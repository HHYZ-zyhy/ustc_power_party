#!/usr/bin/env python3
"""科大战力党玩家数据存储服务：SQLite 一致性快照备份（仅标准库，跨平台）。

使用 SQLite 官方 backup API 生成一致性快照（运行中也可备份），
快照完成后做 PRAGMA integrity_check，再按需 gzip 压缩并轮转旧备份。

安全要点：

- 源库只用 ``mode=rw`` URI 打开（绝不因路径错误而新建空库），并校验
  ``page_count > 0``、``user_version == 1`` 且三张业务表都存在；不合格
  时退出 1，不写最终备份、不轮转。
- 临时文件一律用 ``tempfile.mkstemp`` 生成（不可预测文件名，0600），
  任何异常都会清理；启动时顺带清理超过 24 小时的残留 ``.tmp``。
- 最终文件先 fsync 再 ``os.replace``，替换后 fsync 目录（Windows 上目录
  fsync 不可用则忽略）。
- 轮转只匹配 ``warrior-store-<时间戳>[-序号].sqlite3[.gz]``，按文件名
  时间戳排序（mtime 仅兜底），并排除源库与本次生成的最终文件。

用法：
    python3 backup.py --db /var/lib/warrior-store/store.sqlite3
    python3 backup.py --db store.sqlite3 --out-dir backups --keep 7
    python3 backup.py --db store.sqlite3 --out-dir backups --no-gzip

退出码：0 = 成功；1 = 失败（中文原因输出到 stderr）。
"""

from __future__ import annotations

import argparse
import gzip
import os
import re
import shutil
import sqlite3
import sys
import tempfile
import time
from datetime import datetime
from pathlib import Path
from typing import Sequence

FILE_PREFIX = "warrior-store-"
DEFAULT_OUT_DIR = "/var/lib/warrior-store/backups"
DEFAULT_KEEP = 14
SCHEMA_VERSION = 1
REQUIRED_TABLES = ("players", "stats", "result_events")

# 只认本脚本生成的备份文件名（严格匹配，避免误删运维手工放置的文件）。
_BACKUP_NAME_RE = re.compile(
    r"^warrior-store-(\d{8}-\d{6})(?:-(\d+))?\.sqlite3(?:\.gz)?$"
)
_STALE_TEMP_SECONDS = 24 * 60 * 60


class BackupError(Exception):
    """备份过程中的可预期错误（消息直接展示给运维人员）。"""


def parse_args(argv: Sequence[str] | None = None) -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="科大战力党玩家数据存储服务：SQLite 一致性快照备份",
    )
    parser.add_argument(
        "--db",
        required=True,
        help="源数据库路径（例如 /var/lib/warrior-store/store.sqlite3）",
    )
    parser.add_argument(
        "--out-dir",
        default=DEFAULT_OUT_DIR,
        help=f"备份输出目录，默认 {DEFAULT_OUT_DIR}",
    )
    parser.add_argument(
        "--keep",
        type=int,
        default=DEFAULT_KEEP,
        help=f"只保留最新多少份本脚本生成的备份，默认 {DEFAULT_KEEP}（至少 1）",
    )
    parser.add_argument(
        "--no-gzip",
        action="store_true",
        help="不压缩，直接保留 .sqlite3 文件（默认 gzip 压缩为 .sqlite3.gz）",
    )
    return parser.parse_args(list(argv) if argv is not None else None)


def _connect_existing(path: Path) -> sqlite3.Connection:
    """以 ``mode=rw`` 打开已存在的数据库；绝不会新建或清空文件。"""
    uri = path.resolve().as_uri() + "?mode=rw"
    conn = sqlite3.connect(uri, uri=True, timeout=10)
    conn.execute("PRAGMA busy_timeout = 10000")
    return conn


def _validate_source(db_path: Path) -> None:
    """确认源库是本服务的非空 version 1 数据库，否则拒绝备份。"""
    try:
        conn = _connect_existing(db_path)
        try:
            page_row = conn.execute("PRAGMA page_count").fetchone()
            version_row = conn.execute("PRAGMA user_version").fetchone()
            tables = {
                str(row[0])
                for row in conn.execute(
                    "SELECT name FROM sqlite_master WHERE type = 'table'"
                )
            }
        finally:
            conn.close()
    except sqlite3.Error as exc:
        raise BackupError(
            f"源数据库无法以只读方式打开（可能不是有效的 SQLite 数据库）：{exc}"
        ) from exc

    page_count = int(page_row[0]) if page_row else 0
    version = int(version_row[0]) if version_row else 0

    if page_count <= 0:
        raise BackupError("源数据库是空库（page_count=0），拒绝生成空备份")
    if version != SCHEMA_VERSION:
        if version > SCHEMA_VERSION:
            raise BackupError(
                f"源数据库 schema 版本为 {version}，高于本脚本支持的 "
                f"{SCHEMA_VERSION}，拒绝备份（请使用更新版本的程序）"
            )
        raise BackupError(
            f"源数据库 schema 版本为 {version}（应为 {SCHEMA_VERSION}），"
            "不是本服务的数据库或尚未初始化，拒绝备份"
        )

    missing = [name for name in REQUIRED_TABLES if name not in tables]
    if missing:
        raise BackupError(
            "源数据库缺少本服务必需的表：" + "、".join(missing) + "，拒绝备份"
        )


