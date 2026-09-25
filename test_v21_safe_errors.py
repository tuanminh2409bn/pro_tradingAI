"""Static regressions for secrets and internal errors in production log/response paths."""

from __future__ import annotations

from pathlib import Path
import re
import unittest


SERVER_SOURCE = (Path(__file__).parent / "server.py").read_text()


class SafeErrorTests(unittest.TestCase):
    def test_server_does_not_interpolate_caught_exceptions_into_logs(self):
        self.assertIsNone(
            re.search(r"print\([^\n]*(?:\{e\d*\}|str\(e\))", SERVER_SOURCE)
        )

    def test_server_does_not_return_caught_exception_strings(self):
        self.assertNotIn('"message": str(e)', SERVER_SOURCE)

    def test_fcm_token_values_are_never_logged(self):
        self.assertNotIn("Failed token (will delete)", SERVER_SOURCE)
        self.assertNotIn("resp.exception", SERVER_SOURCE)

    def test_private_identity_and_user_content_are_not_logged(self):
        forbidden = (
            "User {user_id}",
            "user={user_id}",
            "req.message[:50]",
            "req.userId}",
            "Account Created: {account_id}",
        )
        for value in forbidden:
            with self.subTest(value=value):
                self.assertNotIn(value, SERVER_SOURCE, msg=f"unsafe log fragment: {value}")


if __name__ == "__main__":
    unittest.main()
