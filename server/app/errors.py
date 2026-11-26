"""统一 API 错误：业务层与 HTTP 层共用，避免各处手写状态码/文案。"""

from __future__ import annotations


class ApiError(Exception):
    """可安全返回给客户端的错误（不包含内部细节）。"""

    def __init__(
        self,
        status: int,
        code: str,
        message: str,
        headers: dict[str, str] | None = None,
    ) -> None:
        super().__init__(message)
        self.status = status
        self.code = code
        self.message = message
        self.headers = headers or {}

    def body(self) -> dict:
        return {"error": {"code": self.code, "message": self.message}}


def bad_request(code: str, message: str) -> ApiError:
    return ApiError(400, code, message)


def unauthorized(message: str = "缺少或无效的访问令牌") -> ApiError:
    return ApiError(401, "unauthorized", message, {"WWW-Authenticate": "Bearer"})


def not_found(message: str = "资源不存在") -> ApiError:
    return ApiError(404, "not_found", message)


def method_not_allowed(allow: str) -> ApiError:
    return ApiError(
        405,
        "method_not_allowed",
        "该路径不支持此请求方法",
        {"Allow": allow},
    )


def payload_too_large(limit: int) -> ApiError:
    return ApiError(413, "payload_too_large", f"请求体超过上限（{limit} 字节）")


def rate_limited(message: str = "请求过于频繁，请稍后再试") -> ApiError:
    # 固定窗口为 1 小时（注册与上报均如此）；Retry-After 与窗口保持一致，
    # 避免客户端按 60 秒重试却仍被限流。
    return ApiError(429, "rate_limited", message, {"Retry-After": "3600"})


def internal_error() -> ApiError:
    return ApiError(500, "internal_error", "服务端内部错误")
