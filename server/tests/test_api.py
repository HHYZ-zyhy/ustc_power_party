"""HTTP 层端到端测试：真实起服务 + 独立临时数据库，覆盖 API.md 的接口与错误码。"""

from __future__ import annotations

import http.client
import json
import socket
import sqlite3
import tempfile
import threading
import time
import unittest

try:  # 兼容 discover（tests/ 为顶层目录）与 python -m unittest tests.test_api
    from . import helpers
except ImportError:  # pragma: no cover - discover 模式
    import helpers  # type: ignore[no-redef]

# 格式合法但不存在的玩家 ID。
MISSING_ID = "p_0000000000000000"


class ApiTestCase(unittest.TestCase):
    """每个用例独立临时数据库与独立服务。"""

    config_overrides: dict = {}

    def setUp(self) -> None:
        self._tmp = tempfile.TemporaryDirectory(prefix="warrior-store-test-")
        self.addCleanup(self._tmp.cleanup)
        self.config = helpers.make_config(self._tmp.name, **self.config_overrides)
        server_cm = helpers.running_server(self.config)
        self.server, self.base_url = server_cm.__enter__()
        self.addCleanup(server_cm.__exit__, None, None, None)

    # ------------------------------------------------------------------
    # 测试辅助
    # ------------------------------------------------------------------

    def request(
        self,
        method: str,
        path: str,
        body: object = None,
        token: str | None = None,
        headers: dict[str, str] | None = None,
    ) -> tuple[int, dict[str, str], object]:
        """向当前测试服务发请求。"""
        return helpers.http_request(
            method,
            self.base_url + path,
            body=body,
            token=token,
            headers=headers,
        )

    def register(self, nickname: str = "测试玩家") -> dict:
        """注册一个玩家并返回响应体。"""
        status, _headers, body = self.request(
            "POST", "/api/v1/players", body={"nickname": nickname}
        )
        self.assertEqual(status, 201, body)
        self.assertIsInstance(body, dict)
        return body  # type: ignore[return-value]

    def assert_error(
        self,
        result: tuple[int, dict[str, str], object],
        status: int,
        code: str,
    ) -> dict:
        """断言错误响应的状态码与错误码。"""
        actual_status, _headers, body = result
        self.assertEqual(actual_status, status, body)
        self.assertIsInstance(body, dict, body)
        assert isinstance(body, dict)
        error = body.get("error")
        self.assertIsInstance(error, dict, body)
        assert isinstance(error, dict)
        self.assertEqual(error.get("code"), code, body)
        self.assertIsInstance(error.get("message"), str, body)
        return body

    def report(
        self,
        player_id: str,
        token: str,
        mode: str = "pve",
        result: str = "win",
        event_id: str | None = None,
    ) -> tuple[int, dict[str, str], object]:
        """上报一场战绩。"""
        payload: dict = {"mode": mode, "result": result}
        if event_id is not None:
            payload["event_id"] = event_id
        return self.request(
            "POST", f"/api/v1/players/{player_id}/results", body=payload, token=token
        )


# ----------------------------------------------------------------------
# 健康检查
# ----------------------------------------------------------------------


class HealthTest(ApiTestCase):
    def test_healthz_ok(self) -> None:
        status, headers, body = self.request("GET", "/healthz")
        self.assertEqual(status, 200)
        self.assertIsInstance(body, dict)
        assert isinstance(body, dict)
        self.assertEqual(body.get("status"), "ok")
        self.assertEqual(body.get("version"), self.config.version)
        self.assertEqual(body.get("db"), "ok")
        self.assertIsInstance(body.get("uptime_s"), int)
        self.assertGreaterEqual(body["uptime_s"], 0)
        self.assertEqual(headers.get("content-type"), "application/json; charset=utf-8")

    def test_healthz_db_unavailable(self) -> None:
        self.server.store.ping = lambda: False  # type: ignore[method-assign]
        self.assert_error(self.request("GET", "/healthz"), 503, "db_unavailable")

    def test_healthz_503_when_table_missing(self) -> None:
        conn = sqlite3.connect(self.config.db_path)
        try:
            conn.execute("DROP TABLE stats")
            conn.commit()
        finally:
            conn.close()
        self.assert_error(self.request("GET", "/healthz"), 503, "db_unavailable")


# ----------------------------------------------------------------------
# 注册
# ----------------------------------------------------------------------


