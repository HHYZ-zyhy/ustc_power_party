#!/usr/bin/env python3
"""从 backup.py 生成的快照恢复科大战力党玩家数据库（仅标准库，跨平台）。

流程：解压/复制到目标同目录临时文件 → 校验 schema（user_version=1 且
players/stats/result_events 三表齐全）与 PRAGMA integrity_check → 目标已
存在且未加 --force 时拒绝覆盖 →（可选）把旧 WAL/SHM/journal 暂存到同目录
隐藏名 → os.replace 原子替换 → 清理暂存文件 → 尝试修正属主与权限。

恢复前务必先停止服务，否则运行中的进程仍持有旧数据库句柄：

    sudo systemctl stop warrior-store
    sudo python3 restore.py --backup /var/lib/warrior-store/backups/warrior-store-YYYYmmdd-HHMMSS.sqlite3.gz \\
        --db /var/lib/warrior-store/store.sqlite3 --force --remove-wal
    sudo chown warrior-store:warrior-store /var/lib/warrior-store/store.sqlite3
    sudo systemctl start warrior-store
    curl -sS http://127.0.0.1:8080/healthz

默认会检查 ``systemctl is-active --quiet warrior-store``：服务仍在运行时拒绝
恢复（请先 ``systemctl stop warrior-store``）；确知服务未占用数据库时可加
``--allow-running`` 跳过该检查。没有 systemd 的环境自动跳过。

旧库旁的 store.sqlite3-wal / -shm / -journal 会在 SQLite 下次打开时被重放，
可能把崩溃前的数据“复活”到新快照上。因此检测到残留时脚本默认拒绝恢复
（--force 也不能跳过）；确认服务已停止后加 --remove-wal，让脚本在完整性
校验通过后、替换之前把这些 sidecar 改名为同目录隐藏文件，替换成功后再删除；
替换失败则改名还原，保证可回滚。

目标路径已存在但不是普通文件（目录/设备等），或是符号链接时，脚本拒绝恢复，
避免误替换链接本身。空库、其他应用的库、schema 版本不符的备份同样拒绝。

在 root 下运行时，脚本会把恢复后的数据库属主改回旧目标文件的属主；旧文件
不存在时尝试使用 warrior-store 用户（系统无该用户则跳过）。Windows 或非
root 环境自动跳过属主处理。

退出码：0 = 成功；1 = 失败（中文原因输出到 stderr）。
"""

from __future__ import annotations

import argparse
import gzip
import os
import shlex
import shutil
import sqlite3
import subprocess
import sys
import tempfile
import zlib
from pathlib import Path
from typing import Sequence

SERVICE_USER = "warrior-store"
SERVICE_NAME = "warrior-store"
SIDECAR_SUFFIXES = ("-wal", "-shm", "-journal")
SCHEMA_VERSION = 1
REQUIRED_TABLES = ("players", "stats", "result_events")


class RestoreError(Exception):
    """恢复过程中的可预期错误（消息直接展示给运维人员）。"""


def parse_args(argv: Sequence[str] | None = None) -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="从 SQLite 快照恢复科大战力党玩家数据库",
    )
    parser.add_argument(
        "--backup",
        required=True,
        help="备份文件路径（支持 .sqlite3 与 .sqlite3.gz）",
    )
    parser.add_argument(
        "--db",
        required=True,
        help="目标数据库路径（例如 /var/lib/warrior-store/store.sqlite3）",
    )
    parser.add_argument(
        "--force",
        action="store_true",
        help="目标数据库已存在时允许覆盖（不加强制项则拒绝）",
    )
    parser.add_argument(
        "--remove-wal",
        action="store_true",
        help=(
            "完整性校验通过后把目标库旁的旧 WAL/SHM/journal 暂存再替换。"
            "仅在服务已停止时使用；不加本项时检测到残留会拒绝恢复"
        ),
    )
    parser.add_argument(
        "--allow-running",
        action="store_true",
        help=(
            "跳过“warrior-store 服务仍在运行”检查。仅在确认没有进程占用"
            "数据库时使用（例如容器/非 systemd 环境）"
        ),
    )
    return parser.parse_args(list(argv) if argv is not None else None)


def _looks_gzip(path: Path) -> bool:
    if path.name.lower().endswith(".gz"):
        return True
    try:
        with open(path, "rb") as handle:
            return handle.read(2) == b"\x1f\x8b"
    except OSError:
        return False