def _unique_path(out_dir: Path, stamp: str, compressed: bool) -> Path:
    """生成不冲突的备份文件名；正常情况就是 warrior-store-YYYYmmdd-HHMMSS。"""
    suffix = ".sqlite3.gz" if compressed else ".sqlite3"
    candidate = out_dir / f"{FILE_PREFIX}{stamp}{suffix}"
    index = 1
    while candidate.exists():
        candidate = out_dir / f"{FILE_PREFIX}{stamp}-{index}{suffix}"
        index += 1
    return candidate


def _snapshot(db_path: Path, dest: Path) -> None:
    """把 db_path 的一致性快照写入 dest，并校验快照完整性。"""
    src = _connect_existing(db_path)
    try:
        dst = sqlite3.connect(str(dest))
        try:
            src.backup(dst)
            rows = dst.execute("PRAGMA integrity_check").fetchall()
        finally:
            dst.close()
    finally:
        src.close()

    if rows != [("ok",)]:
        detail = "; ".join(str(row[0]) for row in rows) if rows else "无返回"
        raise BackupError(f"快照完整性校验失败（integrity_check 不为 ok）：{detail}")


def _quiet_unlink(path: Path) -> None:
    try:
        path.unlink(missing_ok=True)
    except OSError:
        pass


def _fsync_file(path: Path) -> None:
    """把文件内容刷到磁盘；失败时抛 OSError（由调用方转成中文错误）。"""
    with open(path, "rb+") as handle:
        os.fsync(handle.fileno())


def _fsync_dir(path: Path) -> None:
    """尽力 fsync 目录项；Windows 等不支持目录 fsync 的平台直接跳过。"""
    flags = getattr(os, "O_DIRECTORY", 0)
    if flags == 0:
        return
    try:
        fd = os.open(str(path), os.O_RDONLY | flags)
    except OSError:
        return
    try:
        os.fsync(fd)
    except OSError:
        pass
    finally:
        try:
            os.close(fd)
        except OSError:
            pass


def _cleanup_stale_temps(out_dir: Path) -> None:
    """删除超过 24 小时的本脚本临时文件（异常/断电残留）。"""
    cutoff = time.time() - _STALE_TEMP_SECONDS
    for path in out_dir.glob(f"{FILE_PREFIX}*.tmp"):
        try:
            if path.is_file() and path.stat().st_mtime < cutoff:
                path.unlink()
        except OSError:
            continue


def _write_backup(snapshot: Path, final: Path, compress: bool) -> None:
    """把快照写到最终文件名（先临时文件、fsync，再原子替换）。"""
    if not compress:
        try:
            _fsync_file(snapshot)
            os.replace(snapshot, final)
        except OSError as exc:
            raise BackupError(f"写出备份失败：{exc}") from exc
        _fsync_dir(final.parent)
        return

    fd = -1
    gzip_tmp: Path | None = None
    try:
        fd, tmp_name = tempfile.mkstemp(
            prefix=FILE_PREFIX,
            suffix=".tmp",
            dir=str(final.parent),
        )
        gzip_tmp = Path(tmp_name)
        os.chmod(gzip_tmp, 0o600)
        with os.fdopen(fd, "wb") as raw:
            fd = -1
            with gzip.GzipFile(filename="", mode="wb", fileobj=raw, compresslevel=6) as dst:
                with open(snapshot, "rb") as src:
                    shutil.copyfileobj(src, dst, length=1024 * 1024)
            raw.flush()
            os.fsync(raw.fileno())
        os.replace(gzip_tmp, final)
        gzip_tmp = None
    except OSError as exc:
        raise BackupError(f"压缩备份失败：{exc}") from exc
    finally:
        if fd >= 0:
            try:
                os.close(fd)
            except OSError:
                pass
        if gzip_tmp is not None:
            _quiet_unlink(gzip_tmp)

    _fsync_dir(final.parent)


def _rotation_key(path: Path, match: re.Match[str]) -> tuple[str, int, float, str]:
    """排序键：文件名时间戳 → 同秒序号 → mtime（仅兜底）→ 文件名。"""
    try:
        mtime = path.stat().st_mtime
    except OSError:
        mtime = 0.0
    return (match.group(1), int(match.group(2) or 0), mtime, path.name)


