"""部署脚本测试：backup.py / restore.py 的端到端行为（仅标准库）。

用 ``subprocess`` 调当前解释器运行 ``deploy/`` 下的脚本，所有数据库与备份都
放在 ``tempfile.TemporaryDirectory`` 里；不依赖 root，Windows/Linux 均可运行。
需要 systemctl、符号链接等 POSIX 特性的用例用 ``skipUnless`` 标记。
"""

from __future__ import annotations

import gzip
import os
import shutil
import sqlite3
import stat
import subprocess
import sys
import tempfile
import time
import unittest
from pathlib import Path
from typing import Iterable

DEPLOY_DIR = Path(__file__).resolve().parents[1] / "deploy"

PLAYER_ID = "p_0000000000000001"
SCHEMA_SQL = {
    "players": """
        CREATE TABLE players (
            id TEXT PRIMARY KEY,
            nickname TEXT NOT NULL,
            token_hash BLOB NOT NULL,
            created_at TEXT NOT NULL,
            updated_at TEXT NOT NULL
        )
    """,
    "stats": """
        CREATE TABLE stats (
            player_id TEXT NOT NULL REFERENCES players(id) ON DELETE CASCADE,
            mode TEXT NOT NULL CHECK (mode IN ('pve', 'pvp')),
            games INTEGER NOT NULL DEFAULT 0 CHECK (games >= 0),
            wins INTEGER NOT NULL DEFAULT 0 CHECK (wins >= 0 AND wins <= games),
            PRIMARY KEY (player_id, mode)
        )
    """,
    "result_events": """
        CREATE TABLE result_events (
            player_id TEXT NOT NULL REFERENCES players(id) ON DELETE CASCADE,
            event_id TEXT NOT NULL,
            created_at TEXT NOT NULL,
            PRIMARY KEY (player_id, event_id)
        )
    """,
}
ALL_TABLES = ("players", "stats", "result_events")


def _remove_db_files(path: Path) -> None:
    for candidate in [path, *(Path(f"{path}{suffix}") for suffix in ("-wal", "-shm", "-journal"))]:
        try:
            candidate.unlink()
        except FileNotFoundError:
            continue
        except IsADirectoryError:
            shutil.rmtree(candidate)


def _make_store_db(
    path: Path,
    nickname: str = "alpha",
    *,
    version: int = 1,
    tables: Iterable[str] = ALL_TABLES,
) -> None:
    """建一个与本服务 schema 一致的最小数据库（默认 user_version=1）。"""
    _remove_db_files(path)
    conn = sqlite3.connect(str(path))
    try:
        created = tuple(tables)
        for name in created:
            conn.execute(SCHEMA_SQL[name])
        conn.execute(f"PRAGMA user_version = {int(version)}")
        if "players" in created:
            conn.execute(
                "INSERT INTO players (id, nickname, token_hash, created_at, updated_at)"
                " VALUES (?, ?, ?, ?, ?)",
                (PLAYER_ID, nickname, b"token-hash", "2026-01-01T00:00:00Z", "2026-01-01T00:00:00Z"),
            )
        if "stats" in created:
            conn.execute(
                "INSERT INTO stats (player_id, mode, games, wins) VALUES (?, 'pve', 3, 2)",
                (PLAYER_ID,),
            )
        conn.commit()
    finally:
        conn.close()


def _make_empty_sqlite(path: Path) -> None:
    """建一个 0 页的空 SQLite 数据库。"""
    conn = sqlite3.connect(str(path))
    conn.close()


def _read_nickname(path: Path) -> str:
    conn = sqlite3.connect(str(path))
    try:
        row = conn.execute(
            "SELECT nickname FROM players WHERE id = ?", (PLAYER_ID,)
        ).fetchone()
    finally:
        conn.close()
    if row is None:
        raise AssertionError(f"数据库 {path} 中找不到测试玩家")
    return str(row[0])


def _set_nickname(path: Path, value: str) -> None:
    conn = sqlite3.connect(str(path))
    try:
        conn.execute("UPDATE players SET nickname = ? WHERE id = ?", (value, PLAYER_ID))
        conn.commit()
    finally:
        conn.close()


def _integrity_ok(path: Path) -> bool:
    conn = sqlite3.connect(str(path))
    try:
        return conn.execute("PRAGMA integrity_check").fetchall() == [("ok",)]
    finally:
        conn.close()