class RegisterTest(ApiTestCase):
    def test_register_returns_expected_fields(self) -> None:
        player = self.register("科大路人甲")
        self.assertEqual(
            set(player),
            {"player_id", "short_id", "nickname", "token", "created_at"},
        )
        self.assertRegex(player["player_id"], r"^p_[0-9a-f]{16}$")
        self.assertEqual(player["short_id"], player["player_id"][:6])
        self.assertEqual(player["nickname"], "科大路人甲")
        self.assertIsInstance(player["token"], str)
        self.assertGreaterEqual(len(player["token"]), 40)
        self.assertTrue(player["created_at"].endswith("Z"))

    def test_register_strips_nickname(self) -> None:
        player = self.register("  科大路人甲  ")
        self.assertEqual(player["nickname"], "科大路人甲")

    def test_register_rejects_invalid_nickname(self) -> None:
        cases = {
            "空字符串": "",
            "全空白": "   ",
            "超长": "字" * 25,
            "控制字符": "\x00abc",
            "行分隔符": "abc\u2028def",
            "数字": 123,
            "null": None,
        }
        for label, nickname in cases.items():
            with self.subTest(label=label):
                self.assert_error(
                    self.request("POST", "/api/v1/players", body={"nickname": nickname}),
                    400,
                    "invalid_nickname",
                )
        with self.subTest(label="缺少字段"):
            self.assert_error(
                self.request("POST", "/api/v1/players", body={}),
                400,
                "invalid_nickname",
            )
        with self.subTest(label="孤立代理项"):
            # ensure_ascii 产生 \ud800 转义；Python json.loads 会还原成孤立代理项。
            raw = json.dumps({"nickname": "\ud800"}).encode("ascii")
            self.assert_error(
                self.request("POST", "/api/v1/players", body=raw),
                400,
                "invalid_nickname",
            )

    def test_register_allows_chinese_and_duplicate_names(self) -> None:
        first = self.register("同名玩家")
        second = self.register("同名玩家")
        self.assertEqual(first["nickname"], second["nickname"])
        self.assertNotEqual(first["player_id"], second["player_id"])
        self.assertNotEqual(first["token"], second["token"])


# ----------------------------------------------------------------------
# 单查
# ----------------------------------------------------------------------


class GetPlayerTest(ApiTestCase):
    def test_get_player_public_profile(self) -> None:
        player = self.register("公开资料")
        status, _headers, body = self.request(
            "GET", f"/api/v1/players/{player['player_id']}"
        )
        self.assertEqual(status, 200)
        self.assertIsInstance(body, dict)
        assert isinstance(body, dict)
        self.assertEqual(
            set(body),
            {"player_id", "short_id", "nickname", "created_at", "pve", "pvp"},
        )
        self.assertNotIn("token", body)
        self.assertNotIn("token_hash", body)
        self.assertEqual(body["player_id"], player["player_id"])
        self.assertEqual(body["short_id"], player["player_id"][:6])
        self.assertEqual(body["pve"], {"games": 0, "wins": 0, "win_rate": None})
        self.assertEqual(body["pvp"], {"games": 0, "wins": 0, "win_rate": None})

    def test_get_unknown_player_returns_404(self) -> None:
        self.assert_error(
            self.request("GET", f"/api/v1/players/{MISSING_ID}"), 404, "not_found"
        )

    def test_get_invalid_player_id_returns_400(self) -> None:
        for raw in ("not-a-player-id", "p_XYZ", "p_1234"):
            with self.subTest(raw=raw):
                self.assert_error(
                    self.request("GET", f"/api/v1/players/{raw}"),
                    400,
                    "invalid_player_id",
                )

    def test_empty_player_id_returns_400(self) -> None:
        self.assert_error(
            self.request("GET", "/api/v1/players/"), 400, "invalid_player_id"
        )


# ----------------------------------------------------------------------
# 批量查询
# ----------------------------------------------------------------------


class BatchQueryTest(ApiTestCase):
    def test_batch_lookup_keeps_order_and_omits_unknown(self) -> None:
        first = self.register("批量一")
        second = self.register("批量二")
        ids = f"{second['player_id']},{MISSING_ID},{first['player_id']}"
        status, _headers, body = self.request("GET", f"/api/v1/players?ids={ids}")
        self.assertEqual(status, 200)
        assert isinstance(body, dict)
        players = body["players"]
        self.assertIsInstance(players, list)
        self.assertEqual(
            [player["player_id"] for player in players],
            [second["player_id"], first["player_id"]],
        )

    def test_batch_lookup_without_ids_returns_400(self) -> None:
        self.assert_error(self.request("GET", "/api/v1/players"), 400, "missing_ids")
        self.assert_error(
            self.request("GET", "/api/v1/players?ids="), 400, "missing_ids"
        )
        self.assert_error(
            self.request("GET", "/api/v1/players?ids=,,"), 400, "missing_ids"
        )

    def test_batch_lookup_too_many_ids(self) -> None:
        ids = ",".join(f"p_{index:016x}" for index in range(51))
        self.assert_error(
            self.request("GET", f"/api/v1/players?ids={ids}"), 400, "too_many_ids"
        )

    def test_batch_lookup_invalid_id(self) -> None:
        player = self.register("批量校验")
        ids = f"{player['player_id']},bad-id"
        self.assert_error(
            self.request("GET", f"/api/v1/players?ids={ids}"),
            400,
            "invalid_player_id",
        )


