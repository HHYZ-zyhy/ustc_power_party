"""配置测试：默认值、环境变量覆盖、命令行优先级与非法值拒绝。"""

from __future__ import annotations

import unittest
from pathlib import Path

from app.config import Config, load_config


class ConfigDefaultsTest(unittest.TestCase):
    def test_defaults(self) -> None:
        config = load_config([], env={})
        self.assertIsInstance(config, Config)
        self.assertEqual(config.host, "127.0.0.1")
        self.assertEqual(config.port, 8080)
        self.assertEqual(config.db_path, Path("data/store.sqlite3"))
        self.assertEqual(config.pepper, "")
        self.assertEqual(config.log_level, "INFO")
        self.assertTrue(config.log_ip)
        self.assertTrue(config.access_log)
        self.assertEqual(config.register_per_hour, 20)
        self.assertEqual(config.results_per_hour, 600)
        self.assertFalse(config.trust_proxy)
        self.assertEqual(config.version, "1.0.0")


class ConfigEnvTest(unittest.TestCase):
    def test_env_overrides_defaults(self) -> None:
        env = {
            "WARRIOR_STORE_HOST": "0.0.0.0",
            "WARRIOR_STORE_PORT": "9123",
            "WARRIOR_STORE_DB": "/tmp/env-store.sqlite3",
            "WARRIOR_STORE_PEPPER": "pepper-value",
            "WARRIOR_STORE_LOG_LEVEL": "debug",
            "WARRIOR_STORE_LOG_IP": "0",
            "WARRIOR_STORE_ACCESS_LOG": "no",
            "WARRIOR_STORE_REGISTER_PER_HOUR": "5",
            "WARRIOR_STORE_RESULTS_PER_HOUR": "1200",
            "WARRIOR_STORE_TRUST_PROXY": "yes",
        }
        config = load_config([], env=env)
        self.assertEqual(config.host, "0.0.0.0")
        self.assertEqual(config.port, 9123)
        self.assertEqual(config.db_path, Path("/tmp/env-store.sqlite3"))
        self.assertEqual(config.pepper, "pepper-value")
        self.assertEqual(config.log_level, "DEBUG")
        self.assertFalse(config.log_ip)
        self.assertFalse(config.access_log)
        self.assertEqual(config.register_per_hour, 5)
        self.assertEqual(config.results_per_hour, 1200)
        self.assertTrue(config.trust_proxy)

    def test_argv_overrides_env(self) -> None:
        env = {
            "WARRIOR_STORE_HOST": "10.0.0.1",
            "WARRIOR_STORE_PORT": "9000",
            "WARRIOR_STORE_DB": "/tmp/env-store.sqlite3",
            "WARRIOR_STORE_LOG_LEVEL": "ERROR",
            "WARRIOR_STORE_REGISTER_PER_HOUR": "7",
        }
        config = load_config(
            [
                "--host",
                "127.0.0.2",
                "--port",
                "9001",
                "--db",
                "/tmp/argv-store.sqlite3",
                "--log-level",
                "warning",
            ],
            env=env,
        )
        self.assertEqual(config.host, "127.0.0.2")
        self.assertEqual(config.port, 9001)
        self.assertEqual(config.db_path, Path("/tmp/argv-store.sqlite3"))
        self.assertEqual(config.log_level, "WARNING")
        # 没有命令行开关的项仍来自环境变量。
        self.assertEqual(config.register_per_hour, 7)

    def test_env_bool_accepts_true_and_false(self) -> None:
        for value in ("1", "true", "TRUE", "yes", " On "):
            with self.subTest(value=value):
                config = load_config([], env={"WARRIOR_STORE_TRUST_PROXY": value})
                self.assertTrue(config.trust_proxy)
        for value in ("0", "false", "False", "no", " OFF "):
            with self.subTest(value=value):
                config = load_config([], env={"WARRIOR_STORE_ACCESS_LOG": value})
                self.assertFalse(config.access_log)

    def test_env_bool_rejects_invalid_value(self) -> None:
        with self.assertRaises(ValueError):
            load_config([], env={"WARRIOR_STORE_LOG_IP": "maybe"})

    def test_env_integer_rejects_invalid_value(self) -> None:
        with self.assertRaises(ValueError):
            load_config([], env={"WARRIOR_STORE_PORT": "not-a-port"})
        with self.assertRaises(ValueError):
            load_config([], env={"WARRIOR_STORE_REGISTER_PER_HOUR": "many"})
        with self.assertRaises(ValueError):
            load_config([], env={"WARRIOR_STORE_RESULTS_PER_HOUR": "many"})


class ConfigValidationTest(unittest.TestCase):
    def test_port_out_of_range(self) -> None:
        with self.assertRaises(ValueError):
            load_config(["--port", "65536"], env={})
        with self.assertRaises(ValueError):
            load_config(["--port", "-1"], env={})

    def test_port_zero_allowed(self) -> None:
        config = load_config(["--port", "0"], env={})
        self.assertEqual(config.port, 0)

    def test_log_level_must_be_known(self) -> None:
        with self.assertRaises(ValueError):
            load_config(["--log-level", "LOUD"], env={})
        with self.assertRaises(ValueError):
            load_config([], env={"WARRIOR_STORE_LOG_LEVEL": "TRACE"})

    def test_negative_register_limit_rejected(self) -> None:
        with self.assertRaises(ValueError):
            load_config([], env={"WARRIOR_STORE_REGISTER_PER_HOUR": "-1"})

    def test_negative_results_limit_rejected(self) -> None:
        with self.assertRaises(ValueError):
            load_config([], env={"WARRIOR_STORE_RESULTS_PER_HOUR": "-1"})

    def test_zero_results_limit_allowed(self) -> None:
        config = load_config([], env={"WARRIOR_STORE_RESULTS_PER_HOUR": "0"})
        self.assertEqual(config.results_per_hour, 0)

    def test_empty_host_rejected(self) -> None:
        with self.assertRaises(ValueError):
            load_config(["--host", "   "], env={})

    def test_cli_port_overrides_invalid_env(self) -> None:
        # 命令行显式给出端口时，不应先解析（可能非法的）环境变量。
        config = load_config(["--port", "9000"], env={"WARRIOR_STORE_PORT": "bad"})
        self.assertEqual(config.port, 9000)

    def test_empty_db_path_rejected(self) -> None:
        with self.assertRaises(ValueError):
            load_config(["--db", "   "], env={})
        with self.assertRaises(ValueError):
            load_config([], env={"WARRIOR_STORE_DB": ""})

    def test_memory_and_uri_db_rejected(self) -> None:
        with self.assertRaises(ValueError):
            load_config(["--db", ":memory:"], env={})
        with self.assertRaises(ValueError):
            load_config(["--db", "file:store.sqlite3?mode=rw"], env={})


if __name__ == "__main__":  # pragma: no cover
    unittest.main()
