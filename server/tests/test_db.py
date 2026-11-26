"""Store 存储层单元测试：schema、CRUD、幂等、级联删除、持久化与并发。"""

from __future__ import annotations

import hashlib
import sqlite3
import tempfile
import threading
import unittest
from pathlib import Path
from unittest import mock

from app import db as db_module
from app.db import Store


def _player_id(number: int) -> str:
    """构造合法的确定性玩家 ID（p_ + 16 位小写十六进制）。"""
    return "p_" + f"{number:016x}"


def _token_hash(token: str) -> bytes:
    return hashlib.sha256(token.encode("utf-8")).digest()


class StoreTest(unittest.TestCase):
    def setUp(self) -> None:
        self._tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self._tmp.cleanup)
        self.db_path = Path(self._tmp.name) / "store.sqlite3"
        self.store = Store(self.db_path)
        self.store.init()

    # ------------------------------------------------------------------
    # 测试辅助
    # ------------------------------------------------------------------

    def _create(self, number: int, nickname: str | None = None) -> dict:
        player_id = _player_id(number)
        return self.store.create_player(
            player_id,
            nickname if nickname is not None else f"玩家{number}",
            _token_hash(f"token-{number}"),
        )

    def _scalar(self, sql: str, params: tuple = ()):
        conn = sqlite3.connect(self.db_path)
        try:
            row = conn.execute(sql, params).fetchone()
            return None if row is None else row[0]
        finally:
            conn.close()

    def _count(self, table: str, player_id: str) -> int:
        return int(
            self._scalar(f"SELECT COUNT(*) FROM {table} WHERE player_id = ?", (player_id,))
        )

    def _table_names(self) -> set[str]:
        conn = sqlite3.connect(self.db_path)
        try:
            rows = conn.execute("SELECT name FROM sqlite_master WHERE type = 'table'").fetchall()
            return {row[0] for row in rows}
        finally:
            conn.close()

    # ------------------------------------------------------------------
    # schema 与初始化
    # ------------------------------------------------------------------

    def test_init_sets_version_and_creates_tables(self) -> None:
        self.assertEqual(self._scalar("PRAGMA user_version"), 1)
        self.assertTrue({"players", "stats", "result_events"} <= self._table_names())
        self.assertEqual(self._scalar("PRAGMA journal_mode"), "wal")
        # 用标准 sqlite3 能直接打开（上面的 _scalar 已隐含验证）。
        self.assertEqual(self._scalar("PRAGMA integrity_check"), "ok")

    def test_init_is_idempotent(self) -> None:
        player = self._create(1)

        self.store.init()
        self.store.init()

        self.assertEqual(self._scalar("PRAGMA user_version"), 1)
        self.assertEqual(self.store.get_player(player["player_id"]), player)

    def test_init_creates_parent_directories(self) -> None:
        nested = Path(self._tmp.name) / "a" / "b" / "c" / "store.sqlite3"
        store = Store(nested)
        store.init()
        self.assertTrue(nested.is_file())
        self.assertTrue(store.ping())

    def test_init_rejects_newer_schema(self) -> None:
        future = Path(self._tmp.name) / "future.sqlite3"
        conn = sqlite3.connect(future)
        try:
            conn.execute("PRAGMA user_version = 2")
            conn.commit()
        finally:
            conn.close()
        with self.assertRaises(RuntimeError):
            Store(future).init()

    def test_init_rejects_old_schema_without_migration(self) -> None:
        # 已有 v1 库、程序期望 v2：必须 fail-fast，不能静默按旧 schema 运行。
        with mock.patch.object(db_module, "_SCHEMA_VERSION", 2):
            with self.assertRaises(RuntimeError):
                Store(self.db_path).init()

    def test_init_rejects_directory_path(self) -> None:
        with self.assertRaises(RuntimeError):
            Store(Path(self._tmp.name)).init()

    # ------------------------------------------------------------------
    # 创建 / 查询
    # ------------------------------------------------------------------

    def test_create_and_get_public_shape(self) -> None:
        player_id = _player_id(2)
        token_hash = _token_hash("secret-2")
        created = self.store.create_player(player_id, "科大甲", token_hash)

        self.assertEqual(
            set(created),
            {"player_id", "short_id", "nickname", "created_at", "pve", "pvp"},
        )
        self.assertEqual(created["player_id"], player_id)
        self.assertEqual(created["short_id"], player_id[:6])
        self.assertEqual(len(created["short_id"]), 6)
        self.assertEqual(created["nickname"], "科大甲")
        self.assertRegex(created["created_at"], r"^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}Z$")
        self.assertEqual(created["pve"], {"games": 0, "wins": 0, "win_rate": None})
        self.assertEqual(created["pvp"], {"games": 0, "wins": 0, "win_rate": None})
        self.assertNotIn("token_hash", created)
        self.assertNotIn("token", created)

        self.assertEqual(self.store.get_player(player_id), created)
        self.assertEqual(self.store.get_token_hash(player_id), token_hash)

    def test_unknown_player_returns_none(self) -> None:
        missing = _player_id(999)
        self.assertIsNone(self.store.get_player(missing))
        self.assertIsNone(self.store.get_token_hash(missing))

    def test_duplicate_id_raises_integrity_error(self) -> None:
        player = self._create(3)
        with self.assertRaises(sqlite3.IntegrityError):
            self.store.create_player(player["player_id"], "重复 ID", _token_hash("x"))
        # 失败事务必须完整回滚，原玩家资料不变。
        stored = self.store.get_player(player["player_id"])
        self.assertEqual(stored, player)
        self.assertEqual(self._count("stats", player["player_id"]), 2)

    def test_nicknames_can_repeat_and_stats_are_independent(self) -> None:
        first = self._create(4, "同名玩家")
        second = self._create(5, "同名玩家")
        self.assertEqual(first["nickname"], second["nickname"])
        self.assertNotEqual(first["player_id"], second["player_id"])

        self.store.record_result(first["player_id"], "pve", "win", None)

        self.assertEqual(self.store.get_player(first["player_id"])["pve"]["games"], 1)
        self.assertEqual(self.store.get_player(second["player_id"])["pve"]["games"], 0)
        self.assertIsNone(self.store.get_player(second["player_id"])["pve"]["win_rate"])

    def test_get_players_order_missing_and_duplicates(self) -> None:
        first = self._create(10)
        second = self._create(11)
        third = self._create(12)
        missing = _player_id(999)

        result = self.store.get_players(
            [third["player_id"], missing, first["player_id"], third["player_id"]]
        )
        self.assertEqual(
            [player["player_id"] for player in result],
            [third["player_id"], first["player_id"], third["player_id"]],
        )
        self.assertEqual(self.store.get_players([]), [])

    # ------------------------------------------------------------------
    # 改昵称
    # ------------------------------------------------------------------

    def test_update_nickname(self) -> None:
        player = self._create(20, "旧昵称")
        updated = self.store.update_nickname(player["player_id"], "新昵称")

        self.assertIsNotNone(updated)
        self.assertEqual(updated["nickname"], "新昵称")
        self.assertEqual(updated["created_at"], player["created_at"])
        self.assertEqual(updated["pve"], player["pve"])
        self.assertEqual(self.store.get_player(player["player_id"]), updated)

    def test_update_nickname_unknown_player(self) -> None:
        self.assertIsNone(self.store.update_nickname(_player_id(999), "无主"))

    # ------------------------------------------------------------------
    # 战绩上报
    # ------------------------------------------------------------------

    def test_record_result_modes_and_win_rates(self) -> None:
        player_id = self._create(30)["player_id"]

        first = self.store.record_result(player_id, "pve", "win", None)
        self.assertEqual(set(first), {"pve", "pvp", "duplicate"})
        self.assertFalse(first["duplicate"])
        self.assertEqual(first["pve"], {"games": 1, "wins": 1, "win_rate": 1.0})
        self.assertEqual(first["pvp"], {"games": 0, "wins": 0, "win_rate": None})

        second = self.store.record_result(player_id, "pve", "loss", None)
        self.assertEqual(second["pve"], {"games": 2, "wins": 1, "win_rate": 0.5})
        self.assertEqual(second["pvp"], {"games": 0, "wins": 0, "win_rate": None})

        third = self.store.record_result(player_id, "pvp", "win", None)
        self.assertEqual(third["pvp"], {"games": 1, "wins": 1, "win_rate": 1.0})
        self.assertEqual(third["pve"], {"games": 2, "wins": 1, "win_rate": 0.5})

        fourth = self.store.record_result(player_id, "pve", "loss", None)
        self.assertEqual(fourth["pve"], {"games": 3, "wins": 1, "win_rate": 0.3333})

        # 查询接口与上报返回值一致。
        self.assertEqual(self.store.get_player(player_id)["pve"], fourth["pve"])
        self.assertEqual(self.store.get_player(player_id)["pvp"], third["pvp"])

    def test_record_result_event_id_is_idempotent(self) -> None:
        player_id = self._create(31)["player_id"]

        first = self.store.record_result(player_id, "pve", "win", "evt-00000001")
        self.assertFalse(first["duplicate"])
        self.assertEqual(first["pve"]["games"], 1)

        repeat = self.store.record_result(player_id, "pve", "win", "evt-00000001")
        self.assertTrue(repeat["duplicate"])
        self.assertEqual(repeat["pve"], {"games": 1, "wins": 1, "win_rate": 1.0})

        another = self.store.record_result(player_id, "pve", "loss", "evt-00000002")
        self.assertFalse(another["duplicate"])
        self.assertEqual(another["pve"], {"games": 2, "wins": 1, "win_rate": 0.5})

        self.assertEqual(self._count("result_events", player_id), 2)

    def test_record_result_keeps_latest_events(self) -> None:
        keep = db_module._EVENT_KEEP_LATEST
        player_id = self._create(32)["player_id"]
        for index in range(keep + 5):
            self.store.record_result(player_id, "pve", "win", f"evt{index:08d}")

        self.assertEqual(self._count("result_events", player_id), keep)
        self.assertEqual(self.store.get_player(player_id)["pve"]["games"], keep + 5)

        # 最早的 5 条已被清理，重新上报会被当作新事件。
        oldest = self.store.record_result(player_id, "pve", "win", "evt00000000")
        self.assertFalse(oldest["duplicate"])
        self.assertEqual(oldest["pve"]["games"], keep + 6)
        self.assertEqual(self._count("result_events", player_id), keep)

    def test_record_result_unknown_player(self) -> None:
        missing = _player_id(999)
        self.assertIsNone(self.store.record_result(missing, "pve", "win", "evt-00000001"))
        self.assertEqual(self._count("result_events", missing), 0)
        self.assertEqual(self._count("stats", missing), 0)

    def test_win_rate_rounds_half_up(self) -> None:
        # 1/32 = 0.03125：Python round() 是银行家舍入会得到 0.0312，
        # 这里要求常规四舍五入 0.0313。
        player_id = self._create(33)["player_id"]
        self.store.record_result(player_id, "pve", "win", "evt-win-0001")
        for index in range(31):
            self.store.record_result(player_id, "pve", "loss", f"evt-loss-{index:04d}")
        self.assertEqual(self.store.get_player(player_id)["pve"]["win_rate"], 0.0313)

    # ------------------------------------------------------------------
    # 删除
    # ------------------------------------------------------------------

    def test_delete_player_cascades(self) -> None:
        player_id = self._create(40)["player_id"]
        self.store.record_result(player_id, "pve", "win", "evt-delete-1")

        self.assertTrue(self.store.delete_player(player_id))
        self.assertIsNone(self.store.get_player(player_id))
        self.assertIsNone(self.store.get_token_hash(player_id))
        self.assertEqual(self._count("stats", player_id), 0)
        self.assertEqual(self._count("result_events", player_id), 0)
        self.assertFalse(self.store.delete_player(player_id))

    # ------------------------------------------------------------------
    # 持久化与健康检查
    # ------------------------------------------------------------------

    def test_data_survives_store_recreation(self) -> None:
        player = self._create(50, "持久化")
        player_id = player["player_id"]
        self.store.record_result(player_id, "pvp", "win", "evt-persist-1")

        reopened = Store(self.db_path)
        reopened.init()

        stored = reopened.get_player(player_id)
        self.assertIsNotNone(stored)
        self.assertEqual(stored["nickname"], "持久化")
        self.assertEqual(stored["created_at"], player["created_at"])
        self.assertEqual(stored["pvp"], {"games": 1, "wins": 1, "win_rate": 1.0})
        self.assertEqual(reopened.get_token_hash(player_id), _token_hash("token-50"))

    def test_ping_ok_and_false(self) -> None:
        self.assertTrue(self.store.ping())

        blocker = Path(self._tmp.name) / "blocker"
        blocker.write_text("not a directory", encoding="utf-8")
        unusable = Store(blocker / "nested" / "store.sqlite3")
        self.assertFalse(unusable.ping())

    def test_ping_false_after_database_files_removed(self) -> None:
        self.assertTrue(self.store.ping())

        # 删除主库与 WAL/SHM 伴生文件后，ping 必须失败且不得重新创建空库。
        for suffix in ("", "-wal", "-shm"):
            Path(str(self.db_path) + suffix).unlink(missing_ok=True)
        self.assertFalse(self.store.ping())
        self.assertFalse(self.db_path.exists())
        self.assertFalse(self.store.ping())

    def test_ping_false_when_table_missing(self) -> None:
        conn = sqlite3.connect(self.db_path)
        try:
            conn.execute("DROP TABLE stats")
            conn.commit()
        finally:
            conn.close()
        self.assertFalse(self.store.ping())

    # ------------------------------------------------------------------
    # 并发
    # ------------------------------------------------------------------

    def test_concurrent_record_result_counts_exactly(self) -> None:
        player_id = self._create(60)["player_id"]
        thread_count = 8
        per_thread = 250
        expected_wins = sum(
            1
            for thread_index in range(thread_count)
            for index in range(per_thread)
            if (thread_index + index) % 2 == 0
        )

        errors: list[str] = []
        lock = threading.Lock()

        def worker(thread_index: int) -> None:
            try:
                for index in range(per_thread):
                    result = "win" if (thread_index + index) % 2 == 0 else "loss"
                    event_id = f"evt-t{thread_index}-i{index:04d}"
                    outcome = self.store.record_result(player_id, "pve", result, event_id)
                    if outcome is None:
                        raise AssertionError("record_result 对已存在玩家返回了 None")
            except Exception as exc:  # noqa: BLE001 - 汇总后统一断言
                with lock:
                    errors.append(f"线程 {thread_index}: {exc!r}")

        workers = [
            threading.Thread(target=worker, args=(thread_index,), name=f"writer-{thread_index}")
            for thread_index in range(thread_count)
        ]
        for thread in workers:
            thread.start()
        for thread in workers:
            thread.join(timeout=180)

        stuck = [thread.name for thread in workers if thread.is_alive()]
        if stuck:
            self.fail(f"并发写入未在 180 秒内完成，仍存活：{stuck}")
        if errors:
            self.fail(
                "并发写入出现异常：" + "; ".join(errors[:5]) + f"（共 {len(errors)} 条）"
            )

        stats = self.store.get_player(player_id)["pve"]
        self.assertEqual(stats["games"], thread_count * per_thread)
        self.assertEqual(stats["wins"], expected_wins)
        self.assertEqual(stats["win_rate"], round(expected_wins / (thread_count * per_thread), 4))
        self.assertEqual(self._count("stats", player_id), 2)
        self.assertEqual(
            self._count("result_events", player_id), db_module._EVENT_KEEP_LATEST
        )
        self.assertEqual(self._scalar("PRAGMA integrity_check"), "ok")


if __name__ == "__main__":
    unittest.main()