# ----------------------------------------------------------------------
# 改名
# ----------------------------------------------------------------------


class RenameTest(ApiTestCase):
    def test_rename_requires_valid_token(self) -> None:
        player = self.register("原昵称")
        path = f"/api/v1/players/{player['player_id']}"
        body = {"nickname": "新昵称"}

        self.assert_error(self.request("PATCH", path, body=body), 401, "unauthorized")
        self.assert_error(
            self.request("PATCH", path, body=body, token="wrong-token"),
            401,
            "unauthorized",
        )

        other = self.register("别人")
        self.assert_error(
            self.request("PATCH", path, body=body, token=other["token"]),
            401,
            "unauthorized",
        )

    def test_rename_updates_nickname(self) -> None:
        player = self.register("原昵称")
        path = f"/api/v1/players/{player['player_id']}"
        status, _headers, body = self.request(
            "PATCH", path, body={"nickname": "  新昵称  "}, token=player["token"]
        )
        self.assertEqual(status, 200)
        assert isinstance(body, dict)
        self.assertEqual(body["nickname"], "新昵称")
        self.assertNotIn("token", body)

        status, _headers, body = self.request("GET", path)
        self.assertEqual(status, 200)
        assert isinstance(body, dict)
        self.assertEqual(body["nickname"], "新昵称")

    def test_rename_rejects_invalid_nickname(self) -> None:
        player = self.register("原昵称")
        path = f"/api/v1/players/{player['player_id']}"
        self.assert_error(
            self.request("PATCH", path, body={"nickname": ""}, token=player["token"]),
            400,
            "invalid_nickname",
        )


# ----------------------------------------------------------------------
# 上报战绩
# ----------------------------------------------------------------------


class ResultsTest(ApiTestCase):
    def test_record_pve_and_pvp(self) -> None:
        player = self.register("战绩玩家")
        player_id, token = player["player_id"], player["token"]

        status, _headers, body = self.report(player_id, token, "pve", "win", "evt-win-01")
        self.assertEqual(status, 200)
        assert isinstance(body, dict)
        self.assertIs(body["duplicate"], False)
        self.assertEqual(body["pve"], {"games": 1, "wins": 1, "win_rate": 1.0})
        self.assertEqual(body["pvp"], {"games": 0, "wins": 0, "win_rate": None})

        status, _headers, body = self.report(player_id, token, "pve", "loss", "evt-loss-1")
        self.assertEqual(status, 200)
        assert isinstance(body, dict)
        self.assertEqual(body["pve"], {"games": 2, "wins": 1, "win_rate": 0.5})

        status, _headers, body = self.report(player_id, token, "pvp", "win", "evt-pvp-01")
        self.assertEqual(status, 200)
        assert isinstance(body, dict)
        self.assertEqual(body["pve"], {"games": 2, "wins": 1, "win_rate": 0.5})
        self.assertEqual(body["pvp"], {"games": 1, "wins": 1, "win_rate": 1.0})

        status, _headers, body = self.request("GET", f"/api/v1/players/{player_id}")
        self.assertEqual(status, 200)
        assert isinstance(body, dict)
        self.assertEqual(body["pve"], {"games": 2, "wins": 1, "win_rate": 0.5})
        self.assertEqual(body["pvp"], {"games": 1, "wins": 1, "win_rate": 1.0})

    def test_record_requires_token(self) -> None:
        player = self.register("鉴权玩家")
        path = f"/api/v1/players/{player['player_id']}/results"
        body = {"mode": "pve", "result": "win", "event_id": "evt-authtest"}

        self.assert_error(self.request("POST", path, body=body), 401, "unauthorized")
        self.assert_error(
            self.request("POST", path, body=body, token="wrong-token"),
            401,
            "unauthorized",
        )

    def test_record_invalid_fields(self) -> None:
        player = self.register("校验玩家")
        player_id, token = player["player_id"], player["token"]
        cases = [
            ({"mode": "PVE", "result": "win"}, "invalid_mode"),
            ({"result": "win"}, "invalid_mode"),
            ({"mode": "pve", "result": "draw"}, "invalid_result"),
            ({"mode": "pve"}, "invalid_result"),
            ({"mode": "pve", "result": "win", "event_id": "short"}, "invalid_event_id"),
            ({"mode": "pve", "result": "win", "event_id": "bad event id"}, "invalid_event_id"),
        ]
        for payload, code in cases:
            with self.subTest(payload=payload):
                self.assert_error(
                    self.request(
                        "POST",
                        f"/api/v1/players/{player_id}/results",
                        body=payload,
                        token=token,
                    ),
                    400,
                    code,
                )

        self.assert_error(
            self.request(
                "POST",
                f"/api/v1/players/{player_id}/results",
                body={"mode": "pve", "result": "win", "event_id": 12345},
                token=token,
            ),
            400,
            "invalid_event_id",
        )

        # 非法请求不应写入任何计数。
        status, _headers, body = self.request("GET", f"/api/v1/players/{player_id}")
        self.assertEqual(status, 200)
        assert isinstance(body, dict)
        self.assertEqual(body["pve"]["games"], 0)

    def test_event_id_is_idempotent(self) -> None:
        player = self.register("幂等玩家")
        player_id, token = player["player_id"], player["token"]

        status, _headers, body = self.report(player_id, token, "pve", "win", "evt-same-01")
        self.assertEqual(status, 200)
        assert isinstance(body, dict)
        self.assertIs(body["duplicate"], False)
        self.assertEqual(body["pve"]["games"], 1)

        status, _headers, body = self.report(player_id, token, "pve", "win", "evt-same-01")
        self.assertEqual(status, 200)
        assert isinstance(body, dict)
        self.assertIs(body["duplicate"], True)
        self.assertEqual(body["pve"], {"games": 1, "wins": 1, "win_rate": 1.0})

        status, _headers, body = self.report(player_id, token, "pve", "loss", "evt-other-1")
        self.assertEqual(status, 200)
        assert isinstance(body, dict)
        self.assertIs(body["duplicate"], False)
        self.assertEqual(body["pve"]["games"], 2)

        # 不带 event_id 时每次都计数。
        status, _headers, body = self.report(player_id, token, "pve", "win")
        self.assertEqual(status, 200)
        assert isinstance(body, dict)
        self.assertIs(body["duplicate"], False)
        self.assertEqual(body["pve"]["games"], 3)


