"""HTTP 层：路由、请求解析、鉴权、限流与统一错误响应。

只使用标准库 ``http.server``。服务句柄（由 ``main.make_server`` 构造）通过
``self.server`` 提供 ``config`` / ``store`` / ``started_at`` / ``logger`` /
``register_limiter`` / ``result_limiter``；本模块不负责创建服务或数据库。

约定（与 ``API.md`` 一致）：

- 响应固定带 ``Cache-Control: no-store``、``X-Content-Type-Options: nosniff``；
  JSON 为 UTF-8，204 同样带安全头且无响应体。
- 请求体上限 8 KiB，必须带 ``Content-Length``，不支持 chunked。
- 日志绝不记录 Authorization/token/请求体。
"""

from __future__ import annotations

import ipaddress
import json
import sqlite3
import time
from http.server import BaseHTTPRequestHandler
from urllib.parse import parse_qs, urlsplit

from .auth import hash_token, new_player_id, new_token, token_matches
from .errors import (
    ApiError,
    bad_request,
    internal_error,
    method_not_allowed,
    not_found,
    payload_too_large,
    rate_limited,
    unauthorized,
)
from .log import log_access
from .validation import (
    validate_event_id,
    validate_mode,
    validate_nickname,
    validate_player_id,
    validate_result,
)

# 请求体上限（字节）。与 API.md 的 8 KiB 一致。
MAX_BODY_BYTES = 8192
# 出错时最多排空多少请求体再关闭连接：避免客户端已发送的 body 未读就 close，
# 导致 TCP RST 把错误响应丢掉（Windows 上尤其明显）。
MAX_DRAIN_BYTES = 65536
# 批量查询最多 ID 数。
MAX_BATCH_IDS = 50
# 注册时 ID 冲突（几乎不可能）的最大重试次数。
CREATE_ATTEMPTS = 5

# 路由名 -> 允许的方法（405 的 Allow 头按此顺序输出）。
_ALLOWED_METHODS: dict[str, tuple[str, ...]] = {
    "healthz": ("GET",),
    "players": ("GET", "POST"),
    "player": ("GET", "PATCH", "DELETE"),
    "results": ("POST",),
}

_PLAYERS_PATH = "/api/v1/players"
_PLAYERS_PREFIX = _PLAYERS_PATH + "/"

_JSON_CONTENT_TYPE = "application/json; charset=utf-8"
_INVALID_JSON_MESSAGE = "请求体必须是 JSON 对象"


def _resolve_path(path: str) -> tuple[str, str | None]:
    """把 URL path 解析为 (路由名, 路径中的玩家 ID 原文)。

    严格匹配、不容忍多余斜杠；未知路径抛 404，空玩家 ID 抛 400。
    """
    if path == "/healthz":
        return "healthz", None
    if path == _PLAYERS_PATH:
        return "players", None
    if path.startswith(_PLAYERS_PREFIX):
        rest = path[len(_PLAYERS_PREFIX):]
        if not rest:
            raise bad_request("invalid_player_id", "玩家 ID 格式不合法")
        player_id, sep, tail = rest.partition("/")
        if not sep:
            return "player", player_id
        if tail == "results":
            return "results", player_id
    raise not_found("资源不存在")


def _parse_bearer(header: str | None) -> str | None:
    """从 ``Authorization`` 头取出 Bearer token；格式不对返回 None。"""
    if not header:
        return None
    parts = header.split(None, 1)
    if len(parts) != 2:
        return None
    scheme, token = parts
    if scheme.lower() != "bearer":
        return None
    token = token.strip()
    return token or None


def _parse_content_length(raw: str) -> int:
    """解析 Content-Length；只接受纯 ASCII 数字。

    不使用宽松的 ``int()``：它会接受 ``+5``、``5_0`` 等写法，可能让服务端
    与代理对长度产生不同理解（``5_0`` 会被当成 50）。
    """
    text = str(raw).strip()
    if not text or not text.isascii() or not text.isdigit():
        raise bad_request("invalid_body", "Content-Length 不合法")
    return int(text)


