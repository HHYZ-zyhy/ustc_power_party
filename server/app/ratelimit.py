"""固定窗口内存限流：按 key（客户端 IP 或玩家 ID）计数。

- 计数保存在进程内存，进程重启清零；多实例部署不共享（当前单实例）。
- 固定窗口以 ``time.monotonic()`` 为准，不受系统时钟跳变影响。
- ``limit <= 0`` 表示关闭限流（``allow`` 永远返回 True）。
- 线程安全：所有读写都在 ``threading.Lock`` 内完成。
"""

from __future__ import annotations

import logging
import threading
import time

from .log import APP_LOGGER

# 字典条目超过该阈值时顺带清理过期项，避免长期运行内存无限增长。
_MAX_ENTRIES = 10000
# 清理后仍超过该硬上限时淘汰最旧条目（避免进程 OOM）。
_HARD_MAX_ENTRIES = 50000
# 清理的最小间隔（秒）：避免每个请求都在全局锁内做 O(n) 扫描。
_CLEANUP_INTERVAL = 60.0


class RateLimiter:
    """固定窗口限流器。

    ``limit`` 为每个窗口内允许的次数；``window_seconds`` 为窗口长度（秒）。
    """

    def __init__(self, limit: int, window_seconds: float = 3600.0) -> None:
        self._limit = int(limit)
        self._window = float(window_seconds)
        self._lock = threading.Lock()
        # key -> (窗口开始时间, 窗口内已计数)
        self._hits: dict[str, tuple[float, int]] = {}
        # 上次清理时间；初始化为“已到期”，首次超阈值即可清理。
        self._last_cleanup = time.monotonic() - _CLEANUP_INTERVAL

    def allow(self, key: str) -> bool:
        """记一次请求；未超限返回 True，超限返回 False。

        ``limit <= 0`` 时关闭限流，直接返回 True（不写内存）。
        无论放行还是拒绝，条目数超过阈值时都会顺带清理；清理后仍超过硬上限
        则清空整表（避免被大量不同 key 拖垮内存）。
        """
        if self._limit <= 0:
            return True

        now = time.monotonic()
        with self._lock:
            window_start, count = self._hits.get(key, (now, 0))
            if now - window_start >= self._window:
                # 窗口已过期，重新开始计数。
                window_start, count = now, 0
            allowed = count < self._limit
            if allowed:
                count += 1
            self._hits[key] = (window_start, count)
            if len(self._hits) > _MAX_ENTRIES and now - self._last_cleanup >= _CLEANUP_INTERVAL:
                self._cleanup(now)
                self._last_cleanup = now
            if len(self._hits) > _HARD_MAX_ENTRIES:
                # 仍然过多：按插入顺序淘汰最旧的一批（不清空整表，避免所有
                # 正在被限流的 key 突然全部放行）。
                overflow = len(self._hits) - _MAX_ENTRIES
                for oldest in list(self._hits)[:overflow]:
                    del self._hits[oldest]
                logging.getLogger(APP_LOGGER).warning(
                    "限流表超过硬上限，已淘汰 %d 个最旧条目", overflow
                )
            return allowed

    def _cleanup(self, now: float) -> None:
        """清理窗口已过期的条目（调用方必须已持有锁）。"""
        expired = [
            key
            for key, (window_start, _count) in self._hits.items()
            if now - window_start >= self._window
        ]
        for key in expired:
            del self._hits[key]
