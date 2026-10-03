"""Referral identity boundaries without provider calls or monetary accrual."""
import ast
import asyncio
import time
import unittest
from pathlib import Path
from types import SimpleNamespace

from pydantic import BaseModel, StrictStr, ValidationError
from google.api_core.exceptions import Aborted
from test.backend.test_v21_community_like import HttpError, Ref, Transaction

from referral_api import canonical_referral_link, new_referral_code, eligible_registration


def load_registration(store, records):
    source = Path("server.py").read_text(encoding="utf-8")
    names = {"ReferralRegistrationRequest", "register_referral", "commit_referral_registration", "run_firestore_transaction"}
    nodes = [node for node in ast.parse(source).body if getattr(node, "name", None) in names]
    for node in nodes:
        node.decorator_list = []

    async def verify(header):
        if header != "Bearer alice":
            raise HttpError(401, "Authentication required")
        return "alice"

    namespace = {
        "BaseModel": BaseModel, "StrictStr": StrictStr,
        "Header": lambda default=None: default, "HTTPException": HttpError,
        "verified_user_id": verify, "canonical_referral_link": canonical_referral_link,
        "eligible_registration": eligible_registration, "asyncio": asyncio,
        "time": SimpleNamespace(time=lambda: 200_000, sleep=time.sleep), "db": Ref(store), "Aborted": Aborted,
        "auth": SimpleNamespace(get_user=lambda uid: records[uid]),
        "firestore": SimpleNamespace(SERVER_TIMESTAMP="server-time"),
        "cloud_firestore": SimpleNamespace(transactional=lambda function: function),
    }
    namespace["db"].transaction = lambda **kwargs: Transaction(store)
    exec(compile(ast.fix_missing_locations(ast.Module(body=nodes, type_ignores=[])),
                 "server.py", "exec"), namespace)
    return namespace


class ReferralRegistrationApiTests(unittest.IsolatedAsyncioTestCase):
    def setUp(self):
        self.code = "a" * 24
        self.store = {
            ("referral_codes", self.code): {"userId": "inviter"},
            ("referrals", "inviter"): {"referralCode": self.code, "registeredInviteCount": 0},
        }
        self.records = {uid: SimpleNamespace(disabled=False, user_metadata=SimpleNamespace(
            creation_timestamp=created)) for uid, created in (("alice", 199_999_000), ("inviter", 199_998_000))}
        self.functions = load_registration(self.store, self.records)
        self.request = self.functions["ReferralRegistrationRequest"](code=self.code)

    async def test_token_registration_is_once_only_and_restore_survives_the_window(self):
        handler = self.functions["register_referral"]
        self.assertEqual(await handler(self.request, "Bearer alice"), {"status": "recorded"})
        self.records["alice"].user_metadata.creation_timestamp = 1
        self.assertEqual(await handler(self.request, "Bearer alice"), {"status": "restored"})
        self.assertEqual(self.store[("referrals", "inviter")]["registeredInviteCount"], 1)
        self.assertEqual(self.store[("users", "alice", "meta", "referral_attribution")],
                         {"code": self.code, "createdAt": "server-time"})

    async def test_old_future_and_earlier_than_inviter_accounts_do_not_accrue(self):
        for created in (1, 200_000_001, 199_998_000):
            self.records["alice"].user_metadata.creation_timestamp = created
            self.assertEqual(await self.functions["register_referral"](self.request, "Bearer alice"),
                             {"status": "not_eligible"})
        self.assertEqual(self.store[("referrals", "inviter")]["registeredInviteCount"], 0)
        self.assertEqual(len(self.store), 2)

    async def test_disabled_missing_user_and_corrupt_count_fail_closed(self):
        self.records["inviter"].disabled = True
        with self.assertRaises(HttpError) as error:
            await self.functions["register_referral"](self.request, "Bearer alice")
        self.assertEqual(error.exception.status_code, 403)
        self.records["inviter"].disabled = False
        self.store[("referrals", "inviter")]["registeredInviteCount"] = True
        with self.assertRaises(HttpError) as error:
            await self.functions["register_referral"](self.request, "Bearer alice")
        self.assertEqual(error.exception.status_code, 503)
        del self.records["inviter"]
        with self.assertRaises(HttpError) as error:
            await self.functions["register_referral"](self.request, "Bearer alice")
        self.assertEqual(error.exception.status_code, 503)
        self.assertEqual(len(self.store), 2)

    async def test_anonymous_self_and_malformed_payload_never_write(self):
        with self.assertRaises(HttpError) as error:
            await self.functions["register_referral"](self.request, None)
        self.assertEqual(error.exception.status_code, 401)
        self.store[("referral_codes", self.code)]["userId"] = "alice"
        with self.assertRaises(HttpError) as error:
            await self.functions["register_referral"](self.request, "Bearer alice")
        self.assertEqual(error.exception.status_code, 403)
        model = self.functions["ReferralRegistrationRequest"]
        for payload in ({"code": self.code, "userId": "bob"}, {"code": 123}):
            with self.assertRaises(ValidationError):
                model(**payload)
        self.assertEqual(len(self.store), 2)

    def test_read_contention_retries_fresh_transactions_but_never_masks_other_errors(self):
        transactions, sleeps = [], []
        self.functions["time"] = SimpleNamespace(sleep=sleeps.append)
        run = self.functions["run_firestore_transaction"]

        def succeed_after_abort(transaction):
            transactions.append(transaction)
            if len(transactions) == 1:
                raise Aborted("read contention")
            return "committed"

        self.assertEqual(run(succeed_after_abort), "committed")
        self.assertIsNot(transactions[0], transactions[1])
        self.assertEqual(sleeps, [0.2])
        transactions.clear()
        sleeps.clear()

        def exhausted(transaction):
            transactions.append(transaction)
            raise Aborted("read contention")

        with self.assertRaises(Aborted):
            run(exhausted)
        self.assertEqual(len(transactions), 3)
        self.assertEqual(sleeps, [0.2, 0.4])
        sleeps.clear()
        def invalid_counter(transaction):
            raise ValueError("invalid counter")
        with self.assertRaisesRegex(ValueError, "invalid counter"):
            run(invalid_counter)
        self.assertEqual(sleeps, [])


class ReferralIdentityTests(unittest.TestCase):
    def test_registration_is_newer_than_inviter_and_within_one_day(self):
        now = 200_000_000
        self.assertTrue(eligible_registration(now - 1000, now - 2000, now))
        self.assertTrue(eligible_registration(now - 86_400_000, now - 86_401_000, now))
        for user, inviter in ((now - 86_400_001, 1), (now + 1, now - 1),
                              (now - 1000, now - 999), (now - 1000, now - 1000)):
            self.assertFalse(eligible_registration(user, inviter, now))
        for invalid in (None, True, -1, 1.5, "100"):
            with self.assertRaises(ValueError):
                eligible_registration(invalid, 1, now)

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
