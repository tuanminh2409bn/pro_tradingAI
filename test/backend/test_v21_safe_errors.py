"""Static regressions for secrets and internal errors in production log/response paths."""

from __future__ import annotations

from pathlib import Path
import ast
import contextlib
import io
import re
import unittest


SERVER_SOURCE = (Path(__file__).resolve().parents[2] / "server.py").read_text()


class SafeErrorTests(unittest.TestCase):
    def test_server_does_not_interpolate_caught_exceptions_into_logs(self):
        self.assertIsNone(
            re.search(r"print\([^\n]*(?:\{e\d*\}|str\(e\))", SERVER_SOURCE)
        )

    def test_server_does_not_return_caught_exception_strings(self):
        self.assertNotIn('"message": str(e)', SERVER_SOURCE)

    def test_fcm_token_values_are_never_logged(self):
        self.assertNotIn("Failed token (will delete)", SERVER_SOURCE)
        # Inspect output calls: reading the exception type for retirement is safe;
        # serializing the exception into a log is not.
        for node in ast.walk(ast.parse(SERVER_SOURCE)):
            if isinstance(node, ast.Call) and isinstance(node.func, ast.Name) and node.func.id == 'print':
                self.assertFalse(any(isinstance(value, ast.Attribute) and value.attr == 'exception' for value in ast.walk(node)))
                self.assertNotIn('failed_token', ast.unparse(node))
        from test_v21_signal_push_owner import load_sender
        marker = 'fixture-private-fcm-token'
        for failure in ('transient', 'invalid'):
            output = io.StringIO()
            with contextlib.redirect_stdout(output):
                send = load_sender({'alice': {'pushNotificationsEnabled': True}}, [], failure=failure, error_message=marker)
                send('alice', 'XAUUSD', 'BUY', 2500, 2490, [2520], 80)
            self.assertNotIn(marker, output.getvalue())
            self.assertNotIn('alice-token', output.getvalue())

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
