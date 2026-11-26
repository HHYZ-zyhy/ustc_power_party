"""日志：访问日志为单行 JSON（便于 journald/检索），业务日志走普通格式化。

绝不记录 Authorization、token、请求体；IP 仅在配置允许时记录。
"""

from __future__ import annotations

import json
import logging
import sys
from datetime import datetime, timezone

ACCESS_LOGGER = "warrior_store.access"
APP_LOGGER = "warrior_store"


def setup_logging(level: str) -> None:
    """初始化进程日志；重复调用只更新级别。"""
    app_logger = logging.getLogger(APP_LOGGER)
    app_logger.setLevel(level.upper())
    app_logger.propagate = False
    if not app_logger.handlers:
        stream = logging.StreamHandler(sys.stdout)
        stream.setFormatter(logging.Formatter("%(asctime)s %(levelname)s %(message)s"))
        app_logger.addHandler(stream)

    access_logger = logging.getLogger(ACCESS_LOGGER)
    access_logger.setLevel(level.upper())
    access_logger.propagate = False
    if not access_logger.handlers:
        stream = logging.StreamHandler(sys.stdout)
        stream.setFormatter(logging.Formatter("%(message)s"))
        access_logger.addHandler(stream)


def log_access(
    *,
    method: str,
    path: str,
    status: int,
    duration_ms: float,
    ip: str | None = None,
    player_id: str | None = None,
) -> None:
    """输出一条访问日志（JSON 行）。"""
    record: dict[str, object] = {
        "ts": datetime.now(timezone.utc).isoformat(timespec="milliseconds").replace("+00:00", "Z"),
        "method": method,
        "path": path,
        "status": status,
        "dur_ms": round(duration_ms, 1),
    }
    if ip:
        record["ip"] = ip
    if player_id:
        record["player_id"] = player_id
    logging.getLogger(ACCESS_LOGGER).info(json.dumps(record, ensure_ascii=False, separators=(",", ":")))