# ----------------------------------------------------------------------
# 删除
# ----------------------------------------------------------------------


class DeleteTest(ApiTestCase):
    def test_delete_requires_token(self) -> None:
        player = self.register("待删玩家")
        path = f"/api/v1/players/{player['player_id']}"
        self.assert_error(self.request("DELETE", path), 401, "unauthorized")
        self.assert_error(
            self.request("DELETE", path, token="wrong-token"), 401, "unauthorized"
        )
        # 未删除，仍可查询。
        status, _headers, _body = self.request("GET", path)
        self.assertEqual(status, 200)

    def test_delete_removes_profile_and_invalidates_token(self) -> None:
        player = self.register("删除玩家")
        player_id, token = player["player_id"], player["token"]
        self.report(player_id, token, "pve", "win", "evt-delete-1")

        status, headers, body = self.request(
            "DELETE", f"/api/v1/players/{player_id}", token=token
        )
        self.assertEqual(status, 204)
        self.assertIsNone(body)
        self.assertEqual(headers.get("content-length"), "0")
        self.assertEqual(headers.get("cache-control"), "no-store")
        self.assertEqual(headers.get("x-content-type-options"), "nosniff")

        self.assert_error(
            self.request("GET", f"/api/v1/players/{player_id}"), 404, "not_found"
        )
        self.assert_error(
            self.report(player_id, token, "pve", "win", "evt-delete-2"),
            401,
            "unauthorized",
        )
        self.assert_error(
            self.request(
                "PATCH",
                f"/api/v1/players/{player_id}",
                body={"nickname": "复活"},
                token=token,
            ),
            401,
            "unauthorized",
        )
        self.assert_error(
            self.request("DELETE", f"/api/v1/players/{player_id}", token=token),
            401,
            "unauthorized",
        )


# ----------------------------------------------------------------------
# 协议细节：404/405/请求体/响应头
# ----------------------------------------------------------------------


