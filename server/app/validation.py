"""输入校验：昵称、模式、结果、事件 ID、玩家 ID。

规则与错误码严格对齐 ``API.md``；所有非法输入统一抛出 400 的 ``ApiError``，
由 HTTP 层原样转换为 ``{"error": {"code", "message"}}``。
"""

from __future__ import annotations

import re

from .errors import bad_request

MAX_NICKNAME_LEN = 24
PLAYER_ID_RE = re.compile(r"^p_[0-9a-f]{16}$")

# 客户端生成的事件 ID：8~64 位字母、数字、下划线或连字符
_EVENT_ID_RE = re.compile(r"[A-Za-z0-9_-]{8,64}")

_MODES = frozenset({"pve", "pvp"})
_RESULTS = frozenset({"win", "loss"})

# 明确拒绝的额外字符：Unicode 行分隔符与段分隔符（避免日志/文本注入）。
# 不按 Unicode 类别一刀切，以免误杀中文、emoji 与组合字符。
_FORBIDDEN_NICKNAME_CHARS = frozenset({"\u2028", "\u2029"})

_NICKNAME_LENGTH_MESSAGE = "昵称长度必须为 1~24 个字符"
_NICKNAME_CHAR_MESSAGE = "昵称包含非法字符"


def _has_forbidden_char(text: str) -> bool:
    """昵称是否含控制字符（\\x00-\\x1f、\\x7f）、孤立代理项或 Unicode 行/段分隔符。

    孤立代理项（U+D800~U+DFFF）无法编码为 UTF-8，入库时会在 SQLite 层抛
    ``UnicodeEncodeError``；在入口直接按非法字符拒绝。
    """
    for char in text:
        code = ord(char)
        if code < 0x20 or code == 0x7F:
            return True
        if 0xD800 <= code <= 0xDFFF:
            return True
        if char in _FORBIDDEN_NICKNAME_CHARS:
            return True
    return False


def validate_nickname(raw) -> str:
    """校验昵称：必须是 str，strip 后 1~24 个 Unicode 码点，且不含控制字符。

    返回 strip 后的昵称；非法时抛出 ``invalid_nickname``。昵称可重名。
    """
    if not isinstance(raw, str):
        raise bad_request("invalid_nickname", _NICKNAME_LENGTH_MESSAGE)
    nickname = raw.strip()
    if not 1 <= len(nickname) <= MAX_NICKNAME_LEN:
        raise bad_request("invalid_nickname", _NICKNAME_LENGTH_MESSAGE)
    if _has_forbidden_char(nickname):
        raise bad_request("invalid_nickname", _NICKNAME_CHAR_MESSAGE)
    return nickname


def validate_mode(raw) -> str:
    """校验对局模式：只接受 ``pve`` / ``pvp``（大小写敏感）。"""
    if not isinstance(raw, str) or raw not in _MODES:
        raise bad_request("invalid_mode", "mode 必须为 pve 或 pvp")
    return raw


def validate_result(raw) -> str:
    """校验对局结果：只接受 ``win`` / ``loss``（大小写敏感）。"""
    if not isinstance(raw, str) or raw not in _RESULTS:
        raise bad_request("invalid_result", "result 必须为 win 或 loss")
    return raw


def validate_event_id(raw) -> str | None:
    """校验幂等事件 ID：``None`` 原样返回；否则必须匹配 8~64 位 ``[A-Za-z0-9_-]``。"""
    if raw is None:
        return None
    if not isinstance(raw, str) or _EVENT_ID_RE.fullmatch(raw) is None:
        raise bad_request(
            "invalid_event_id",
            "event_id 必须为 8~64 位字母、数字、下划线或连字符",
        )
    return raw


def validate_player_id(raw) -> str:
    """校验玩家 ID：``p_`` + 16 位小写十六进制，共 18 字符。"""
    if not isinstance(raw, str) or PLAYER_ID_RE.fullmatch(raw) is None:
        raise bad_request("invalid_player_id", "玩家 ID 格式不合法")
    return raw


# 供静态检查与调用方类型标注使用；bad_request 的返回值类型即 ApiError。
__all__ = [
    "MAX_NICKNAME_LEN",
    "PLAYER_ID_RE",
    "validate_event_id",
    "validate_mode",
    "validate_nickname",
    "validate_player_id",
    "validate_result",
]
