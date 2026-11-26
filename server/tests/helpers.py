"""HTTP 测试工具：临时服务上下文、请求封装与测试配置构造。

- ``running_server(config)``：后台线程跑 ``serve_forever``，yield 服务句柄与 base_url；
  退出时 ``shutdown`` + ``server_close`` 并带超时 join。
- ``http_request(...)``：用 ``http.client`` 发请求（避免 urlopen 对 4xx/5xx 抛异常），
  返回 ``(status, headers, body)``；响应头键统一小写，204/空体返回 None。
- ``make_config(tmpdir, **overrides)``：随机端口 + 临时数据库 + 关闭访问日志。
"""

from __future__ import annotations

import http.client
import json
import threading
from contextlib import contextmanager
from http.server import ThreadingHTTPServer
from pathlib import Path
from typing import Iterator
from urllib.parse import urlsplit

from app.config import Config
from app.main import make_server


@contextmanager
def running_server(config: Config) -> Iterator[tuple[ThreadingHTTPServer, str]]:
    """在后台线程启动服务，yield ``(server, base_url)``，退出时彻底关闭。"""
    server = make_server(config)
    # 缩短轮询间隔，让测试收尾更快（serve_forever 的默认间隔为 0.5 秒）。
    thread = threading.Thread(
        target=server.serve_forever,
        kwargs={"poll_interval": 0.05},
        name="test-server",
        daemon=True,
    )
    thread.start()
    try:
        host = str(server.server_address[0])
        if host in ("0.0.0.0", "::", ""):
            host = "127.0.0.1"
        port = int(server.server_address[1])
        yield server, f"http://{host}:{port}"
    finally:
        server.shutdown()
        server.server_close()
        thread.join(timeout=10)


def http_request(
    method: str,
    url: str,
    body: object = None,
    token: str | None = None,
    headers: dict[str, str] | None = None,
    timeout: float = 10,
) -> tuple[int, dict[str, str], object]:
    """发一个 HTTP 请求。

    ``body`` 非 bytes 时自动 ``json.dumps`` 并加 ``Content-Type: application/json``；
    bytes 原样发送（用于构造非法 JSON）。返回 ``(status, headers, body)``：
    响应头键为小写；响应无体或 204 时 body 为 None；非 JSON 响应返回原始 bytes。
    """
    parts = urlsplit(url)
    path = parts.path or "/"
    if parts.query:
        path = f"{path}?{parts.query}"

    payload: bytes | None = None
    request_headers: dict[str, str] = {"Accept": "application/json"}
    if headers:
        request_headers.update(headers)
    if body is not None:
        if isinstance(body, (bytes, bytearray)):
            payload = bytes(body)
        else:
            payload = json.dumps(body, ensure_ascii=False).encode("utf-8")
        request_headers.setdefault("Content-Type", "application/json")
    if token is not None:
        request_headers["Authorization"] = f"Bearer {token}"

    connection = http.client.HTTPConnection(parts.hostname, parts.port, timeout=timeout)
    try:
        connection.request(method, path, body=payload, headers=request_headers)
        response = connection.getresponse()
        status = response.status
        response_headers = {name.lower(): value for name, value in response.getheaders()}
        raw = response.read()
    finally:
        connection.close()

    if not raw:
        return status, response_headers, None
    try:
        return status, response_headers, json.loads(raw.decode("utf-8"))
    except (UnicodeDecodeError, json.JSONDecodeError):
        return status, response_headers, raw


def make_config(tmpdir: object, **overrides: object) -> Config:
    """构造测试配置：默认随机端口、临时数据库、关闭访问日志。"""
    values: dict[str, object] = {
        "host": "127.0.0.1",
        "port": 0,
        "db_path": Path(str(tmpdir)) / "store.sqlite3",
        "access_log": False,
        "log_ip": False,
    }
    values.update(overrides)
    if "db_path" in values and not isinstance(values["db_path"], Path):
        values["db_path"] = Path(str(values["db_path"]))
    return Config(**values)  # type: ignore[arg-type]
