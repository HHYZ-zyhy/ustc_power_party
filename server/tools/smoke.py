#!/usr/bin/env python3
"""科大战力党玩家数据存储服务：跨平台 HTTP 冒烟测试（仅标准库）。

自起一个临时服务与临时数据库，走完整 API 流程；失败以非 0 退出。
不依赖 app/main.py 之外的任何组件；请先确保 HTTP 层已实现。

用法：
    python server/tools/smoke.py
    cd server && python tools/smoke.py
"""

from __future__ import annotations

import json
import sys
import tempfile
import threading
import urllib.error
import urllib.request
from pathlib import Path

SERVER_ROOT = Path(__file__).resolve().parents[1]
if str(SERVER_ROOT) not in sys.path:
    sys.path.insert(0, str(SERVER_ROOT))

# 显式禁用代理：本脚本只访问 127.0.0.1，环境里的 http_proxy/https_proxy
# 不应把本机请求转发出去（否则会误报连接失败或走到外部代理）。
_OPENER = urllib.request.build_opener(urllib.request.ProxyHandler({}))


class SmokeError(Exception):
    """冒烟测试断言失败（消息直接展示给维护者）。"""


class Client:
    def __init__(self, base_url: str) -> None:
        self.base_url = base_url.rstrip("/")

    def request(
        self,
        method: str,
        path: str,
        *,
        body: dict | None = None,
        token: str | None = None,
    ) -> tuple[int, object]:
        url = self.base_url + path
        data = None
        headers = {"Accept": "application/json"}
        if body is not None:
            data = json.dumps(body, ensure_ascii=False).encode("utf-8")
            headers["Content-Type"] = "application/json; charset=utf-8"
        if token:
            headers["Authorization"] = f"Bearer {token}"

        request = urllib.request.Request(url, data=data, headers=headers, method=method)
        try:
            with _OPENER.open(request, timeout=10) as response:
                status = response.status
                raw = response.read()
        except urllib.error.HTTPError as exc:
            status = exc.code
            raw = exc.read()
        except urllib.error.URLError as exc:
            raise SmokeError(f"请求 {method} {path} 失败：{exc}") from exc

        if not raw:
            return status, None
        try:
            return status, json.loads(raw.decode("utf-8"))
        except (UnicodeDecodeError, json.JSONDecodeError) as exc:
            preview = raw[:120]
            raise SmokeError(
                f"{method} {path} 返回非 JSON 内容（HTTP {status}）：{preview!r}"
            ) from exc


def _ok(message: str) -> None:
    print(f"[OK] {message}", flush=True)


def _fail(message: str) -> None:
    raise SmokeError(message)


def _expect_status(method: str, path: str, status: int, expected: int, body: object) -> None:
    if status != expected:
        _fail(f"{method} {path} 期望 HTTP {expected}，实际 {status}：{body!r}")


def _expect_stats(body: object, mode: str, games: int, wins: int, rate: float | None) -> None:
    if not isinstance(body, dict):
        _fail(f"响应不是 JSON 对象：{body!r}")
    block = body.get(mode)
    if not isinstance(block, dict):
        _fail(f"响应缺少 {mode} 统计：{body!r}")
    actual = (block.get("games"), block.get("wins"), block.get("win_rate"))
    expected = (games, wins, rate)
    if actual != expected:
        _fail(f"{mode} 统计不符：期望 games={games} wins={wins} win_rate={rate}，实际 {actual}")


def _expect_error(body: object, code: str) -> None:
    if not isinstance(body, dict):
        _fail(f"错误响应不是 JSON 对象：{body!r}")
    error = body.get("error")
    if not isinstance(error, dict) or error.get("code") != code:
        _fail(f"错误码期望 {code}，实际 {body!r}")