class ProtocolTest(ApiTestCase):
    def test_unknown_path_returns_404(self) -> None:
        for path in ("/api/v1/nope", "/healthz/", "/api/v1/players/x/y"):
            with self.subTest(path=path):
                self.assert_error(self.request("GET", path), 404, "not_found")

    def test_root_returns_404(self) -> None:
        self.assert_error(self.request("GET", "/"), 404, "not_found")

    def test_known_path_wrong_method_returns_405(self) -> None:
        status, headers, body = self.request("PUT", "/api/v1/players")
        self.assertEqual(status, 405)
        self.assertIn("POST", headers.get("allow", ""))
        self.assertIn("GET", headers.get("allow", ""))
        assert isinstance(body, dict)
        self.assertEqual(body["error"]["code"], "method_not_allowed")

        status, headers, _body = self.request("POST", "/healthz")
        self.assertEqual(status, 405)
        self.assertEqual(headers.get("allow"), "GET")

        status, headers, _body = self.request(
            "GET", f"/api/v1/players/{MISSING_ID}/results"
        )
        self.assertEqual(status, 405)
        self.assertEqual(headers.get("allow"), "POST")

        status, headers, _body = self.request(
            "PUT", f"/api/v1/players/{MISSING_ID}"
        )
        self.assertEqual(status, 405)
        self.assertEqual(headers.get("allow"), "GET, PATCH, DELETE")

    def test_head_returns_no_body(self) -> None:
        status, headers, body = self.request("HEAD", "/healthz")
        self.assertEqual(status, 405)
        self.assertIsNone(body)
        self.assertGreater(int(headers.get("content-length", "0")), 0)

    def test_payload_too_large(self) -> None:
        payload = {"nickname": "字" * 9000}
        self.assert_error(
            self.request("POST", "/api/v1/players", body=payload),
            413,
            "payload_too_large",
        )

    def test_invalid_json(self) -> None:
        for raw in (b"{", b"[]", b'"text"', b"", b"\xff\xfe"):
            with self.subTest(raw=raw):
                self.assert_error(
                    self.request("POST", "/api/v1/players", body=raw),
                    400,
                    "invalid_json",
                )

    def _raw_exchange(
        self, request: bytes, shutdown_write: bool = False
    ) -> tuple[int, object]:
        """用原始 socket 发请求，返回 (状态码, JSON 响应体或原始字节)。"""
        port = int(self.server.server_address[1])
        with socket.create_connection(("127.0.0.1", port), timeout=10) as sock:
            sock.sendall(request)
            if shutdown_write:
                sock.shutdown(socket.SHUT_WR)
            chunks = []
            while True:
                data = sock.recv(4096)
                if not data:
                    break
                chunks.append(data)
        head, _sep, raw_body = b"".join(chunks).partition(b"\r\n\r\n")
        status = int(head.split(b" ", 2)[1])
        if not raw_body:
            return status, None
        try:
            return status, json.loads(raw_body.decode("utf-8"))
        except (UnicodeDecodeError, json.JSONDecodeError):
            return status, raw_body

    def test_missing_content_length_returns_400(self) -> None:
        raw_request = (
            b"POST /api/v1/players HTTP/1.1\r\n"
            b"Host: 127.0.0.1\r\n"
            b"Content-Type: application/json\r\n"
            b"Connection: close\r\n"
            b"\r\n"
            b'{"nickname":"raw"}'
        )
        status, body = self._raw_exchange(raw_request)
        self.assertEqual(status, 400)
        assert isinstance(body, dict)
        self.assertEqual(body["error"]["code"], "length_required")

    def test_duplicate_content_length_rejected(self) -> None:
        raw_request = (
            b"POST /api/v1/players HTTP/1.1\r\n"
            b"Host: 127.0.0.1\r\n"
            b"Content-Type: application/json\r\n"
            b"Content-Length: 5\r\n"
            b"Content-Length: 999\r\n"
            b"Connection: close\r\n"
            b"\r\n"
        )
        status, body = self._raw_exchange(raw_request)
        self.assertEqual(status, 400)
        assert isinstance(body, dict)
        self.assertEqual(body["error"]["code"], "invalid_body")

    def test_malformed_absolute_form_uri_returns_404(self) -> None:
        status, _body = self._raw_exchange(
            b"GET http://[ HTTP/1.1\r\n"
            b"Host: x\r\n"
            b"Connection: close\r\n"
            b"\r\n"
        )
        self.assertEqual(status, 404)

    def test_short_body_is_rejected_without_writing(self) -> None:
        player = self.register("短读玩家")
        payload = json.dumps({"mode": "pve", "result": "win"}).encode("utf-8")
        declared = len(payload) + 100
        raw = (
            b"POST /api/v1/players/"
            + player["player_id"].encode()
            + b"/results HTTP/1.1\r\n"
            b"Host: 127.0.0.1\r\n"
            b"Content-Type: application/json\r\n"
            b"Authorization: Bearer "
            + player["token"].encode()
            + b"\r\nContent-Length: "
            + str(declared).encode()
            + b"\r\nConnection: close\r\n\r\n"
            + payload
        )
        status, body = self._raw_exchange(raw, shutdown_write=True)
        self.assertEqual(status, 400, body)
        assert isinstance(body, dict)
        self.assertEqual(body["error"]["code"], "invalid_body")

        status, _headers, profile = self.request(
            "GET", f"/api/v1/players/{player['player_id']}"
        )
        self.assertEqual(status, 200)
        assert isinstance(profile, dict)
        self.assertEqual(profile["pve"]["games"], 0)

    def test_deep_json_returns_400(self) -> None:
        status, _headers, body = self.request(
            "POST", "/api/v1/players", body=b"[" * 3000
        )
        self.assertEqual(status, 400, body)
        assert isinstance(body, dict)
        self.assertEqual(body["error"]["code"], "invalid_json")

    def test_huge_integer_json_returns_400(self) -> None:
        raw = b'{"nickname":' + b"1" * 5000 + b"}"
        status, _headers, body = self.request("POST", "/api/v1/players", body=raw)
        self.assertEqual(status, 400, body)
        assert isinstance(body, dict)
        self.assertIn(body["error"]["code"], {"invalid_json", "invalid_nickname"})

    def test_strict_content_length_format(self) -> None:
        raw = (
            b"POST /api/v1/players HTTP/1.1\r\n"
            b"Host: x\r\n"
            b"Content-Length: 5_0\r\n"
            b"Connection: close\r\n"
            b"\r\n"
        )
        status, body = self._raw_exchange(raw)
        self.assertEqual(status, 400)
        assert isinstance(body, dict)
        self.assertEqual(body["error"]["code"], "invalid_body")

    def test_transfer_encoding_is_rejected(self) -> None:
        # 不发送 body：chunked 帧无法在不解析的情况下排空，带 body 时
        # Windows 可能因关闭未读数据而 RST。这里只验证“任何 TE 都被拒绝”。
        status, _headers, body = self.request(
            "POST",
            "/api/v1/players",
            headers={"Transfer-Encoding": "chunked"},
        )
        self.assertEqual(status, 400, body)
        assert isinstance(body, dict)
        self.assertEqual(body["error"]["code"], "invalid_body")

    def test_unknown_method_returns_json(self) -> None:
        status, headers, body = self.request("FOO", "/healthz")
        self.assertEqual(status, 405)
        self.assertEqual(headers.get("allow"), "GET")
        assert isinstance(body, dict)
        self.assertEqual(body["error"]["code"], "method_not_allowed")

        self.assert_error(self.request("FOO", "/nope"), 404, "not_found")

    def test_head_response_has_no_body(self) -> None:
        # http.client 对 HEAD 本来就不返回 body，这里用原始 socket 才能验证
        # 服务端确实没有发送 body。
        status, body = self._raw_exchange(
            b"HEAD /healthz HTTP/1.1\r\nHost: x\r\nConnection: close\r\n\r\n"
        )
        self.assertEqual(status, 405)
        self.assertIsNone(body)

    def test_duplicate_authorization_headers_rejected(self) -> None:
        player = self.register("双鉴权头")
        payload = b'{"mode":"pve","result":"win"}'
        raw = (
            b"POST /api/v1/players/"
            + player["player_id"].encode()
            + b"/results HTTP/1.1\r\n"
            b"Host: 127.0.0.1\r\n"
            b"Content-Type: application/json\r\n"
            b"Authorization: Bearer "
            + player["token"].encode()
            + b"\r\nAuthorization: Bearer "
            + player["token"].encode()
            + b"\r\nContent-Length: "
            + str(len(payload)).encode()
            + b"\r\nConnection: close\r\n\r\n"
            + payload
        )
        status, body = self._raw_exchange(raw)
        self.assertEqual(status, 401)
        assert isinstance(body, dict)
        self.assertEqual(body["error"]["code"], "unauthorized")

    def test_response_headers(self) -> None:
        status, headers, _body = self.request("GET", "/healthz")
        self.assertEqual(status, 200)
        self.assertEqual(headers.get("cache-control"), "no-store")
        self.assertEqual(headers.get("x-content-type-options"), "nosniff")
        self.assertEqual(headers.get("content-type"), "application/json; charset=utf-8")
        self.assertIn("content-length", headers)
        # Server 头不泄露 Python 版本。
        self.assertEqual(headers.get("server"), "WarriorStore/1.0")

        status, headers, _body = self.request("GET", f"/api/v1/players/{MISSING_ID}")
        self.assertEqual(status, 404)
        self.assertEqual(headers.get("cache-control"), "no-store")