def _read_backup_nickname(backup: Path) -> str:
    """解压（如有）备份到临时文件并读出昵称。"""
    fd, name = tempfile.mkstemp(
        prefix="unpack-", suffix=".sqlite3", dir=str(backup.parent)
    )
    os.close(fd)
    unpacked = Path(name)
    try:
        if backup.name.lower().endswith(".gz"):
            with gzip.open(backup, "rb") as src, open(unpacked, "wb") as dst:
                shutil.copyfileobj(src, dst)
        else:
            shutil.copyfile(backup, unpacked)
        return _read_nickname(unpacked)
    finally:
        unpacked.unlink(missing_ok=True)


class DeployScriptsTest(unittest.TestCase):
    def setUp(self) -> None:
        self._tmp = tempfile.TemporaryDirectory(prefix="warrior-store-deploy-test-")
        self.addCleanup(self._tmp.cleanup)
        self.tmpdir = Path(self._tmp.name)

    # ------------------------------------------------------------------
    # 工具
    # ------------------------------------------------------------------

    def _run(
        self,
        script: str,
        *args: object,
        extra_env: dict[str, str] | None = None,
        path_prefix: Path | None = None,
    ) -> subprocess.CompletedProcess[str]:
        env = os.environ.copy()
        env["PYTHONIOENCODING"] = "utf-8"
        env["PYTHONDONTWRITEBYTECODE"] = "1"
        if path_prefix is not None:
            env["PATH"] = str(path_prefix) + os.pathsep + env.get("PATH", "")
        if extra_env:
            env.update(extra_env)
        return subprocess.run(
            [sys.executable, str(DEPLOY_DIR / script), *(str(arg) for arg in args)],
            cwd=str(self.tmpdir),
            capture_output=True,
            text=True,
            encoding="utf-8",
            errors="replace",
            env=env,
            timeout=120,
        )

    @staticmethod
    def _output(result: subprocess.CompletedProcess[str]) -> str:
        return f"{result.stdout}\n{result.stderr}"

    def _assert_failed(self, result: subprocess.CompletedProcess[str]) -> None:
        self.assertNotEqual(
            result.returncode,
            0,
            f"期望脚本失败但退出码为 0：\n{self._output(result)}",
        )

    def _assert_chinese_failure(
        self, result: subprocess.CompletedProcess[str], needle: str = "失败"
    ) -> None:
        self._assert_failed(result)
        self.assertIn(needle, self._output(result))
        self.assertNotIn("未预期错误", self._output(result))

    def _make_backup(
        self,
        nickname: str = "from-backup",
        *,
        no_gzip: bool = False,
    ) -> Path:
        """用 backup.py 生成一份备份并返回文件路径。"""
        source = self.tmpdir / "source.sqlite3"
        _make_store_db(source, nickname)
        out_dir = self.tmpdir / "backups"
        args: list[object] = ["--db", source, "--out-dir", out_dir, "--keep", 5]
        if no_gzip:
            args.append("--no-gzip")
        result = self._run("backup.py", *args)
        self.assertEqual(
            result.returncode,
            0,
            f"backup.py 应成功：\n{self._output(result)}",
        )
        pattern = "warrior-store-*.sqlite3" if no_gzip else "warrior-store-*.sqlite3.gz"
        files = sorted(out_dir.glob(pattern))
        self.assertEqual(len(files), 1, f"应生成 1 份备份，实际：{files}")
        return files[0]

    # ------------------------------------------------------------------
    # 备份
    # ------------------------------------------------------------------

    def test_backup_creates_valid_gzip(self) -> None:
        source = self.tmpdir / "store.sqlite3"
        _make_store_db(source, "alpha")
        out_dir = self.tmpdir / "backups"

        result = self._run("backup.py", "--db", source, "--out-dir", out_dir, "--keep", 2)
        self.assertEqual(result.returncode, 0, f"backup.py 应成功：\n{self._output(result)}")

        files = list(out_dir.glob("warrior-store-*.sqlite3.gz"))
        self.assertEqual(len(files), 1, f"应生成 1 份 .gz 备份，实际：{files}")
        self.assertEqual(
            list(out_dir.glob("*.tmp")),
            [],
            "成功的备份不应留下 .tmp 临时文件",
        )
        if os.name == "posix":
            mode = stat.S_IMODE(files[0].stat().st_mode)
            self.assertEqual(mode, 0o600, f"备份文件权限应为 0600，实际 {oct(mode)}")

        self.assertEqual(_read_backup_nickname(files[0]), "alpha")

    def test_backup_rotation_keeps_latest(self) -> None:
        source = self.tmpdir / "store.sqlite3"
        _make_store_db(source, "rotate-0")
        out_dir = self.tmpdir / "backups"

        for index in range(3):
            _set_nickname(source, f"rotate-{index}")
            result = self._run(
                "backup.py",
                "--db",
                source,
                "--out-dir",
                out_dir,
                "--keep",
                2,
            )
            self.assertEqual(
                result.returncode,
                0,
                f"第 {index + 1} 次 backup.py 应成功：\n{self._output(result)}",
            )
            if index < 2:
                # 让文件名时间戳可区分，避免同秒备份的顺序歧义。
                time.sleep(1.1)

        files = sorted(out_dir.glob("warrior-store-*"))
        self.assertEqual(
            len(files),
            2,
            f"--keep 2 应只保留 2 份备份，实际：{files}",
        )
        self.assertEqual(
            list(out_dir.glob("*.tmp")),
            [],
            "轮转后不应留下 .tmp 临时文件",
        )
        values = sorted(_read_backup_nickname(path) for path in files)
        self.assertEqual(values, ["rotate-1", "rotate-2"], "应保留最新两次备份内容")

    def test_rotation_skips_source_and_unrelated_names(self) -> None:
        out_dir = self.tmpdir / "backups"
        out_dir.mkdir()
        source = out_dir / "warrior-store-20200101-000000.sqlite3"
        _make_store_db(source, "source-in-outdir")
        source_before = source.read_bytes()
        unrelated = out_dir / "warrior-store-important.sqlite3"
        unrelated.write_bytes(b"do not delete")

        result = self._run(
            "backup.py",
            "--db",
            source,
            "--out-dir",
            out_dir,
            "--keep",
            1,
        )
        self.assertEqual(result.returncode, 0, f"backup.py 应成功：\n{self._output(result)}")

        self.assertTrue(source.exists(), "匹配备份命名的源库不得被轮转删除")
        self.assertEqual(source.read_bytes(), source_before, "源库内容不应被修改")
        self.assertTrue(unrelated.exists(), "不匹配备份命名的文件不得被删除")
        self.assertEqual(unrelated.read_bytes(), b"do not delete")
        gz_files = list(out_dir.glob("warrior-store-*.sqlite3.gz"))
        self.assertEqual(len(gz_files), 1, f"应生成 1 份新备份，实际：{gz_files}")

    def test_rotation_uses_filename_timestamp_not_mtime(self) -> None:
        out_dir = self.tmpdir / "backups"
        out_dir.mkdir()
        older = out_dir / "warrior-store-20000101-000000.sqlite3"
        newer = out_dir / "warrior-store-20000102-000000.sqlite3"
        older.write_bytes(b"old-1")
        newer.write_bytes(b"old-2")
        # 旧文件的 mtime 设到未来：若按 mtime 排序，新备份会被误当成最旧删掉。
        future = time.time() + 10 * 365 * 24 * 60 * 60
        os.utime(older, (future, future))
        os.utime(newer, (1_000_000, 1_000_000))

        source = self.tmpdir / "store.sqlite3"
        _make_store_db(source, "fresh")
        result = self._run(
            "backup.py",
            "--db",
            source,
            "--out-dir",
            out_dir,
            "--keep",
            2,
        )
        self.assertEqual(result.returncode, 0, f"backup.py 应成功：\n{self._output(result)}")

        self.assertFalse(older.exists(), "按文件名时间戳最旧的备份应被删除")
        self.assertTrue(newer.exists(), "按文件名时间戳较新的备份应保留")
        self.assertEqual(newer.read_bytes(), b"old-2")
        new_files = list(out_dir.glob("warrior-store-*.sqlite3.gz"))
        self.assertEqual(len(new_files), 1, f"本次新备份不得被轮转删除：{list(out_dir.iterdir())}")

    def test_backup_rejects_invalid_source(self) -> None:
        cases: list[tuple[str, Path]] = []

        missing = self.tmpdir / "missing.sqlite3"
        cases.append(("missing", missing))

        zero_bytes = self.tmpdir / "zero-bytes.sqlite3"
        zero_bytes.write_bytes(b"")
        cases.append(("zero-bytes", zero_bytes))

        empty_db = self.tmpdir / "empty.sqlite3"
        _make_empty_sqlite(empty_db)
        cases.append(("empty-db", empty_db))

        version_zero = self.tmpdir / "version-zero.sqlite3"
        _make_store_db(version_zero, "v0", version=0)
        cases.append(("version-zero", version_zero))

        version_future = self.tmpdir / "version-99.sqlite3"
        _make_store_db(version_future, "v99", version=99)
        cases.append(("version-99", version_future))

        missing_tables = self.tmpdir / "missing-tables.sqlite3"
        _make_store_db(missing_tables, "partial", tables=("players",))
        cases.append(("missing-tables", missing_tables))

        for name, source in cases:
            with self.subTest(case=name):
                out_dir = self.tmpdir / f"out-{name}"
                out_dir.mkdir()
                sentinel = out_dir / "warrior-store-19990101-000000.sqlite3.gz"
                sentinel.write_bytes(b"sentinel")
                result = self._run(
                    "backup.py",
                    "--db",
                    source,
                    "--out-dir",
                    out_dir,
                    "--keep",
                    1,
                )
                self._assert_chinese_failure(result, "备份失败")
                self.assertNotIn("备份完成", self._output(result))
                self.assertTrue(sentinel.exists(), "源库校验失败时不得轮转删除旧备份")
                self.assertEqual(sentinel.read_bytes(), b"sentinel")
                self.assertEqual(
                    [path.name for path in out_dir.iterdir()],
                    [sentinel.name],
                    "源库校验失败时不应写出任何新备份",
                )

    def test_backup_captures_uncheckpointed_wal(self) -> None:
        source = self.tmpdir / "wal-source.sqlite3"
        _remove_db_files(source)
        conn = sqlite3.connect(str(source))
        try:
            mode = conn.execute("PRAGMA journal_mode = WAL").fetchone()
            self.assertEqual(mode, ("wal",))
            conn.execute(SCHEMA_SQL["players"])
            conn.execute(SCHEMA_SQL["stats"])
            conn.execute(SCHEMA_SQL["result_events"])
            conn.execute("PRAGMA user_version = 1")
            conn.execute(
                "INSERT INTO players (id, nickname, token_hash, created_at, updated_at)"
                " VALUES (?, ?, ?, ?, ?)",
                (PLAYER_ID, "wal-committed", b"hash", "t", "t"),
            )
            conn.commit()
            wal_path = Path(f"{source}-wal")
            self.assertTrue(wal_path.exists(), "连接保持打开时应存在 -wal 文件")

            out_dir = self.tmpdir / "wal-backups"
            result = self._run(
                "backup.py",
                "--db",
                source,
                "--out-dir",
                out_dir,
                "--keep",
                5,
            )
            self.assertEqual(
                result.returncode,
                0,
                f"WAL 模式下 backup.py 应成功：\n{self._output(result)}",
            )
        finally:
            conn.close()

        backups = list(out_dir.glob("warrior-store-*.sqlite3.gz"))
        self.assertEqual(len(backups), 1, f"应生成 1 份备份，实际：{backups}")
        self.assertEqual(
            _read_backup_nickname(backups[0]),
            "wal-committed",
            "备份快照应包含仍在 WAL 中的已提交数据",
        )

        target = self.tmpdir / "wal-restored.sqlite3"
        restored = self._run(
            "restore.py", "--backup", backups[0], "--db", target, "--force"
        )
        self.assertEqual(
            restored.returncode,
            0,
            f"恢复 WAL 快照应成功：\n{self._output(restored)}",
        )
        self.assertEqual(_read_nickname(target), "wal-committed")

    def test_backup_no_gzip_and_restore(self) -> None:
        backup = self._make_backup("plain-value", no_gzip=True)
        self.assertTrue(backup.name.endswith(".sqlite3"))
        self.assertFalse(backup.name.endswith(".gz"))
        self.assertTrue(_integrity_ok(backup))

        target = self.tmpdir / "plain-target.sqlite3"
        result = self._run("restore.py", "--backup", backup, "--db", target, "--force")
        self.assertEqual(
            result.returncode,
            0,
            f"恢复未压缩备份应成功：\n{self._output(result)}",
        )
        self.assertEqual(_read_nickname(target), "plain-value")

    # ------------------------------------------------------------------
    # 恢复
    # ------------------------------------------------------------------

    def test_restore_requires_force(self) -> None:
        backup = self._make_backup("restored-value")
        target = self.tmpdir / "target.sqlite3"
        _make_store_db(target, "original")
        before = target.read_bytes()

        refused = self._run("restore.py", "--backup", backup, "--db", target)
        self._assert_failed(refused)
        self.assertEqual(
            target.read_bytes(),
            before,
            "未加 --force 时目标数据库不应被修改",
        )

        restored = self._run("restore.py", "--backup", backup, "--db", target, "--force")
        self.assertEqual(
            restored.returncode,
            0,
            f"加 --force 后 restore.py 应成功：\n{self._output(restored)}",
        )
        self.assertEqual(_read_nickname(target), "restored-value")
        self.assertEqual(list(self.tmpdir.glob(".*restore-old-*")), [])

    def test_restore_refuses_sidecars_without_remove_wal(self) -> None:
        backup = self._make_backup("after-wal")
        target = self.tmpdir / "target.sqlite3"
        _make_store_db(target, "original")
        before = target.read_bytes()

        sidecars = [Path(f"{target}{suffix}") for suffix in ("-wal", "-shm", "-journal")]
        for sidecar in sidecars:
            sidecar.write_bytes(b"stale sidecar")

        refused = self._run("restore.py", "--backup", backup, "--db", target, "--force")
        self._assert_failed(refused)
        self.assertIn(
            "--remove-wal",
            self._output(refused),
            "拒绝信息应提示 --remove-wal",
        )
        self.assertEqual(target.read_bytes(), before, "拒绝恢复时目标数据库不应被修改")
        self.assertTrue(
            all(sidecar.exists() for sidecar in sidecars),
            "未加 --remove-wal 时不应处理任何 sidecar",
        )

        restored = self._run(
            "restore.py",
            "--backup",
            backup,
            "--db",
            target,
            "--force", "--allow-running",
            "--remove-wal",
        )
        self.assertEqual(
            restored.returncode,
            0,
            f"加 --remove-wal 后 restore.py 应成功：\n{self._output(restored)}",
        )
        self.assertFalse(
            any(sidecar.exists() for sidecar in sidecars),
            "恢复后旧 -wal/-shm/-journal 应被删除",
        )
        self.assertEqual(
            list(self.tmpdir.glob(".*restore-old-*")),
            [],
            "替换成功后不应残留 sidecar 暂存文件",
        )
        self.assertEqual(_read_nickname(target), "after-wal")

    def test_restore_rejects_corrupt_backup(self) -> None:
        target = self.tmpdir / "target.sqlite3"
        _make_store_db(target, "original")
        before = target.read_bytes()

        bad_plain = self.tmpdir / "bad.sqlite3"
        bad_plain.write_bytes(b"this is not a sqlite database")
        bad_gzip = self.tmpdir / "bad.sqlite3.gz"
        bad_gzip.write_bytes(b"\x1f\x8bthis is not gzip data")
        empty = self.tmpdir / "empty-backup.sqlite3"
        empty.write_bytes(b"")

        for bad in (bad_plain, bad_gzip, empty):
            with self.subTest(backup=bad.name):
                result = self._run(
                    "restore.py",
                    "--backup",
                    bad,
                    "--db",
                    target,
                    "--force", "--allow-running",
                )
                self._assert_chinese_failure(result, "恢复失败")
                self.assertNotIn("恢复完成", self._output(result))
                self.assertEqual(
                    target.read_bytes(),
                    before,
                    f"坏备份 {bad.name} 不应修改目标数据库",
                )

    def test_restore_rejects_invalid_schema(self) -> None:
        target = self.tmpdir / "target.sqlite3"
        _make_store_db(target, "original")
        before = target.read_bytes()

        cases: list[tuple[str, Path]] = []
        version_zero = self.tmpdir / "version-zero.sqlite3"
        _make_store_db(version_zero, "v0", version=0)
        cases.append(("version-zero", version_zero))

        version_future = self.tmpdir / "version-99.sqlite3"
        _make_store_db(version_future, "v99", version=99)
        cases.append(("version-99", version_future))

        missing_tables = self.tmpdir / "missing-tables.sqlite3"
        _make_store_db(missing_tables, "partial", tables=("players",))
        cases.append(("missing-tables", missing_tables))

        empty_db = self.tmpdir / "empty.sqlite3"
        _make_empty_sqlite(empty_db)
        cases.append(("empty-db", empty_db))

        foreign = self.tmpdir / "foreign.sqlite3"
        conn = sqlite3.connect(str(foreign))
        try:
            conn.execute("CREATE TABLE other_app (value TEXT)")
            conn.commit()
        finally:
            conn.close()
        cases.append(("foreign-app", foreign))

        for name, bad in cases:
            with self.subTest(case=name):
                result = self._run(
                    "restore.py",
                    "--backup",
                    bad,
                    "--db",
                    target,
                    "--force", "--allow-running",
                )
                self._assert_chinese_failure(result, "恢复失败")
                self.assertNotIn("恢复完成", self._output(result))
                self.assertEqual(
                    target.read_bytes(),
                    before,
                    f"无效 schema 的备份 {name} 不应修改目标数据库",
                )

    def test_restore_rejects_truncated_gzip(self) -> None:
        backup = self._make_backup("truncated")
        data = backup.read_bytes()
        self.assertGreater(len(data), 20)
        truncated = self.tmpdir / "truncated.sqlite3.gz"
        truncated.write_bytes(data[: len(data) // 2])

        target = self.tmpdir / "target.sqlite3"
        _make_store_db(target, "original")
        before = target.read_bytes()

        result = self._run(
            "restore.py",
            "--backup",
            truncated,
            "--db",
            target,
            "--force", "--allow-running",
        )
        self._assert_failed(result)
        output = self._output(result)
        self.assertIn("恢复失败", output)
        self.assertTrue(
            "可能损坏" in output or "不完整" in output,
            f"截断 gzip 应提示备份损坏/不完整：\n{output}",
        )
        self.assertNotIn("未预期错误", output)
        self.assertEqual(target.read_bytes(), before, "截断 gzip 不应修改目标数据库")

    def test_restore_rejects_directory_target(self) -> None:
        backup = self._make_backup("dir-target")
        target = self.tmpdir / "target-dir.sqlite3"
        target.mkdir()

        result = self._run("restore.py", "--backup", backup, "--db", target, "--force")
        self._assert_failed(result)
        self.assertIn("不是普通文件", self._output(result))
        self.assertTrue(target.is_dir(), "目标目录不应被替换")

    @unittest.skipUnless(os.name == "posix", "需要 POSIX 符号链接")
    def test_restore_rejects_symlink_target(self) -> None:
        backup = self._make_backup("link-target")
        real = self.tmpdir / "real.sqlite3"
        _make_store_db(real, "real")
        before = real.read_bytes()
        link = self.tmpdir / "link.sqlite3"
        os.symlink(real, link)

        result = self._run("restore.py", "--backup", backup, "--db", link, "--force")
        self._assert_failed(result)
        self.assertIn("符号链接", self._output(result))
        self.assertTrue(link.is_symlink(), "符号链接本身不应被替换")
        self.assertEqual(real.read_bytes(), before)

    @unittest.skipUnless(os.name == "posix", "需要 POSIX 可执行脚本与 systemctl")
    def test_restore_refuses_running_service(self) -> None:
        backup = self._make_backup("running")
        target = self.tmpdir / "target.sqlite3"
        _make_store_db(target, "original")
        before = target.read_bytes()

        fake_bin = self.tmpdir / "fake-bin"
        fake_bin.mkdir()
        fake_systemctl = fake_bin / "systemctl"
        fake_systemctl.write_text("#!/bin/sh\nexit 0\n", encoding="utf-8")
        fake_systemctl.chmod(0o755)

        refused = self._run(
            "restore.py",
            "--backup",
            backup,
            "--db",
            target,
            "--force",
            path_prefix=fake_bin,
        )
        self._assert_failed(refused)
        self.assertIn("systemctl stop warrior-store", self._output(refused))
        self.assertEqual(target.read_bytes(), before)

        allowed = self._run(
            "restore.py",
            "--backup",
            backup,
            "--db",
            target,
            "--force", "--allow-running",
            path_prefix=fake_bin,
        )
        self.assertEqual(
            allowed.returncode,
            0,
            f"--allow-running 时恢复应成功：\n{self._output(allowed)}",
        )
        self.assertEqual(_read_nickname(target), "running")


if __name__ == "__main__":
    unittest.main()