def _rotate(
    out_dir: Path,
    keep: int,
    final_path: Path,
    db_path: Path,
) -> int:
    """只保留最新 keep 份本脚本生成的备份（含本次），返回删除数量。

    严格按文件名匹配；源库与本次最终文件永不参与删除。排序以文件名中的
    时间戳/序号为准，避免旧备份 mtime 异常（未来时间）导致新备份被误删。
    """
    try:
        final_resolved = final_path.resolve()
        db_resolved = db_path.resolve()
    except OSError:
        final_resolved = final_path.absolute()
        db_resolved = db_path.absolute()

    candidates: list[tuple[Path, re.Match[str]]] = []
    for path in out_dir.glob(f"{FILE_PREFIX}*"):
        match = _BACKUP_NAME_RE.match(path.name)
        if match is None:
            continue
        try:
            if not path.is_file():
                continue
            resolved = path.resolve()
        except OSError:
            continue
        if resolved == final_resolved or resolved == db_resolved:
            continue
        candidates.append((path, match))

    candidates.sort(key=lambda item: _rotation_key(*item))

    # final_path 占一席，因此其余旧文件最多保留 keep-1 份。
    excess = len(candidates) - max(0, keep - 1)
    removed = 0
    if excess <= 0:
        return 0
    for path, _match in candidates[:excess]:
        try:
            if path.resolve() == final_resolved:
                continue
            path.unlink()
            removed += 1
            print(f"  已删除旧备份：{path}", flush=True)
        except OSError as exc:
            print(f"  警告：无法删除旧备份 {path}：{exc}", file=sys.stderr, flush=True)
    return removed


def _human_size(size: int) -> str:
    value = float(size)
    for unit in ("B", "KiB", "MiB", "GiB"):
        if value < 1024 or unit == "GiB":
            return f"{value:.1f} {unit}" if unit != "B" else f"{int(value)} B"
        value /= 1024
    return f"{size} B"


def main(argv: Sequence[str] | None = None) -> int:
    args = parse_args(argv)
    db_path = Path(args.db).expanduser()
    out_dir = Path(args.out_dir).expanduser()

    if args.keep < 1:
        print("备份失败：--keep 必须 >= 1（表示至少保留 1 份备份）", file=sys.stderr)
        return 1
    if not db_path.exists():
        print(f"备份失败：源数据库不存在：{db_path}", file=sys.stderr)
        return 1
    if not db_path.is_file():
        print(f"备份失败：源数据库不是普通文件：{db_path}", file=sys.stderr)
        return 1

    print(f"源数据库：{db_path}", flush=True)
    print(f"备份目录：{out_dir}", flush=True)

    try:
        out_dir.mkdir(parents=True, exist_ok=True)
    except OSError as exc:
        print(f"备份失败：无法创建备份目录 {out_dir}：{exc}", file=sys.stderr)
        return 1

    _cleanup_stale_temps(out_dir)

    try:
        _validate_source(db_path)
    except BackupError as exc:
        print(f"备份失败：{exc}", file=sys.stderr)
        return 1
    except sqlite3.Error as exc:
        print(f"备份失败：SQLite 错误：{exc}", file=sys.stderr)
        return 1

    stamp = datetime.now().strftime("%Y%m%d-%H%M%S")
    final_path = _unique_path(out_dir, stamp, compressed=not args.no_gzip)

    tmp_path: Path | None = None
    try:
        fd, tmp_name = tempfile.mkstemp(
            prefix=FILE_PREFIX,
            suffix=".tmp",
            dir=str(out_dir),
        )
        tmp_path = Path(tmp_name)
        os.close(fd)
        fd = -1
        os.chmod(tmp_path, 0o600)

        print("[1/3] 生成一致性快照（SQLite backup API）...", flush=True)
        _snapshot(db_path, tmp_path)
        print("[2/3] 校验快照完整性（PRAGMA integrity_check）... ok", flush=True)

        print("[3/3] 写出备份并轮转旧文件...", flush=True)
        _write_backup(tmp_path, final_path, compress=not args.no_gzip)

        if not final_path.is_file():
            raise BackupError(f"备份文件未正确写出：{final_path}")

        # 只有最终文件确认存在后才轮转，避免删掉旧备份却留下半成品。
        removed = _rotate(out_dir, args.keep, final_path, db_path)

        size = final_path.stat().st_size
        print(f"备份完成：{final_path}（{_human_size(size)}）", flush=True)
        if removed == 0:
            print(f"轮转：保留最新 {args.keep} 份，无需删除旧备份。", flush=True)
        else:
            print(f"轮转：保留最新 {args.keep} 份，删除 {removed} 份旧备份。", flush=True)
        return 0
    except BackupError as exc:
        print(f"备份失败：{exc}", file=sys.stderr)
        return 1
    except sqlite3.Error as exc:
        print(f"备份失败：SQLite 错误：{exc}", file=sys.stderr)
        return 1
    except OSError as exc:
        print(f"备份失败：文件操作错误：{exc}", file=sys.stderr)
        return 1
    except Exception as exc:  # 兜底：保证临时文件被清理且退出码为 1
        print(f"备份失败（未预期错误）：{type(exc).__name__}: {exc}", file=sys.stderr)
        return 1
    finally:
        if tmp_path is not None:
            _quiet_unlink(tmp_path)


if __name__ == "__main__":
    sys.exit(main())