def _materialize(backup: Path, temp: Path) -> None:
    """把备份（必要时解压）写到临时文件。"""
    if _looks_gzip(backup):
        try:
            with gzip.open(backup, "rb") as src, open(temp, "wb") as dst:
                shutil.copyfileobj(src, dst, length=1024 * 1024)
        except (OSError, EOFError, zlib.error) as exc:
            raise RestoreError(
                f"解压备份失败（备份文件可能损坏或不完整）：{exc}"
            ) from exc
    else:
        try:
            shutil.copyfile(backup, temp)
        except OSError as exc:
            raise RestoreError(f"复制备份失败：{exc}") from exc


def _validate_database(path: Path) -> None:
    """确认备份内容是本服务的非空 version 1 数据库且完整性良好。"""
    try:
        conn = sqlite3.connect(path.resolve().as_uri() + "?mode=ro", uri=True, timeout=10)
        try:
            page_row = conn.execute("PRAGMA page_count").fetchone()
            page_count = int(page_row[0]) if page_row else 0
            if page_count <= 0:
                raise RestoreError("备份内容是空数据库（page_count=0），拒绝恢复")

            version_row = conn.execute("PRAGMA user_version").fetchone()
            version = int(version_row[0]) if version_row else 0
            tables = {
                str(row[0])
                for row in conn.execute(
                    "SELECT name FROM sqlite_master WHERE type = 'table'"
                )
            }
            rows = conn.execute("PRAGMA integrity_check").fetchall()
        finally:
            conn.close()
    except sqlite3.Error as exc:
        raise RestoreError(f"备份文件不是有效的 SQLite 数据库：{exc}") from exc

    if version != SCHEMA_VERSION:
        if version > SCHEMA_VERSION:
            raise RestoreError(
                f"备份文件的 schema 版本为 {version}，高于本脚本支持的 "
                f"{SCHEMA_VERSION}，拒绝恢复（请使用更新版本的恢复脚本）"
            )
        raise RestoreError(
            f"备份文件的 schema 版本为 {version}（应为 {SCHEMA_VERSION}），"
            "不是本服务的数据库或从未初始化，拒绝恢复"
        )

    missing = [name for name in REQUIRED_TABLES if name not in tables]
    if missing:
        raise RestoreError(
            "备份文件缺少本服务必需的表："
            + "、".join(missing)
            + "（不是本服务的数据库），拒绝恢复"
        )

    if rows != [("ok",)]:
        detail = "; ".join(str(row[0]) for row in rows) if rows else "无返回"
        raise RestoreError(f"备份文件完整性校验失败（integrity_check 不为 ok）：{detail}")


def _service_is_active() -> bool:
    """查询 warrior-store 服务是否在运行；无 systemctl/非 systemd 时返回 False。"""
    systemctl = shutil.which("systemctl")
    if systemctl is None:
        return False
    try:
        completed = subprocess.run(
            [systemctl, "is-active", "--quiet", SERVICE_NAME],
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
            timeout=5,
            check=False,
        )
    except (OSError, subprocess.SubprocessError):
        return False
    return completed.returncode == 0


def _existing_sidecars(db_path: Path) -> list[Path]:
    """返回目标库旁实际存在的 WAL/SHM/journal 文件。"""
    paths = [Path(f"{db_path}{suffix}") for suffix in SIDECAR_SUFFIXES]
    return [path for path in paths if path.exists() or path.is_symlink()]


def _quiet_unlink(path: Path) -> None:
    try:
        path.unlink(missing_ok=True)
    except OSError:
        pass


def _restore_stashed(stashed: Sequence[tuple[Path, Path]]) -> None:
    """把已改名的旧 sidecar 还原回原位（尽力而为，失败只警告）。"""
    for original, hidden in reversed(list(stashed)):
        try:
            os.replace(hidden, original)
        except OSError as exc:
            print(
                f"警告：无法还原旧文件 {original}（暂存于 {hidden}）：{exc}",
                file=sys.stderr,
                flush=True,
            )


def _stash_sidecars(sidecars: Sequence[Path]) -> list[tuple[Path, Path]]:
    """把旧 sidecar 改名为同目录隐藏文件，返回 (原路径, 暂存路径) 列表。

    sidecar 暂时移走而不是直接删除；只有数据库替换成功后才真正删除，
    替换失败调用 ``_restore_stashed`` 即可回滚。
    """
    stashed: list[tuple[Path, Path]] = []
    pid = os.getpid()
    for path in sidecars:
        if path.exists() and not path.is_file():
            _restore_stashed(stashed)
            raise RestoreError(
                f"旧 sidecar 不是普通文件（可能是目录/设备），拒绝处理：{path}"
            )
        hidden = path.with_name(f".{path.name}.restore-old-{pid}")
        try:
            os.replace(path, hidden)
        except OSError as exc:
            _restore_stashed(stashed)
            raise RestoreError(
                f"暂存旧 sidecar 失败（已还原已处理文件）：{path}：{exc}"
            ) from exc
        stashed.append((path, hidden))
    return stashed