# ----------------------------------------------------------------------
# 限流
# ----------------------------------------------------------------------


class RegisterRateLimitTest(ApiTestCase):
    config_overrides = {"register_per_hour": 2}

    def test_third_registration_is_rate_limited(self) -> None:
        self.register("限流一")
        self.register("限流二")
        status, headers, body = self.request(
            "POST", "/api/v1/players", body={"nickname": "限流三"}
        )
        self.assertEqual(status, 429)
        self.assertIsNotNone(headers.get("retry-after"))
        assert isinstance(body, dict)
        self.assertEqual(body["error"]["code"], "rate_limited")


class ForwardedForTest(ApiTestCase):
    """信任反代时只认 X-Forwarded-For 的最后一段（单跳可信代理）。"""

    config_overrides = {"register_per_hour": 1, "trust_proxy": True}

    def _register_with_xff(self, forwarded: str) -> tuple[int, dict[str, str], object]:
        return self.request(
            "POST",
            "/api/v1/players",
            body={"nickname": "代理玩家"},
            headers={"X-Forwarded-For": forwarded},
        )

    def test_only_last_forwarded_segment_is_trusted(self) -> None:
        status, _headers, _body = self._register_with_xff("9.9.9.9, 1.2.3.4")
        self.assertEqual(status, 201)

        # 最左段由客户端控制；末段相同即视为同一 IP，仍被限流。
        status, _headers, body = self._register_with_xff("8.8.8.8, 1.2.3.4")
        self.assertEqual(status, 429)
        assert isinstance(body, dict)
        self.assertEqual(body["error"]["code"], "rate_limited")

        # 末段不同则视为另一客户端。
        status, _headers, _body = self._register_with_xff("8.8.8.8, 5.6.7.8")
        self.assertEqual(status, 201)

    def test_duplicate_forwarded_headers_use_last(self) -> None:
        body = b'{"nickname":"dup-xff"}'
        raw = (
            b"POST /api/v1/players HTTP/1.1\r\n"
            b"Host: x\r\n"
            b"X-Forwarded-For: 9.9.9.9\r\n"
            b"X-Forwarded-For: 1.2.3.4\r\n"
            b"Content-Type: application/json\r\n"
            b"Content-Length: "
            + str(len(body)).encode()
            + b"\r\nConnection: close\r\n\r\n"
            + body
        )
        port = int(self.server.server_address[1])
        with socket.create_connection(("127.0.0.1", port), timeout=10) as sock:
            sock.sendall(raw)
            data = b""
            while True:
                chunk = sock.recv(4096)
                if not chunk:
                    break
                data += chunk
        self.assertEqual(int(data.split(b" ", 2)[1]), 201)

        # 最后一跳是 1.2.3.4，已占用本窗口唯一名额；相同末段应被限流。
        status, _headers, _body = self._register_with_xff("1.2.3.4")
        self.assertEqual(status, 429)


