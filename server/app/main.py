"""服务入口：构造 HTTP 服务、运行生命周期与命令行 main。

- ``make_server``：初始化日志与数据库，返回可直接 ``serve_forever`` 的服务句柄；
  ``port=0`` 时由系统分配端口，调用方可读 ``server.server_address[1]``。
- ``run``：阻塞运行；SIGTERM/SIGINT 在单独线程调用 ``shutdown()``，避免死锁。
- ``main``：解析配置；配置非法时打印中文错误并以 2 退出。
"""

from __future__ import annotations

import logging
import signal
import sqlite3
import sys
import threading
import time
from http.server import ThreadingHTTPServer

from .config import Config, load_config
from .db import Store
from .http_api import ApiHandler
from .log import APP_LOGGER, setup_logging
from .ratelimit import RateLimiter


class StoreHTTPServer(ThreadingHTTPServer):
    """HTTP 服务句柄：把配置、存储、限流器与启动时间挂到 server 上供 handler 使用。"""

    daemon_threads = True
    allow_reuse_address = True
    # 默认 backlog 只有 5；低并发场景也容易被瞬时连接打满。
    request_queue_size = 128

    def __init__(self, address: tuple[str, int], config: Config, store: Store) -> None:
        super().__init__(address, ApiHandler)
        self.config = config
        self.store = store
        self.started_at = time.monotonic()
        self.logger = logging.getLogger(APP_LOGGER)
        self.register_limiter = RateLimiter(config.register_per_hour)
        # 上报限流每玩家每小时 config.results_per_hour 次（默认 600，0 = 关闭）。
        self.result_limiter = RateLimiter(config.results_per_hour)


def make_server(config: Config, store: Store | None = None) -> ThreadingHTTPServer:
    """创建并初始化 HTTP 服务（不启动 serve_forever）。"""
    setup_logging(config.log_level)
    if store is None:
        store = Store(config.db_path)
    store.init()
    return StoreHTTPServer((config.host, config.port), config, store)


def run(config: Config) -> int:
    """启动服务并阻塞直到收到停止信号；返回进程退出码。"""
    server = make_server(config)
    logger = server.logger
    host, port = server.server_address[0], server.server_address[1]
    logger.info("玩家数据存储服务已启动：http://%s:%s（数据库：%s）", host, port, config.db_path)

    def _request_shutdown(signum, _frame) -> None:
        """信号处理：另起线程调用 shutdown()，避免与 serve_forever 同线程死锁。"""
        logger.info("收到信号 %s，正在停止服务…", signum)
        threading.Thread(target=server.shutdown, name="shutdown", daemon=True).start()

    previous_handlers: dict[int, object] = {}
    for signum in (signal.SIGTERM, signal.SIGINT):
        try:
            previous_handlers[signum] = signal.signal(signum, _request_shutdown)
        except (ValueError, OSError):
            # 非主线程或平台不支持时忽略信号注册。
            pass

    try:
        server.serve_forever()
    finally:
        for signum, handler in previous_handlers.items():
            try:
                signal.signal(signum, handler)
            except (ValueError, OSError, TypeError):
                pass
        server.server_close()
        logger.info("服务已停止")
    return 0


def main(argv: list[str] | None = None) -> int:
    """命令行入口：解析配置后运行；配置非法返回 2。"""
    try:
        config = load_config(argv)
    except ValueError as exc:
        print(f"配置错误：{exc}", file=sys.stderr)
        return 2

    try:
        return run(config)
    except KeyboardInterrupt:
        print("已中断", file=sys.stderr)
        return 0
    except (OSError, sqlite3.Error, RuntimeError) as exc:
        # 常见：端口占用、数据库损坏/路径是目录/schema 过新、权限不足。
        # 不打印 traceback，避免 systemd 日志被噪声淹没。
        print(f"服务启动失败：{exc}", file=sys.stderr)
        return 1
