"""输入校验单元测试：昵称、mode、result、event_id、player_id 的边界与错误码。"""

from __future__ import annotations

import unittest

from app.errors import ApiError
from app.validation import (
    MAX_NICKNAME_LEN,
    PLAYER_ID_RE,
    validate_event_id,
    validate_mode,
    validate_nickname,
    validate_player_id,
    validate_result,
)


class ValidationTestCase(unittest.TestCase):
    """公共断言：校验非法输入统一为 400 + 指定错误码。"""

    def assert_api_error(self, code: str, func, *args, message: str | None = None) -> ApiError:
        with self.assertRaises(ApiError) as ctx:
            func(*args)
        error = ctx.exception
        self.assertEqual(error.status, 400)
        self.assertEqual(error.code, code)
        if message is not None:
            self.assertEqual(error.message, message)
        return error


class NicknameTest(ValidationTestCase):
    def test_accepts_chinese(self) -> None:
        self.assertEqual(validate_nickname("科大路人甲"), "科大路人甲")

    def test_strips_surrounding_whitespace(self) -> None:
        self.assertEqual(validate_nickname("  科大路人甲  "), "科大路人甲")
        self.assertEqual(validate_nickname("\t名字\n"), "名字")

    def test_exactly_max_length_accepted(self) -> None:
        name = "字" * MAX_NICKNAME_LEN
        self.assertEqual(len(name), 24)
        self.assertEqual(validate_nickname(name), name)

    def test_one_over_max_length_rejected(self) -> None:
        self.assert_api_error(
            "invalid_nickname",
            validate_nickname,
            "字" * (MAX_NICKNAME_LEN + 1),
            message="昵称长度必须为 1~24 个字符",
        )

    def test_empty_and_blank_rejected(self) -> None:
        for raw in ("", "   ", "\n", "\t \t"):
            with self.subTest(raw=raw):
                self.assert_api_error(
                    "invalid_nickname",
                    validate_nickname,
                    raw,
                    message="昵称长度必须为 1~24 个字符",
                )

    def test_control_and_separator_chars_rejected(self) -> None:
        for raw in (
            "坏\x00名",
            "坏\n名",
            "坏\r名",
            "坏\t名",
            "坏\x1f名",
            "坏\x7f名",
            "坏\u2028名",
            "坏\u2029名",
            "\ud800",
            "坏\udfff名",
        ):
            with self.subTest(raw=repr(raw)):
                self.assert_api_error(
                    "invalid_nickname",
                    validate_nickname,
                    raw,
                    message="昵称包含非法字符",
                )

    def test_non_str_rejected(self) -> None:
        for raw in (None, 123, 1.5, True, False, ["名字"], {"nickname": "名字"}, b"name"):
            with self.subTest(raw=repr(raw)):
                self.assert_api_error(
                    "invalid_nickname",
                    validate_nickname,
                    raw,
                    message="昵称长度必须为 1~24 个字符",
                )

    def test_emoji_and_combining_chars_allowed(self) -> None:
        self.assertEqual(validate_nickname("🎮玩家"), "🎮玩家")
        self.assertEqual(validate_nickname("e\u0301clair"), "e\u0301clair")
        # 按 Unicode 码点计数：4 个 emoji + 20 个汉字 = 24
        mixed = "🎮" * 4 + "字" * 20
        self.assertEqual(len(mixed), 24)
        self.assertEqual(validate_nickname(mixed), mixed)

    def test_returns_stripped_value(self) -> None:
        self.assertEqual(validate_nickname("  新名字 "), "新名字")


class ModeTest(ValidationTestCase):
    def test_valid_modes(self) -> None:
        for raw in ("pve", "pvp"):
            self.assertEqual(validate_mode(raw), raw)

    def test_invalid_modes(self) -> None:
        for raw in ("PVE", "Pve", "pvp ", " pve", "pvc", "", "pvepvp", None, 1, True, b"pve"):
            with self.subTest(raw=repr(raw)):
                self.assert_api_error("invalid_mode", validate_mode, raw)


class ResultTest(ValidationTestCase):
    def test_valid_results(self) -> None:
        for raw in ("win", "loss"):
            self.assertEqual(validate_result(raw), raw)

    def test_invalid_results(self) -> None:
        for raw in ("WIN", "Win", "win ", "winlose", "draw", "", None, 0, False, b"win"):
            with self.subTest(raw=repr(raw)):
                self.assert_api_error("invalid_result", validate_result, raw)


class EventIdTest(ValidationTestCase):
    def test_none_allowed(self) -> None:
        self.assertIsNone(validate_event_id(None))

    def test_valid_lengths_and_charset(self) -> None:
        self.assertEqual(validate_event_id("a" * 8), "a" * 8)
        self.assertEqual(validate_event_id("A1_-" * 16), "A1_-" * 16)  # 恰好 64 位
        self.assertEqual(validate_event_id("abcDEF12"), "abcDEF12")

    def test_invalid_event_ids(self) -> None:
        for raw in (
            "",
            "a" * 7,
            "a" * 65,
            "abc def1",
            "abc!def1",
            "abc.def1",
            "事件id12345678",
            "a" * 8 + "\n",
            123,
            True,
            b"abcdefgh",
        ):
            with self.subTest(raw=repr(raw)):
                self.assert_api_error("invalid_event_id", validate_event_id, raw)


class PlayerIdTest(ValidationTestCase):
    def test_valid_player_id(self) -> None:
        player_id = "p_" + "0123456789abcdef"
        self.assertEqual(len(player_id), 18)
        self.assertEqual(validate_player_id(player_id), player_id)
        self.assertIsNotNone(PLAYER_ID_RE.fullmatch(player_id))

    def test_invalid_player_ids(self) -> None:
        for raw in (
            "0123456789abcdef",             # 缺 p_ 前缀
            "x_0123456789abcdef",           # 前缀错误
            "p-0123456789abcdef",           # 分隔符错误
            "p_" + "0" * 15,                # 太短
            "p_" + "0" * 17,                # 太长
            "p_" + "0123456789ABCDEF",      # 大写十六进制
            "p_" + "g" * 16,                # 非十六进制
            "p_" + "0" * 16 + "\n",         # 尾部换行（$ 不能放过）
            "P_" + "0" * 16,
            "",
            None,
            123,
            True,
            b"p_0123456789abcdef",
        ):
            with self.subTest(raw=repr(raw)):
                self.assert_api_error("invalid_player_id", validate_player_id, raw)


if __name__ == "__main__":
    unittest.main()