class ForwardedForIgnoredTest(ApiTestCase):
    """trust_proxy=False 时忽略 X-Forwarded-For，伪造头无法绕过限流。"""

    config_overrides = {"register_per_hour": 1}

    def test_forwarded_header_ignored_without_trust_proxy(self) -> None:
        self.register("未信任代理一")
        status, _headers, body = self.request(
            "POST",
            "/api/v1/players",
            body={"nickname": "未信任代理二"},
            headers={"X-Forwarded-For": "9.9.9.9"},
        )
        self.assertEqual(status, 429)
        assert isinstance(body, dict)
        self.assertEqual(body["error"]["code"], "rate_limited")


class ResultsRateLimitTest(ApiTestCase):
    config_overrides = {"results_per_hour": 1}

    def test_second_report_is_rate_limited(self) -> None:
        player = self.register("上报限流")
        player_id, token = player["player_id"], player["token"]

        status, _headers, _body = self.report(
            player_id, token, "pve", "win", "rl-event-01"
        )
        self.assertEqual(status, 200)

        # 不同 event_id 仍计入同一玩家的上报限流。
        status, _headers, body = self.report(
            player_id, token, "pve", "win", "rl-event-02"
        )
        self.assertEqual(status, 429)
        assert isinstance(body, dict)
        self.assertEqual(body["error"]["code"], "rate_limited")


# ----------------------------------------------------------------------
# 并发上报
# ----------------------------------------------------------------------


class ConcurrentResultsTest(ApiTestCase):
    def test_concurrent_unique_events_are_all_counted(self) -> None:
        player = self.register("并发玩家")
        player_id, token = player["player_id"], player["token"]

        status, _headers, body = self.request("GET", f"/api/v1/players/{player_id}")
        self.assertEqual(status, 200)
        assert isinstance(body, dict)
        start_games = body["pve"]["games"]

        errors: list[tuple[int, object]] = []
        lock = threading.Lock()

        def worker(worker_index: int) -> None:
            for index in range(50):
                status, _headers, body = helpers.http_request(
                    "POST",
                    f"{self.base_url}/api/v1/players/{player_id}/results",
                    body={
                        "mode": "pve",
                        "result": "win",
                        "event_id": f"conc-{worker_index}-{index:03d}",
                    },
                    token=token,
                )
                if status != 200:
                    with lock:
                        errors.append((status, body))

        threads = [
            threading.Thread(target=worker, args=(worker_index,), daemon=True)
            for worker_index in range(4)
        ]
        for thread in threads:
            thread.start()
        for thread in threads:
            thread.join(timeout=60)

        self.assertFalse(any(thread.is_alive() for thread in threads), "并发请求线程未结束")
        self.assertEqual(errors, [])

        status, _headers, body = self.request("GET", f"/api/v1/players/{player_id}")
        self.assertEqual(status, 200)
        assert isinstance(body, dict)
        self.assertEqual(body["pve"]["games"], start_games + 200)
        self.assertEqual(body["pve"]["wins"], 200)


# ----------------------------------------------------------------------
# 持久化（同一数据库重启服务）
# ----------------------------------------------------------------------


