"""RateLimiter 单元测试：窗口、关闭、并发与硬上限。"""

from __future__ import annotations

import threading
import time
import unittest
from unittest import mock

from app import ratelimit as ratelimit_module
from app.ratelimit import RateLimiter


class RateLimiterTest(unittest.TestCase):
    def test_limit_and_window_expiry(self) -> None:
        limiter = RateLimiter(limit=2, window_seconds=0.15)
        self.assertTrue(limiter.allow("k"))
        self.assertTrue(limiter.allow("k"))
        self.assertFalse(limiter.allow("k"))
        time.sleep(0.2)
        self.assertTrue(limiter.allow("k"))

    def test_zero_limit_disables(self) -> None:
        limiter = RateLimiter(limit=0)
        for _ in range(100):
            self.assertTrue(limiter.allow("k"))

    def test_concurrent_allow_is_exact(self) -> None:
        limiter = RateLimiter(limit=500, window_seconds=60)
        allowed = 0
        lock = threading.Lock()
        barrier = threading.Barrier(8)

        def worker() -> None:
            nonlocal allowed
            barrier.wait()
            local = 0
            for _ in range(100):
                if limiter.allow("same-key"):
                    local += 1
            with lock:
                allowed += local

        threads = [threading.Thread(target=worker) for _ in range(8)]
        for thread in threads:
            thread.start()
        for thread in threads:
            thread.join(timeout=30)
        self.assertFalse(any(thread.is_alive() for thread in threads))
        self.assertEqual(allowed, 500)

    def test_hard_cap_evicts_oldest_instead_of_clearing(self) -> None:
        with mock.patch.object(ratelimit_module, "_MAX_ENTRIES", 3), \
                mock.patch.object(ratelimit_module, "_HARD_MAX_ENTRIES", 5):
            limiter = RateLimiter(limit=1, window_seconds=3600)
            with self.assertLogs("warrior_store", level="WARNING"):
                for index in range(10):
                    self.assertTrue(limiter.allow(f"key-{index}"))
            # 淘汰后仍受硬上限约束，但不会把整表清空导致所有 key 重新放行。
            self.assertLessEqual(len(limiter._hits), 5)
            self.assertGreater(len(limiter._hits), 0)


if __name__ == "__main__":  # pragma: no cover
    unittest.main()
