"""SQLite 存储层：玩家资料、PVE/PVP 统计与上报幂等事件。

设计要点：

- 每次方法调用使用独立短连接（``isolation_level=None``，手动事务），
  不跨线程共享连接；连接在 ``finally`` 中关闭。
- 写操作统一 ``BEGIN IMMEDIATE``：先拿写锁再读改写，避免并发下计数丢失；
  遇到 ``locked``/``busy`` 时最多重试 5 次，其余异常原样抛出。
- 公开字典只含玩家资料与统计，token 哈希只能通过 ``get_token_hash`` 读取。
- schema 版本由 ``PRAGMA user_version`` 管理，当前为 1；更高版本直接拒绝启动。
"""

from __future__ import annotations

import sqlite3
import time
from contextlib import contextmanager
from datetime import datetime, timezone
from decimal import Decimal, ROUND_HALF_UP
from pathlib import Path
from typing import Callable, Iterator, TypeVar

_SCHEMA_VERSION = 1

# 写事务遇锁时的重试次数与退避基数（秒）
_WRITE_ATTEMPTS = 5
_RETRY_SLEEP_BASE = 0.02

# 幂等事件每玩家最多保留的条数（只保留最近写入的）。
# 默认上报上限 600 次/小时，保留 2000 条可覆盖约 3 小时满速上报，
# 避免客户端稍晚重试时因记录被清理而重复计数。
_EVENT_KEEP_LATEST = 2000

_SCHEMA_STATEMENTS: tuple[str, ...] = (
    """
    CREATE TABLE players (
        id TEXT PRIMARY KEY,
        nickname TEXT NOT NULL,
        token_hash BLOB NOT NULL,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL
    )
    """,
    """
    CREATE TABLE stats (
        player_id TEXT NOT NULL REFERENCES players(id) ON DELETE CASCADE,
        mode TEXT NOT NULL CHECK (mode IN ('pve', 'pvp')),
        games INTEGER NOT NULL DEFAULT 0 CHECK (games >= 0),
        wins INTEGER NOT NULL DEFAULT 0 CHECK (wins >= 0 AND wins <= games),
        PRIMARY KEY (player_id, mode)
    )
    """,
    """
    CREATE TABLE result_events (
        player_id TEXT NOT NULL REFERENCES players(id) ON DELETE CASCADE,
        event_id TEXT NOT NULL,
        created_at TEXT NOT NULL,
        PRIMARY KEY (player_id, event_id)
    )
    """,
)

_T = TypeVar("_T")


def _utc_now() -> str:
    """当前 UTC 时间，格式与 API 约定一致（秒级 ISO8601，``Z`` 结尾）。"""
    return datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")


def _win_rate(games: int, wins: int) -> float | None:
    """胜率：保留 4 位小数（四舍五入）；无场次时为 None。

    不用内置 ``round``：它采用银行家舍入（1/32 = 0.03125 会得到 0.0312）。
    """
    if games == 0:
        return None
    rate = Decimal(wins) / Decimal(games)
    return float(rate.quantize(Decimal("0.0001"), rounding=ROUND_HALF_UP))


def _stat_block(games: int, wins: int) -> dict:
    """构造单一模式的统计字典。"""
    return {"games": games, "wins": wins, "win_rate": _win_rate(games, wins)}


def _is_busy_error(exc: sqlite3.OperationalError) -> bool:
    """SQLite 的锁冲突错误（不同平台/版本文案不同，按关键字判断）。"""
    message = str(exc).lower()
    return "locked" in message or "busy" in message