def run_checks(client: Client) -> None:
    # 1. 健康检查
    status, body = client.request("GET", "/healthz")
    _expect_status("GET", "/healthz", status, 200, body)
    if not isinstance(body, dict) or body.get("status") != "ok" or body.get("db") != "ok":
        _fail(f"/healthz 响应异常：{body!r}")
    _ok(f"/healthz 200（version={body.get('version')}, db=ok）")

    # 2. 注册
    status, body = client.request(
        "POST", "/api/v1/players", body={"nickname": "冒烟测试员"}
    )
    _expect_status("POST", "/api/v1/players", status, 201, body)
    if not isinstance(body, dict):
        _fail(f"注册响应不是 JSON 对象：{body!r}")
    player_id = body.get("player_id")
    token = body.get("token")
    if not isinstance(player_id, str) or not player_id.startswith("p_") or len(player_id) != 18:
        _fail(f"player_id 格式不符（应为 p_ + 16 位十六进制）：{player_id!r}")
    if body.get("short_id") != player_id[:6]:
        _fail(f"short_id 应为 player_id 前 6 位：{body.get('short_id')!r}")
    if body.get("nickname") != "冒烟测试员":
        _fail(f"昵称回显不符：{body.get('nickname')!r}")
    if not isinstance(token, str) or not token:
        _fail("注册响应缺少 token")
    _ok(f"注册成功（player_id={player_id}, short_id={body.get('short_id')}）")

    # 3. 新玩家统计为零
    status, body = client.request("GET", f"/api/v1/players/{player_id}")
    _expect_status("GET", f"/api/v1/players/{player_id}", status, 200, body)
    _expect_stats(body, "pve", 0, 0, None)
    _expect_stats(body, "pvp", 0, 0, None)
    _ok("查询新玩家：PVE/PVP 均为 games=0 wins=0 win_rate=null")

    # 4-6. 上报三场：PVE 胜、PVE 负、PVP 胜
    pve_win_event = "smoke-pve-win-01"
    status, body = client.request(
        "POST",
        f"/api/v1/players/{player_id}/results",
        body={"mode": "pve", "result": "win", "event_id": pve_win_event},
        token=token,
    )
    _expect_status("POST", "results(pve win)", status, 200, body)
    if not isinstance(body, dict) or body.get("duplicate") is not False:
        _fail(f"首次上报不应是 duplicate：{body!r}")
    _expect_stats(body, "pve", 1, 1, 1.0)
    _ok("上报 PVE 胜：pve games=1 wins=1 win_rate=1.0")

    status, body = client.request(
        "POST",
        f"/api/v1/players/{player_id}/results",
        body={"mode": "pve", "result": "loss", "event_id": "smoke-pve-loss-01"},
        token=token,
    )
    _expect_status("POST", "results(pve loss)", status, 200, body)
    _expect_stats(body, "pve", 2, 1, 0.5)
    _ok("上报 PVE 负：pve games=2 wins=1 win_rate=0.5")

    status, body = client.request(
        "POST",
        f"/api/v1/players/{player_id}/results",
        body={"mode": "pvp", "result": "win", "event_id": "smoke-pvp-win-01"},
        token=token,
    )
    _expect_status("POST", "results(pvp win)", status, 200, body)
    _expect_stats(body, "pve", 2, 1, 0.5)
    _expect_stats(body, "pvp", 1, 1, 1.0)
    _ok("上报 PVP 胜：pvp games=1 wins=1，且 PVE 不受影响")

    # 7. 查询校验最终统计
    status, body = client.request("GET", f"/api/v1/players/{player_id}")
    _expect_status("GET", f"/api/v1/players/{player_id}", status, 200, body)
    _expect_stats(body, "pve", 2, 1, 0.5)
    _expect_stats(body, "pvp", 1, 1, 1.0)
    _ok("查询校验：pve games=2 wins=1 win_rate=0.5；pvp games=1 wins=1 win_rate=1.0")

    # 8. 同 event_id 重发：duplicate 且不重复计数
    status, body = client.request(
        "POST",
        f"/api/v1/players/{player_id}/results",
        body={"mode": "pve", "result": "win", "event_id": pve_win_event},
        token=token,
    )
    _expect_status("POST", "results(duplicate)", status, 200, body)
    if not isinstance(body, dict) or body.get("duplicate") is not True:
        _fail(f"重复 event_id 应返回 duplicate=true：{body!r}")
    _expect_stats(body, "pve", 2, 1, 0.5)
    _ok("同 event_id 重发：duplicate=true，统计仍为 pve games=2 wins=1")

    # 9. 批量查询（未知 ID 省略）
    status, body = client.request(
        "GET", f"/api/v1/players?ids={player_id},p_0000000000000000"
    )
    _expect_status("GET", "players?ids=...", status, 200, body)
    if not isinstance(body, dict) or not isinstance(body.get("players"), list):
        _fail(f"批量查询响应缺少 players 数组：{body!r}")
    players = body["players"]
    if len(players) != 1 or players[0].get("player_id") != player_id:
        _fail(f"批量查询应包含 1 个已知玩家、省略未知 ID：{players!r}")
    _ok("批量查询：包含该玩家，未知 ID 被省略")

    # 10. 改昵称
    status, body = client.request(
        "PATCH",
        f"/api/v1/players/{player_id}",
        body={"nickname": "冒烟测试员改"},
        token=token,
    )
    _expect_status("PATCH", f"/api/v1/players/{player_id}", status, 200, body)
    if not isinstance(body, dict) or body.get("nickname") != "冒烟测试员改":
        _fail(f"改昵称后响应不符：{body!r}")
    _ok("PATCH 改名成功")

    # 11. 删除本人数据
    status, body = client.request(
        "DELETE", f"/api/v1/players/{player_id}", token=token
    )
    _expect_status("DELETE", f"/api/v1/players/{player_id}", status, 204, body)
    _ok("DELETE 返回 204 No Content")

    # 12. 删除后再查询应为 404
    status, body = client.request("GET", f"/api/v1/players/{player_id}")
    _expect_status("GET", f"/api/v1/players/{player_id}", status, 404, body)
    _expect_error(body, "not_found")
    _ok("删除后查询返回 404 not_found")


