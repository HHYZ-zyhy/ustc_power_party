"""服务配置：命令行参数优先，其次环境变量，最后内置默认值。"""

from __future__ import annotations

import argparse
import os
from dataclasses import dataclass
from pathlib import Path
from typing import Mapping, Sequence

from . import __version__

_TRUE_VALUES = {"1", "true", "yes", "on"}
_FALSE_VALUES = {"0", "false", "no", "off"}
_LOG_LEVELS = {"DEBUG", "INFO", "WARNING", "ERROR", "CRITICAL"}


@dataclass(frozen=True)
class Config:
    """运行配置。测试可直接构造，无需解析环境变量。"""

    host: str = "127.0.0.1"
    port: int = 8080
    db_path: Path = Path("data/store.sqlite3")
    pepper: str = ""
    log_level: str = "INFO"
    log_ip: bool = True
    access_log: bool = True
    register_per_hour: int = 20
    results_per_hour: int = 600
    trust_proxy: bool = False
    version: str = __version__


def _env_int(env: Mapping[str, str], name: str, default: int) -> int:
    raw = env.get(name)
    if raw is None or not raw.strip():
        return default
    try:
        return int(raw.strip())
    except ValueError as exc:
        raise ValueError(f"环境变量 {name} 必须是整数，当前为 {raw!r}") from exc


def _env_bool(env: Mapping[str, str], name: str, default: bool) -> bool:
    raw = env.get(name)
    if raw is None or not raw.strip():
        return default
    value = raw.strip().lower()
    if value in _TRUE_VALUES:
        return True
    if value in _FALSE_VALUES:
        return False
    raise ValueError(f"环境变量 {name} 只能是 1/0，当前为 {raw!r}")


def load_config(
    argv: Sequence[str] | None = None,
    env: Mapping[str, str] | None = None,
) -> Config:
    """解析配置；argv 为 None 时读取 sys.argv。"""
    env = os.environ if env is None else env
    parser = argparse.ArgumentParser(
        prog="warrior-store",
        description="科大战力党玩家数据存储服务（只存 PVE/PVP 场次与胜场）",
    )
    # 默认值留到 parse_args 之后再取：命令行显式给出时，不应先解析（可能非法的）
    # 环境变量，否则 ``WARRIOR_STORE_PORT=bad --port 9000`` 会误报环境变量错误。
    parser.add_argument(
        "--host",
        default=None,
        help="监听地址，默认取 WARRIOR_STORE_HOST 或 127.0.0.1（仅本机）",
    )
    parser.add_argument(
        "--port",
        type=int,
        default=None,
        help="监听端口，默认取 WARRIOR_STORE_PORT 或 8080（0 = 随机端口，测试用）",
    )
    parser.add_argument(
        "--db",
        default=None,
        help="SQLite 数据库路径，默认取 WARRIOR_STORE_DB 或 data/store.sqlite3",
    )
    parser.add_argument(
        "--log-level",
        default=None,
        help="日志级别：DEBUG/INFO/WARNING/ERROR/CRITICAL，默认取 WARRIOR_STORE_LOG_LEVEL 或 INFO",
    )
    args = parser.parse_args(list(argv) if argv is not None else None)

    host = str(
        args.host if args.host is not None else env.get("WARRIOR_STORE_HOST", "127.0.0.1")
    ).strip()
    if not host:
        raise ValueError("监听地址不能为空")

    port = args.port if args.port is not None else _env_int(env, "WARRIOR_STORE_PORT", 8080)
    if not 0 <= int(port) <= 65535:
        raise ValueError("端口必须在 0~65535 之间")
    port = int(port)

    db_raw = str(
        args.db if args.db is not None else env.get("WARRIOR_STORE_DB", "data/store.sqlite3")
    ).strip()
    if not db_raw:
        raise ValueError("数据库路径不能为空")
    if db_raw == ":memory:" or db_raw.startswith("file:"):
        raise ValueError("数据库路径必须是普通文件路径（不支持内存库 :memory: 或 URI）")

    log_level_raw = str(
        args.log_level if args.log_level is not None else env.get("WARRIOR_STORE_LOG_LEVEL", "INFO")
    )
    log_level = log_level_raw.strip().upper()
    if log_level not in _LOG_LEVELS:
        raise ValueError(f"日志级别无效：{log_level_raw!r}")

    register_per_hour = _env_int(env, "WARRIOR_STORE_REGISTER_PER_HOUR", 20)
    if register_per_hour < 0:
        raise ValueError("WARRIOR_STORE_REGISTER_PER_HOUR 不能为负数（0 = 关闭限流）")

    results_per_hour = _env_int(env, "WARRIOR_STORE_RESULTS_PER_HOUR", 600)
    if results_per_hour < 0:
        raise ValueError("WARRIOR_STORE_RESULTS_PER_HOUR 不能为负数（0 = 关闭限流）")

    return Config(
        host=host,
        port=port,
        db_path=Path(db_raw).expanduser(),
        pepper=env.get("WARRIOR_STORE_PEPPER", ""),
        log_level=log_level,
        log_ip=_env_bool(env, "WARRIOR_STORE_LOG_IP", True),
        access_log=_env_bool(env, "WARRIOR_STORE_ACCESS_LOG", True),
        register_per_hour=register_per_hour,
        results_per_hour=results_per_hour,
        trust_proxy=_env_bool(env, "WARRIOR_STORE_TRUST_PROXY", False),
    )