class ApiHandler(BaseHTTPRequestHandler):
    """API 请求处理器：每个请求独立分发，异常统一转成 JSON 错误。"""

    protocol_version = "HTTP/1.1"
    server_version = "WarriorStore/1.0"
    sys_version = ""
    # 防止慢连接长期占用线程（StreamRequestHandler.setup 会应用到 socket）。
    timeout = 30

    # ------------------------------------------------------------------
    # HTTP 方法入口：全部走同一分发；已知路径返回 405，未知路径 404。
    # ------------------------------------------------------------------

    def do_GET(self) -> None:  # noqa: N802 - BaseHTTPRequestHandler 约定
        self._handle_request("GET")

    def do_POST(self) -> None:  # noqa: N802
        self._handle_request("POST")

    def do_PATCH(self) -> None:  # noqa: N802
        self._handle_request("PATCH")

    def do_DELETE(self) -> None:  # noqa: N802
        self._handle_request("DELETE")

    def do_PUT(self) -> None:  # noqa: N802
        self._handle_request("PUT")

    def do_OPTIONS(self) -> None:  # noqa: N802
        self._handle_request("OPTIONS")

    def do_HEAD(self) -> None:  # noqa: N802
        self._handle_request("HEAD")

    def do_TRACE(self) -> None:  # noqa: N802
        self._handle_request("TRACE")

    def do_CONNECT(self) -> None:  # noqa: N802
        self._handle_request("CONNECT")

    def __getattr__(self, name: str):
        """未知 ``do_*`` 方法也走统一分发，避免基类返回 HTML 501。

        只在属性缺失时调用；已知 HTTP 方法仍使用上面的显式方法。
        """
        if name.startswith("do_") and len(name) > 3:
            method = name[3:]
            return lambda: self._handle_request(method)
        raise AttributeError(name)

    def version_string(self) -> str:
        """固定 Server 头，不泄露 Python 版本。"""
        return "WarriorStore/1.0"

    def log_message(self, format: str, *args) -> None:  # noqa: A002
        """屏蔽 http.server 默认的 stderr 日志；访问日志走 log_access。"""
        return

    # ------------------------------------------------------------------
    # 请求生命周期
    # ------------------------------------------------------------------

    def _handle_request(self, method: str) -> None:
        """执行一次请求：分发、异常转换、访问日志（finally 必定执行）。"""
        started = time.monotonic()
        status = 500
        self._auth_player_id: str | None = None
        self._body_consumed = False
        self._status_code = 500
        try:
            try:
                self._dispatch(method)
                status = self._status_code
            except ApiError as err:
                status = err.status
                self._send_api_error(err)
            except (BrokenPipeError, ConnectionResetError):
                # 客户端提前断开：静默，不再写响应。
                status = 499
            except Exception:
                self.server.logger.exception("未处理异常")
                status = 500
                self._send_api_error(internal_error())
        except (BrokenPipeError, ConnectionResetError):
            status = 499
        finally:
            cfg = self.server.config
            if cfg.access_log:
                log_access(
                    method=method,
                    path=self.path,
                    status=status,
                    duration_ms=(time.monotonic() - started) * 1000.0,
                    ip=self._client_ip() if cfg.log_ip else None,
                    player_id=self._auth_player_id,
                )

    def _dispatch(self, method: str) -> None:
        """按路径与方法分发到具体处理函数。"""
        try:
            split = urlsplit(self.path)
        except ValueError:
            # 畸形 absolute-form（如 ``http://[``）会让 urlsplit 抛错，按未知资源处理。
            raise not_found("资源不存在") from None
        route, raw_player_id = _resolve_path(split.path)

        allowed = _ALLOWED_METHODS[route]
        if method not in allowed:
            # 请求体尚未读取，残留字节会污染 keep-alive 连接，直接关闭。
            self.close_connection = True
            raise method_not_allowed(", ".join(allowed))

        if route == "healthz":
            self._discard_body()
            self._handle_health()
            return

        if route == "players":
            if method == "POST":
                self._handle_create_player()
            else:
                self._discard_body()
                self._handle_list_players(split.query)
            return

        player_id = validate_player_id(raw_player_id)
        if route == "player":
            if method == "GET":
                self._discard_body()
                self._handle_get_player(player_id)
            elif method == "PATCH":
                self._handle_patch_player(player_id)
            else:
                self._discard_body()
                self._handle_delete_player(player_id)
            return

        # route == "results"
        self._handle_record_result(player_id)

    # ------------------------------------------------------------------
    # 请求体
    # ------------------------------------------------------------------

    def _content_length(self) -> int | None:
        """读取唯一的 Content-Length；未提供返回 None，重复一律 400。

        重复的 Content-Length 会造成连接错位/请求走私，必须直接拒绝并关闭连接。
        """
        values = self.headers.get_all("Content-Length")
        if not values:
            return None
        if len(values) > 1:
            self.close_connection = True
            raise bad_request("invalid_body", "Content-Length 重复")
        return _parse_content_length(values[0])

    def _has_transfer_encoding(self) -> bool:
        """是否存在任何 Transfer-Encoding（大小写/多值都按存在处理）。"""
        values = self.headers.get_all("Transfer-Encoding") or []
        return any(str(value).strip() for value in values)

    def _read_body(self) -> bytes:
        """读取 POST/PATCH 的请求体（按 Content-Length，最多 8 KiB）。"""
        if self._has_transfer_encoding():
            self.close_connection = True
            raise bad_request("invalid_body", "不支持 Transfer-Encoding: chunked")

        length = self._content_length()
        if length is None:
            self.close_connection = True
            raise bad_request("length_required", "请求体缺少 Content-Length")

        if length > MAX_BODY_BYTES:
            self.close_connection = True
            raise payload_too_large(MAX_BODY_BYTES)

        body = self.rfile.read(length) if length else b""
        self._body_consumed = True
        if len(body) != length:
            # 客户端半关闭/提前 EOF：不能把截断的 JSON 当完整请求落库。
            self.close_connection = True
            raise bad_request("invalid_body", "请求体长度与 Content-Length 不一致")
        return body

    def _read_json_object(self) -> dict:
        """读取并解析 JSON 对象请求体；任何非对象内容都是 400 ``invalid_json``。"""
        body = self._read_body()
        try:
            payload = json.loads(body.decode("utf-8"))
        except (ValueError, RecursionError):
            # JSONDecodeError/UnicodeDecodeError 是 ValueError 子类；深嵌套会
            # 抛 RecursionError，超大整数会抛 ValueError，都不应变成 500。
            raise bad_request("invalid_json", _INVALID_JSON_MESSAGE) from None
        if not isinstance(payload, dict):
            raise bad_request("invalid_json", _INVALID_JSON_MESSAGE)
        return payload

    def _discard_body(self) -> None:
        """GET/DELETE 不解析请求体，但消费掉字节以保持连接可复用。"""
        if self._has_transfer_encoding():
            self.close_connection = True
            raise bad_request("invalid_body", "不支持 Transfer-Encoding: chunked")

        length = self._content_length()
        if length is None:
            self._body_consumed = True
            return

        if length > MAX_BODY_BYTES:
            self.close_connection = True
            raise payload_too_large(MAX_BODY_BYTES)

        remaining = length
        while remaining > 0:
            chunk = self.rfile.read(min(remaining, 65536))
            if not chunk:
                break
            remaining -= len(chunk)
        self._body_consumed = True
        if remaining != 0:
            self.close_connection = True
            raise bad_request("invalid_body", "请求体长度与 Content-Length 不一致")

    # ------------------------------------------------------------------
    # 响应输出
    # ------------------------------------------------------------------

    def _send_json(
        self,
        status: int,
        payload: dict,
        headers: dict[str, str] | None = None,
    ) -> None:
        """发送 JSON 响应；HEAD 只发头（带 Content-Length）不发体。"""
        body = json.dumps(payload, ensure_ascii=False, separators=(",", ":")).encode("utf-8")
        self._status_code = status
        self.send_response(status)
        self.send_header("Content-Type", _JSON_CONTENT_TYPE)
        self.send_header("Content-Length", str(len(body)))
        self.send_header("Cache-Control", "no-store")
        self.send_header("X-Content-Type-Options", "nosniff")
        extra_headers = headers or {}
        if self.close_connection and "Connection" not in extra_headers:
            self.send_header("Connection", "close")
        for name, value in extra_headers.items():
            self.send_header(name, value)
        self.end_headers()
        if self.command != "HEAD":
            self.wfile.write(body)

    def _drain_for_error(self) -> None:
        """出错时尽量排空剩余请求体，避免 close 触发 RST 丢掉响应。

        只处理长度已知且不超过 ``MAX_DRAIN_BYTES`` 的请求；超大 body 直接
        关闭连接（响应可能被 RST 丢弃，但不再读取不可信的大量数据）。
        """
        try:
            values = self.headers.get_all("Content-Length")
            if not values or len(values) != 1:
                return
            raw = values[0].strip()
            if not raw.isascii() or not raw.isdigit():
                return
            length = int(raw)
            if length <= 0 or length > MAX_DRAIN_BYTES:
                return
            # 排空只用于让客户端收到错误响应；给慢客户端最多 2 秒，
            # 避免一个不发送 body 的连接把处理线程拖到 30 秒超时。
            old_timeout = self.connection.gettimeout()
            try:
                self.connection.settimeout(2.0)
                remaining = length
                while remaining > 0:
                    chunk = self.rfile.read(min(remaining, 65536))
                    if not chunk:
                        break
                    remaining -= len(chunk)
            finally:
                try:
                    self.connection.settimeout(old_timeout)
                except OSError:
                    pass
            self._body_consumed = True
        except Exception:
            # 排空只是优化，失败不影响随后发送错误响应。
            pass

    def _send_api_error(self, err: ApiError) -> None:
        """把 ApiError 转成标准错误响应（必要时先排空请求体）。"""
        if not self._body_consumed:
            self._drain_for_error()
        if not self._body_consumed:
            # 没能排空：必须关闭连接，避免残留字节被当成下一个请求。
            self.close_connection = True
        self._send_json(err.status, err.body(), err.headers)

    def _send_empty(self, status: int) -> None:
        """发送无响应体的响应（用于 204）。"""
        self._status_code = status
        self.send_response(status)
        self.send_header("Content-Length", "0")
        self.send_header("Cache-Control", "no-store")
        self.send_header("X-Content-Type-Options", "nosniff")
        self.end_headers()

    # ------------------------------------------------------------------
    # 客户端信息与鉴权
    # ------------------------------------------------------------------

    def _client_ip(self) -> str:
        """客户端 IP；仅在配置信任反向代理时采用 X-Forwarded-For 最后一段。

        反向代理（如 nginx ``$proxy_add_x_forwarded_for``）把真实客户端地址
        追加在末尾，最左段由客户端控制、不可信；只认最后一跳并做 IP 校验。
        """
        ip = self.client_address[0] if self.client_address else ""
        cfg = self.server.config
        if cfg.trust_proxy:
            values = self.headers.get_all("X-Forwarded-For") or []
            if values:
                # 多个 XFF 头时，最后一跳（最靠近服务端）才是可信代理追加的；
                # 再取该值的最后一段，兼容代理把真实 IP 追加在末尾的写法。
                candidate = values[-1].rsplit(",", 1)[-1].strip()
                try:
                    ip = str(ipaddress.ip_address(candidate))
                except ValueError:
                    pass
        return ip

    def _require_auth(self, player_id: str) -> None:
        """校验 Bearer token。

        玩家不存在与 token 不匹配统一返回 401，避免探测。
        """
        auth_values = self.headers.get_all("Authorization") or []
        if len(auth_values) != 1:
            # 多个 Authorization 头时不同代理/后端可能取不同值，直接拒绝。
            raise unauthorized()
        token = _parse_bearer(auth_values[0])
        if token is None:
            raise unauthorized()
        stored_hash = self.server.store.get_token_hash(player_id)
        if stored_hash is None or not token_matches(token, stored_hash, self.server.config.pepper):
            raise unauthorized()
        self._auth_player_id = player_id

    # ------------------------------------------------------------------
    # 各接口实现
    # ------------------------------------------------------------------

    def _handle_health(self) -> None:
        """GET /healthz：数据库可用返回 200，否则 503。"""
        cfg = self.server.config
        uptime_s = max(0, int(time.monotonic() - self.server.started_at))
        if self.server.store.ping():
            self._send_json(
                200,
                {
                    "status": "ok",
                    "version": cfg.version,
                    "db": "ok",
                    "uptime_s": uptime_s,
                },
            )
        else:
            self._send_json(
                503,
                {"error": {"code": "db_unavailable", "message": "数据库不可用"}},
            )

    def _handle_create_player(self) -> None:
        """POST /api/v1/players：注册新玩家并返回一次性 token。"""
        cfg = self.server.config
        if not self.server.register_limiter.allow(self._client_ip()):
            self.close_connection = True
            raise rate_limited()

        payload = self._read_json_object()
        nickname = validate_nickname(payload.get("nickname"))

        token = new_token()
        token_hash = hash_token(token, cfg.pepper)
        for _attempt in range(CREATE_ATTEMPTS):
            player_id = new_player_id()
            try:
                player = self.server.store.create_player(player_id, nickname, token_hash)
            except sqlite3.IntegrityError:
                # 极小概率的 ID 冲突：重新生成。
                continue
            self._send_json(
                201,
                {
                    "player_id": player["player_id"],
                    "short_id": player["player_id"][:6],
                    "nickname": player["nickname"],
                    "token": token,
                    "created_at": player["created_at"],
                },
            )
            return
        raise internal_error()

    def _handle_list_players(self, query: str) -> None:
        """GET /api/v1/players?ids=...：批量查询，保序并省略未知 ID。"""
        params = parse_qs(query, keep_blank_values=True)
        raw_ids = params.get("ids")
        if not raw_ids:
            raise bad_request("missing_ids", "批量查询必须提供 ids 参数")

        player_ids = [
            part.strip()
            for part in ",".join(raw_ids).split(",")
            if part.strip()
        ]
        if not player_ids:
            raise bad_request("missing_ids", "批量查询必须提供 ids 参数")
        if len(player_ids) > MAX_BATCH_IDS:
            raise bad_request("too_many_ids", f"批量查询最多 {MAX_BATCH_IDS} 个 ID")
        for player_id in player_ids:
            validate_player_id(player_id)

        self._send_json(200, {"players": self.server.store.get_players(player_ids)})

    def _handle_get_player(self, player_id: str) -> None:
        """GET /api/v1/players/{id}：公开资料（永远不含 token）。"""
        player = self.server.store.get_player(player_id)
        if player is None:
            raise not_found("玩家不存在")
        self._send_json(200, player)

    def _handle_patch_player(self, player_id: str) -> None:
        """PATCH /api/v1/players/{id}：改昵称（需要本人 token）。"""
        self._require_auth(player_id)
        payload = self._read_json_object()
        nickname = validate_nickname(payload.get("nickname"))
        player = self.server.store.update_nickname(player_id, nickname)
        if player is None:
            raise not_found("玩家不存在")
        self._send_json(200, player)

    def _handle_record_result(self, player_id: str) -> None:
        """POST /api/v1/players/{id}/results：上报一场 PVE/PVP 结果。"""
        self._require_auth(player_id)
        if not self.server.result_limiter.allow(player_id):
            self.close_connection = True
            raise rate_limited()

        payload = self._read_json_object()
        mode = validate_mode(payload.get("mode"))
        result = validate_result(payload.get("result"))
        event_id = validate_event_id(payload.get("event_id"))

        stats = self.server.store.record_result(player_id, mode, result, event_id)
        if stats is None:
            raise not_found("玩家不存在")
        self._send_json(200, stats)

    def _handle_delete_player(self, player_id: str) -> None:
        """DELETE /api/v1/players/{id}：删除本人资料（需要本人 token）。"""
        self._require_auth(player_id)
        if not self.server.store.delete_player(player_id):
            raise not_found("玩家不存在")
        self._send_empty(204)