class PersistenceTest(unittest.TestCase):
    def test_stats_survive_server_restart(self) -> None:
        with tempfile.TemporaryDirectory(prefix="warrior-store-persist-") as tmp_dir:
            config = helpers.make_config(tmp_dir)
            with helpers.running_server(config) as (_server, base_url):
                status, _headers, player = helpers.http_request(
                    "POST", f"{base_url}/api/v1/players", body={"nickname": "持久化"}
                )
                self.assertEqual(status, 201)
                assert isinstance(player, dict)
                status, _headers, _body = helpers.http_request(
                    "POST",
                    f"{base_url}/api/v1/players/{player['player_id']}/results",
                    body={"mode": "pve", "result": "win", "event_id": "persist-001"},
                    token=player["token"],
                )
                self.assertEqual(status, 200)

            with helpers.running_server(config) as (_server, base_url):
                status, _headers, body = helpers.http_request(
                    "GET", f"{base_url}/api/v1/players/{player['player_id']}"
                )
                self.assertEqual(status, 200)
                assert isinstance(body, dict)
                self.assertEqual(body["pve"], {"games": 1, "wins": 1, "win_rate": 1.0})
                self.assertEqual(body["nickname"], "持久化")

                status, _headers, body = helpers.http_request(
                    "POST",
                    f"{base_url}/api/v1/players/{player['player_id']}/results",
                    body={"mode": "pvp", "result": "loss", "event_id": "persist-002"},
                    token=player["token"],
                )
                self.assertEqual(status, 200)
                assert isinstance(body, dict)
                self.assertEqual(body["pvp"], {"games": 1, "wins": 0, "win_rate": 0.0})


class PepperTest(unittest.TestCase):
    """pepper 参与 token 哈希：同一 pepper 重启后可鉴权，换 pepper 后失效。"""

    def test_pepper_survives_restart_and_wrong_pepper_is_rejected(self) -> None:
        with tempfile.TemporaryDirectory(prefix="warrior-store-pepper-") as tmp_dir:
            config = helpers.make_config(tmp_dir, pepper="pepper-one")
            with helpers.running_server(config) as (_server, base_url):
                status, _headers, player = helpers.http_request(
                    "POST", f"{base_url}/api/v1/players", body={"nickname": "胡椒"}
                )
                self.assertEqual(status, 201)
                assert isinstance(player, dict)
                status, _headers, _body = helpers.http_request(
                    "POST",
                    f"{base_url}/api/v1/players/{player['player_id']}/results",
                    body={"mode": "pve", "result": "win", "event_id": "pepper-001"},
                    token=player["token"],
                )
                self.assertEqual(status, 200)

            with helpers.running_server(config) as (_server, base_url):
                status, _headers, _body = helpers.http_request(
                    "POST",
                    f"{base_url}/api/v1/players/{player['player_id']}/results",
                    body={"mode": "pve", "result": "win", "event_id": "pepper-002"},
                    token=player["token"],
                )
                self.assertEqual(status, 200)

            wrong = helpers.make_config(tmp_dir, pepper="pepper-two")
            with helpers.running_server(wrong) as (_server, base_url):
                status, _headers, body = helpers.http_request(
                    "POST",
                    f"{base_url}/api/v1/players/{player['player_id']}/results",
                    body={"mode": "pve", "result": "win", "event_id": "pepper-003"},
                    token=player["token"],
                )
                self.assertEqual(status, 401)
                assert isinstance(body, dict)
                self.assertEqual(body["error"]["code"], "unauthorized")


class AccessLogTest(ApiTestCase):
    config_overrides = {"access_log": True}

    def test_token_never_appears_in_access_log(self) -> None:
        with self.assertLogs("warrior_store.access", level="INFO") as captured:
            player = self.register("日志玩家")
            status, _headers, _body = self.report(
                player["player_id"], player["token"], event_id="log-0001"
            )
            self.assertEqual(status, 200)
            # 客户端先读到响应，服务端 handler 的 finally 可能稍后才写日志。
            time.sleep(0.1)
        joined = "\n".join(captured.output)
        self.assertNotIn(player["token"], joined)
        self.assertIn(player["player_id"], joined)


class KeepAliveTest(ApiTestCase):
    def test_two_requests_on_same_connection(self) -> None:
        port = int(self.server.server_address[1])
        connection = http.client.HTTPConnection("127.0.0.1", port, timeout=10)
        try:
            body = json.dumps({"nickname": "长连接"}).encode("utf-8")
            connection.request(
                "POST",
                "/api/v1/players",
                body=body,
                headers={"Content-Type": "application/json"},
            )
            response = connection.getresponse()
            response.read()
            self.assertEqual(response.status, 201)

            connection.request("GET", "/healthz")
            response = connection.getresponse()
            data = response.read()
            self.assertEqual(response.status, 200)
            self.assertIn(b'"status":"ok"', data)
        finally:
            connection.close()


if __name__ == "__main__":  # pragma: no cover
    unittest.main()
