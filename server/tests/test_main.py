"""命令行入口测试：配置错误返回 2，数据库启动错误返回 1 且不打印 traceback。"""

from __future__ import annotations

import contextlib
import io
import tempfile
import unittest

from app.main import main


class MainTest(unittest.TestCase):
    def test_invalid_config_returns_2(self) -> None:
        stderr = io.StringIO()
        with contextlib.redirect_stderr(stderr):
            code = main(["--port", "70000"])
        self.assertEqual(code, 2)
        self.assertIn("配置错误", stderr.getvalue())

    def test_database_directory_returns_1(self) -> None:
        stderr = io.StringIO()
        with tempfile.TemporaryDirectory(prefix="warrior-store-main-") as tmp_dir:
            with contextlib.redirect_stderr(stderr):
                code = main(["--db", tmp_dir, "--port", "0"])
        self.assertEqual(code, 1)
        self.assertIn("服务启动失败", stderr.getvalue())
        self.assertNotIn("Traceback", stderr.getvalue())


if __name__ == "__main__":  # pragma: no cover
    unittest.main()
