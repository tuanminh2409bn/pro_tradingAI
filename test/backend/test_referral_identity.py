"""Referral identity boundaries without provider calls or monetary accrual."""
import ast
import unittest
from pathlib import Path

from referral_api import canonical_referral_link, new_referral_code


class ReferralIdentityTests(unittest.TestCase):
    def test_codes_are_random_opaque_and_canonical_link_has_only_code(self):
        codes = {new_referral_code() for _ in range(20)}
        self.assertEqual(len(codes), 20)
        for code in codes:
            self.assertRegex(code, r"^[A-Za-z0-9_-]{24}$")
            self.assertEqual(canonical_referral_link(code),
                             "https://protrading-ai-2026.web.app/?ref=" + code)

    def test_invalid_codes_fail_closed(self):
        for code in (None, 123, "", "a" * 23, "a" * 25, "../users/alice", "a" * 23 + " "):
            with self.subTest(code=code), self.assertRaises(ValueError):
                canonical_referral_link(code)

    def test_api_identity_is_from_token_and_provision_does_not_touch_money(self):
        source = Path("server.py").read_text(encoding="utf-8")
        tree = ast.parse(source)
        handler = next(node for node in tree.body if isinstance(node, ast.AsyncFunctionDef)
                       and node.name == "provision_referral_identity")
        body = ast.get_source_segment(source, handler)
        self.assertIn("await verified_user_id(authorization)", body)
        self.assertIn("asyncio.to_thread", body)
        self.assertNotIn("req.userId", body)
        commit = next(node for node in tree.body if isinstance(node, ast.FunctionDef)
                      and node.name == "commit_referral_identity")
        text = ast.get_source_segment(source, commit)
        self.assertIn('"referral_codes"', text)
        self.assertIn("merge=True", text)
        for money in ("totalEarnings", "ledgerStatus", "f1Count", "f2Count", "withdrawal"):
            self.assertNotIn(money, text)