def _remove_stashed(stashed: Sequence[tuple[Path, Path]]) -> None:
    """替换成功后删除暂存的旧 sidecar；删不掉只警告，不影响恢复结果。"""
    for _original, hidden in stashed:
        try:
            hidden.unlink()
        except FileNotFoundError:
            continue
        except OSError as exc:
            print(
                f"警告：无法删除旧 sidecar 暂存文件 {hidden}：{exc}",
                file=sys.stderr,
                flush=True,
            )


def _fsync_file(path: Path) -> None:
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


def _record_owner(db_path: Path) -> tuple[int, int] | None:
    """记录替换前的目标文件属主（不存在则返回 None）。"""
    try:
        stat = db_path.stat()
    except OSError:
        return None
    return (stat.st_uid, stat.st_gid)


def _chown_after_replace(db_path: Path, old_owner: tuple[int, int] | None) -> bool:
    """尝试把恢复后的数据库属主改回旧属主；返回是否已设置成功。"""
    if not hasattr(os, "geteuid"):
        print("提示：当前平台不支持 POSIX 属主操作，跳过 chown。", flush=True)
        return False
    if os.geteuid() != 0:
        print("提示：当前用户不是 root，跳过自动 chown。", flush=True)
        return False

    owner = old_owner
    source = "旧目标文件"
    if owner is None:
        try:
            import pwd  # 仅 POSIX 有；Windows 上不会走到这里
        except ImportError:
            print("提示：当前平台没有 pwd 模块，跳过自动 chown。", flush=True)
            return False
        try:
            entry = pwd.getpwnam(SERVICE_USER)
        except KeyError:
            print(
                f"提示：旧目标文件不存在，系统中也没有 {SERVICE_USER} 用户，跳过自动 chown。",
                flush=True,
            )
            return False
        owner = (entry.pw_uid, entry.pw_gid)
        source = f"{SERVICE_USER} 用户"

    try:
        os.chown(db_path, owner[0], owner[1])
    except OSError as exc:
        print(f"警告：自动 chown 失败：{exc}", file=sys.stderr, flush=True)
        return False
    print(f"已设置属主 {owner[0]}:{owner[1]}（来源：{source}）。", flush=True)
    return True


