"""令牌工具：token 即密码，服务端只保存哈希，永不保存明文。

- 玩家 ID：``p_`` 前缀 + 8 字节随机十六进制（共 18 字符）；
- token：``secrets.token_urlsafe(32)``，只在注册响应中返回一次；
- 存储哈希：默认 ``SHA-256(token)``；配置 pepper 时用 ``HMAC-SHA256(pepper, token)``；
- 校验一律走 ``hmac.compare_digest``（常数时间），任何异常输入都返回 False。
"""

from __future__ import annotations

import hashlib
import hmac
import secrets


def new_player_id() -> str:
    """生成玩家 ID：``p_`` + 8 字节随机十六进制（共 18 字符）。"""
    return "p_" + secrets.token_hex(8)


def new_token() -> str:
    """生成 32 字节随机 token（URL 安全 Base64，43 字符）。"""
    return secrets.token_urlsafe(32)


def hash_token(token: str, pepper: str = "") -> bytes:
    """计算 token 的存储哈希。

    无 pepper 时为 ``SHA-256(token)``；有 pepper 时为 ``HMAC-SHA256(pepper, token)``。
    pepper 一旦启用便不可更改，否则所有已发 token 立即失效。
    """
    data = token.encode("utf-8")
    if pepper:
        return hmac.new(pepper.encode("utf-8"), data, hashlib.sha256).digest()
    return hashlib.sha256(data).digest()


def token_matches(token: str, stored_hash: bytes, pepper: str = "") -> bool:
    """常数时间比较 token 与存储哈希。

    输入异常（None、非 bytes、非 str、编码失败等）一律返回 False，绝不抛异常，
    避免把校验细节泄露给调用方。
    """
    try:
        if not isinstance(token, str) or not isinstance(stored_hash, bytes):
            return False
        return hmac.compare_digest(hash_token(token, pepper), stored_hash)
    except Exception:
        return False