def main() -> int:
    try:
        from app import config as app_config
        from app import main as app_main
    except Exception as exc:  # app/main.py 由 HTTP 层实现，缺失时给出明确提示
        print(f"冒烟测试失败：无法导入 app.config / app.main：{exc}", file=sys.stderr)
        print("请确认 server/app/main.py 已实现（make_server/run）。", file=sys.stderr)
        return 1

    with tempfile.TemporaryDirectory(prefix="warrior-store-smoke-") as tmp_dir:
        db_path = Path(tmp_dir) / "store.sqlite3"
        try:
            config = app_config.Config(
                host="127.0.0.1",
                port=0,
                db_path=db_path,
                access_log=False,
            )
            server = app_main.make_server(config)
        except Exception as exc:
            print(f"冒烟测试失败：无法启动临时服务：{type(exc).__name__}: {exc}", file=sys.stderr)
            return 1

        server_thread = threading.Thread(
            target=server.serve_forever, name="smoke-server", daemon=True
        )
        server_thread.start()
        port = int(server.server_address[1])
        base_url = f"http://127.0.0.1:{port}"
        print(f"临时服务已启动：{base_url}（数据库：{db_path}）", flush=True)

        try:
            run_checks(Client(base_url))
        except SmokeError as exc:
            print(f"冒烟测试失败：{exc}", file=sys.stderr)
            return 1
        except Exception as exc:
            print(f"冒烟测试失败（未预期异常）：{type(exc).__name__}: {exc}", file=sys.stderr)
            return 1
        finally:
            server.shutdown()
            server.server_close()
            server_thread.join(timeout=5)

    print("SMOKE OK", flush=True)
    return 0


if __name__ == "__main__":
    sys.exit(main())