def main(argv: Sequence[str] | None = None) -> int:
    args = parse_args(argv)
    backup_path = Path(args.backup).expanduser()
    db_path = Path(args.db).expanduser()

    if not backup_path.exists():
        print(f"恢复失败：备份文件不存在：{backup_path}", file=sys.stderr)
        return 1
    if not backup_path.is_file():
        print(f"恢复失败：备份路径不是普通文件：{backup_path}", file=sys.stderr)
        return 1

    if _service_is_active():
        if not args.allow_running:
            print(
                "恢复失败：检测到 warrior-store 服务正在运行。\n"
                "  运行中的进程仍持有旧数据库句柄，直接替换可能丢数据或让旧事务\n"
                "  在下次打开时覆盖恢复结果。请先停止服务：\n"
                "    sudo systemctl stop warrior-store\n"
                "  停止后重试。若确认没有进程占用数据库（例如容器环境），\n"
                "  可追加 --allow-running 跳过本检查。",
                file=sys.stderr,
            )
            return 1
        print(
            "警告：已加 --allow-running，跳过“服务正在运行”检查；"
            "请自行确认没有进程占用数据库。",
            file=sys.stderr,
            flush=True,
        )

    if db_path.is_symlink():
        print(
            f"恢复失败：目标路径是符号链接：{db_path}\n"
            "  为避免替换链接本身（而不是链接指向的数据库），请先删除该链接，\n"
            "  或改用链接指向的真实路径后重试。",
            file=sys.stderr,
        )
        return 1
    if db_path.exists() and not db_path.is_file():
        print(
            f"恢复失败：目标路径已存在但不是普通文件（可能是目录/设备）：{db_path}",
            file=sys.stderr,
        )
        return 1

    sidecars = _existing_sidecars(db_path)
    if sidecars and not args.remove_wal:
        print("恢复失败：检测到旧数据库的 WAL/SHM/journal 残留文件：", file=sys.stderr)
        for path in sidecars:
            print(f"  {path}", file=sys.stderr)
        print(
            "  SQLite 下次打开数据库时会重放这些文件中的旧事务，可能让恢复结果\n"
            "  “复活”崩溃前的数据。因此脚本默认拒绝恢复（--force 也不能跳过）。\n"
            "  请先停止服务，确认没有进程占用数据库，再删除残留后重试：",
            file=sys.stderr,
        )
        print(
            "    " + " ".join(["rm -f", *(shlex.quote(str(path)) for path in sidecars)]),
            file=sys.stderr,
        )
        print(
            "  或追加 --remove-wal，让脚本在校验通过后、替换之前自动处理。",
            file=sys.stderr,
        )
        return 1

    parent = db_path.parent if str(db_path.parent) else Path(".")
    try:
        parent.mkdir(parents=True, exist_ok=True)
    except OSError as exc:
        print(f"恢复失败：无法创建目标目录 {parent}：{exc}", file=sys.stderr)
        return 1

    temp_path: Path | None = None
    owner_set = False
    stashed: list[tuple[Path, Path]] = []
    try:
        fd, tmp_name = tempfile.mkstemp(
            prefix=".warrior-store-restore-",
            suffix=".sqlite3.tmp",
            dir=str(parent),
        )
        temp_path = Path(tmp_name)
        os.close(fd)

        print("提示：恢复前应先执行 sudo systemctl stop warrior-store。", flush=True)
        print(f"备份文件：{backup_path}", flush=True)
        print(f"目标数据库：{db_path}", flush=True)

        print("[1/4] 解压/复制到临时文件...", flush=True)
        _materialize(backup_path, temp_path)
        if temp_path.stat().st_size == 0:
            raise RestoreError("备份内容为空（0 字节），拒绝恢复")

        print("[2/4] 校验备份 schema 与完整性...", flush=True)
        _validate_database(temp_path)
        print("       schema 与完整性校验通过（ok）。", flush=True)

        if db_path.exists() and not args.force:
            print(
                f"恢复失败：目标数据库已存在：{db_path}\n"
                "为避免误覆盖，未加 --force 时不允许替换。确认要覆盖请追加 --force。",
                file=sys.stderr,
            )
            return 1

        if sidecars:
            print("[3/4] 暂存旧 WAL/SHM/journal 并原子替换目标数据库...", flush=True)
            stashed = _stash_sidecars(sidecars)
        else:
            print("[3/4] 原子替换目标数据库...", flush=True)

        old_owner = _record_owner(db_path)
        try:
            _fsync_file(temp_path)
            os.replace(temp_path, db_path)
        except OSError as exc:
            _restore_stashed(stashed)
            stashed = []
            raise RestoreError(f"替换目标数据库失败（旧 sidecar 已还原）：{exc}") from exc

        temp_path = None
        _fsync_dir(parent)
        if stashed:
            print("[4/4] 清理已替换的旧 sidecar...", flush=True)
            _remove_stashed(stashed)
            stashed = []
        owner_set = _chown_after_replace(db_path, old_owner)
    except RestoreError as exc:
        _restore_stashed(stashed)
        print(f"恢复失败：{exc}", file=sys.stderr)
        return 1
    except sqlite3.Error as exc:
        _restore_stashed(stashed)
        print(f"恢复失败：SQLite 错误（备份可能不是有效的数据库）：{exc}", file=sys.stderr)
        return 1
    except OSError as exc:
        _restore_stashed(stashed)
        print(f"恢复失败：文件操作错误：{exc}", file=sys.stderr)
        return 1
    except Exception as exc:  # 兜底：保证临时文件被清理且退出码为 1
        _restore_stashed(stashed)
        print(f"恢复失败（未预期错误）：{type(exc).__name__}: {exc}", file=sys.stderr)
        return 1
    finally:
        if temp_path is not None:
            _quiet_unlink(temp_path)

    try:
        os.chmod(db_path, 0o600)
    except OSError as exc:
        print(f"警告：无法把 {db_path} 权限设为 0600：{exc}", file=sys.stderr)

    print(f"恢复完成：{db_path}", flush=True)
    print("后续步骤（root）：", flush=True)
    if not owner_set:
        print(f"  sudo chown {SERVICE_USER}:{SERVICE_USER} {db_path}", flush=True)
    print("  sudo systemctl start warrior-store", flush=True)
    print("  sudo systemctl status warrior-store --no-pager", flush=True)
    print("  curl -sS http://127.0.0.1:8080/healthz", flush=True)
    return 0


if __name__ == "__main__":
    sys.exit(main())