class Store:
    """玩家数据存储。

    所有方法都是短连接、可跨线程调用；并发写由 SQLite 串行化，
    应用层通过 ``BEGIN IMMEDIATE`` + 有限重试避免少计与长时间报错。
    """

    def __init__(self, db_path: str | Path) -> None:
        self._db_path = Path(db_path)

    # ------------------------------------------------------------------
    # 连接与事务基础设施
    # ------------------------------------------------------------------

    @contextmanager
    def _connect(self) -> Iterator[sqlite3.Connection]:
        """打开一个短连接并设置连接级 PRAGMA；无论成败都在 finally 关闭。"""
        conn = sqlite3.connect(str(self._db_path), isolation_level=None)
        try:
            conn.row_factory = sqlite3.Row
            conn.execute("PRAGMA busy_timeout=5000")
            conn.execute("PRAGMA foreign_keys=ON")
            conn.execute("PRAGMA synchronous=FULL")
            yield conn
        finally:
            conn.close()

    def _read(self, operation: Callable[[sqlite3.Connection], _T]) -> _T:
        """在独立只读连接上执行查询。"""
        with self._connect() as conn:
            return operation(conn)

    def _write(self, operation: Callable[[sqlite3.Connection], _T]) -> _T:
        """在 ``BEGIN IMMEDIATE`` 写事务中执行操作，遇锁有限重试。

        操作内抛出的任何异常都会触发 ROLLBACK 后原样上抛；
        只有 ``locked``/``busy`` 类型的 ``OperationalError`` 才会重试。
        """
        for attempt in range(_WRITE_ATTEMPTS):
            try:
                with self._connect() as conn:
                    conn.execute("BEGIN IMMEDIATE")
                    try:
                        value = operation(conn)
                        conn.execute("COMMIT")
                        return value
                    except BaseException:
                        try:
                            conn.execute("ROLLBACK")
                        except sqlite3.Error:
                            # 连接已失效或事务已被回滚时忽略，保留原始异常。
                            pass
                        raise
            except sqlite3.OperationalError as exc:
                if not _is_busy_error(exc) or attempt + 1 >= _WRITE_ATTEMPTS:
                    raise
                time.sleep(_RETRY_SLEEP_BASE * (attempt + 1))
        # 循环内要么返回要么抛出，这里仅为满足类型检查。
        raise RuntimeError("写事务重试流程异常结束")  # pragma: no cover

    # ------------------------------------------------------------------
    # 生命周期
    # ------------------------------------------------------------------

    def init(self) -> None:
        """创建父目录、开启 WAL 并建表（``user_version`` 0 → 1，可重复调用）。"""
        self._db_path.parent.mkdir(parents=True, exist_ok=True)
        if self._db_path.exists() and self._db_path.is_dir():
            raise RuntimeError(f"数据库路径是目录，无法作为 SQLite 文件：{self._db_path}")

        # journal_mode 不能在事务内切换，先用独立连接设置。
        with self._connect() as conn:
            conn.execute("PRAGMA journal_mode=WAL").fetchone()

        def migrate(conn: sqlite3.Connection) -> None:
            version = int(conn.execute("PRAGMA user_version").fetchone()[0])
            if version > _SCHEMA_VERSION:
                raise RuntimeError(
                    f"数据库 schema 版本 {version} 高于程序支持的 {_SCHEMA_VERSION}，"
                    "请升级服务端程序"
                )
            if 0 < version < _SCHEMA_VERSION:
                raise RuntimeError(
                    f"数据库 schema 版本 {version} 过旧，当前程序需要 {_SCHEMA_VERSION}，"
                    "但缺少对应的迁移步骤；请使用旧版程序或手动迁移"
                )
            if version == 0:
                for statement in _SCHEMA_STATEMENTS:
                    conn.execute(statement)
                conn.execute(f"PRAGMA user_version = {_SCHEMA_VERSION}")

        self._write(migrate)
        if not self.ping():
            raise RuntimeError("数据库初始化后自检失败：表缺失或 schema 版本不匹配")

    def ping(self) -> bool:
        """健康检查：数据库文件存在、schema 版本匹配且三张表都可读。

        不能用 ``sqlite3.connect`` 后 ``SELECT 1`` 判断：文件缺失时 SQLite 会
        新建空库并让 ``SELECT 1`` 成功，从而在数据库被删除后误报健康。
        """
        try:
            if not self._db_path.is_file():
                return False
            with self._connect() as conn:
                version = int(conn.execute("PRAGMA user_version").fetchone()[0])
                if version != _SCHEMA_VERSION:
                    return False
                tables = {
                    row[0]
                    for row in conn.execute(
                        "SELECT name FROM sqlite_master WHERE type = 'table'"
                    ).fetchall()
                }
                if not {"players", "stats", "result_events"} <= tables:
                    return False
                conn.execute("SELECT 1 FROM players LIMIT 1").fetchone()
            return True
        except Exception:
            return False

    # ------------------------------------------------------------------
    # 玩家资料
    # ------------------------------------------------------------------

    def create_player(self, player_id: str, nickname: str, token_hash: bytes) -> dict:
        """创建玩家并初始化 pve/pvp 两行零统计。

        ID 冲突时让 ``sqlite3.IntegrityError`` 上抛，由 HTTP 层重新生成 ID 重试。
        """
        now = _utc_now()

        def insert(conn: sqlite3.Connection) -> None:
            conn.execute(
                "INSERT INTO players (id, nickname, token_hash, created_at, updated_at)"
                " VALUES (?, ?, ?, ?, ?)",
                (player_id, nickname, token_hash, now, now),
            )
            conn.executemany(
                "INSERT INTO stats (player_id, mode, games, wins) VALUES (?, ?, 0, 0)",
                ((player_id, "pve"), (player_id, "pvp")),
            )

        self._write(insert)
        player = self.get_player(player_id)
        if player is None:  # pragma: no cover - 事务提交后不应读不到
            raise RuntimeError("创建玩家后读取失败")
        return player

    def get_player(self, player_id: str) -> dict | None:
        """按 ID 返回公开字典；不存在返回 None。"""
        players = self.get_players([player_id])
        return players[0] if players else None

    def get_players(self, player_ids: list[str]) -> list[dict]:
        """批量查询公开资料。

        用一条 players 查询 + 一条 stats 查询（避免 N+1）；按输入顺序返回，
        未知 ID 省略，重复 ID 按重复次数返回。
        """
        if not player_ids:
            return []

        unique_ids = list(dict.fromkeys(player_ids))
        placeholders = ",".join("?" for _ in unique_ids)

        def query(conn: sqlite3.Connection):
            # 两条 SELECT 必须处于同一读快照，否则并发删除会在两次查询之间
            # 造成“玩家存在但统计为 0/0”的不一致结果。
            conn.execute("BEGIN")
            try:
                player_rows = conn.execute(
                    f"SELECT id, nickname, created_at FROM players"
                    f" WHERE id IN ({placeholders})",
                    unique_ids,
                ).fetchall()
                stat_rows = conn.execute(
                    f"SELECT player_id, mode, games, wins FROM stats"
                    f" WHERE player_id IN ({placeholders})",
                    unique_ids,
                ).fetchall()
            except BaseException:
                conn.execute("ROLLBACK")
                raise
            conn.execute("COMMIT")
            return player_rows, stat_rows

        player_rows, stat_rows = self._read(query)

        players_by_id = {row["id"]: row for row in player_rows}
        stats_by_id: dict[str, dict[str, tuple[int, int]]] = {}
        for row in stat_rows:
            stats_by_id.setdefault(row["player_id"], {})[row["mode"]] = (
                int(row["games"]),
                int(row["wins"]),
            )

        result: list[dict] = []
        for player_id in player_ids:
            row = players_by_id.get(player_id)
            if row is None:
                continue
            modes = stats_by_id.get(player_id, {})
            pve_games, pve_wins = modes.get("pve", (0, 0))
            pvp_games, pvp_wins = modes.get("pvp", (0, 0))
            result.append(
                {
                    "player_id": row["id"],
                    "short_id": row["id"][:6],
                    "nickname": row["nickname"],
                    "created_at": row["created_at"],
                    "pve": _stat_block(pve_games, pve_wins),
                    "pvp": _stat_block(pvp_games, pvp_wins),
                }
            )
        return result

    def get_token_hash(self, player_id: str) -> bytes | None:
        """读取 token 哈希（仅供鉴权层使用）；玩家不存在返回 None。"""
        def query(conn: sqlite3.Connection) -> bytes | None:
            row = conn.execute(
                "SELECT token_hash FROM players WHERE id = ?", (player_id,)
            ).fetchone()
            if row is None:
                return None
            return bytes(row["token_hash"])

        return self._read(query)

    def update_nickname(self, player_id: str, nickname: str) -> dict | None:
        """更新昵称与 updated_at；成功返回最新公开字典，玩家不存在返回 None。"""
        now = _utc_now()

        def update(conn: sqlite3.Connection) -> bool:
            cursor = conn.execute(
                "UPDATE players SET nickname = ?, updated_at = ? WHERE id = ?",
                (nickname, now, player_id),
            )
            return cursor.rowcount > 0

        if not self._write(update):
            return None
        return self.get_player(player_id)

    # ------------------------------------------------------------------
    # 战绩上报
    # ------------------------------------------------------------------

    def record_result(
        self,
        player_id: str,
        mode: str,
        result: str,
        event_id: str | None,
    ) -> dict | None:
        """记录一场 PVE/PVP 结果，返回两种模式的最新统计。

        同一写事务内完成：确认玩家存在 → 幂等检查/写入 event_id →
        ``stats`` 自增 → 清理过期幂等记录。玩家不存在返回 None。
        """
        # mode/result 由 HTTP 层先行校验；这里用断言兜住误用。
        assert mode in ("pve", "pvp"), f"非法 mode: {mode!r}"
        assert result in ("win", "loss"), f"非法 result: {result!r}"
        wins_increment = 1 if result == "win" else 0
        now = _utc_now()

        def record(conn: sqlite3.Connection) -> dict | None:
            exists = conn.execute(
                "SELECT 1 FROM players WHERE id = ?", (player_id,)
            ).fetchone()
            if exists is None:
                return None

            duplicate = False
            if event_id is not None:
                seen = conn.execute(
                    "SELECT 1 FROM result_events WHERE player_id = ? AND event_id = ?",
                    (player_id, event_id),
                ).fetchone()
                if seen is not None:
                    duplicate = True
                else:
                    conn.execute(
                        "INSERT INTO result_events (player_id, event_id, created_at)"
                        " VALUES (?, ?, ?)",
                        (player_id, event_id, now),
                    )

            if not duplicate:
                conn.execute(
                    "INSERT INTO stats (player_id, mode, games, wins)"
                    " VALUES (?, ?, 1, ?)"
                    " ON CONFLICT(player_id, mode) DO UPDATE SET"
                    " games = games + 1, wins = wins + excluded.wins",
                    (player_id, mode, wins_increment),
                )
                if event_id is not None:
                    # 幂等记录每玩家只保留最近 500 条，写入成功后顺带清理。
                    conn.execute(
                        "DELETE FROM result_events WHERE player_id = ? AND event_id NOT IN"
                        " (SELECT event_id FROM result_events WHERE player_id = ?"
                        " ORDER BY rowid DESC LIMIT ?)",
                        (player_id, player_id, _EVENT_KEEP_LATEST),
                    )

            stat_rows = conn.execute(
                "SELECT mode, games, wins FROM stats WHERE player_id = ?",
                (player_id,),
            ).fetchall()
            stats = {
                row["mode"]: (int(row["games"]), int(row["wins"]))
                for row in stat_rows
            }
            pve_games, pve_wins = stats.get("pve", (0, 0))
            pvp_games, pvp_wins = stats.get("pvp", (0, 0))
            return {
                "pve": _stat_block(pve_games, pve_wins),
                "pvp": _stat_block(pvp_games, pvp_wins),
                "duplicate": duplicate,
            }

        return self._write(record)

    # ------------------------------------------------------------------
    # 删除
    # ------------------------------------------------------------------

    def delete_player(self, player_id: str) -> bool:
        """删除玩家；stats/result_events 由外键 ``ON DELETE CASCADE`` 级联删除。"""
        def delete(conn: sqlite3.Connection) -> bool:
            cursor = conn.execute("DELETE FROM players WHERE id = ?", (player_id,))
            return cursor.rowcount > 0

        return self._write(delete)
