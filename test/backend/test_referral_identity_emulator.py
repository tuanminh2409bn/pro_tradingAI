"""Real unique allocation and UID replay, loopback Emulator only."""
import ast
import os
import re
import unittest
import uuid
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path
from types import SimpleNamespace

from referral_api import canonical_referral_link, new_referral_code, ReferralCodeCollision


@unittest.skipUnless(re.fullmatch(r"(?:localhost|127\.0\.0\.1):[0-9]+",
                                os.environ.get("FIRESTORE_EMULATOR_HOST", "")),
                     "requires a loopback Firestore Emulator")
class ReferralIdentityEmulatorTests(unittest.TestCase):
    def test_concurrent_provision_restores_one_code_preserves_stats_and_registry(self):
        from fastapi import HTTPException
        from google.auth.credentials import AnonymousCredentials
        from google.cloud import firestore
        client = firestore.Client(project="protrading-ai-2026", credentials=AnonymousCredentials())
        source = Path("server.py").read_text(encoding="utf-8")
        node = next(node for node in ast.parse(source).body if isinstance(node, ast.FunctionDef)
                    and node.name == "commit_referral_identity")
        namespace = {"cloud_firestore": firestore, "HTTPException": HTTPException,
                     "firestore": SimpleNamespace(SERVER_TIMESTAMP=firestore.SERVER_TIMESTAMP),
                     "db": client, "canonical_referral_link": canonical_referral_link,
                     "ReferralCodeCollision": ReferralCodeCollision}
        exec(compile(ast.fix_missing_locations(ast.Module(body=[node], type_ignores=[])),
                     "server.py", "exec"), namespace)
        uid = "referral-local-" + uuid.uuid4().hex
        owner = client.collection("referrals").document(uid)
        owner.set({"totalEarnings": 12.5, "unrelatedField": "preserve"})
        allocated = None
        collision = new_referral_code()
        client.collection("referral_codes").document(collision).set({"userId": "other"})
        try:
            with ThreadPoolExecutor(max_workers=6) as pool:
                results = list(pool.map(lambda _: namespace["commit_referral_identity"](
                    client.transaction(max_attempts=20), uid, new_referral_code()), range(20)))
            codes = {result["code"] for result in results}
            self.assertEqual(len(codes), 1)
            allocated = codes.pop()
            self.assertEqual(owner.get().to_dict()["referralCode"], allocated)
            self.assertEqual(owner.get().to_dict()["totalEarnings"], 12.5)
            self.assertEqual(owner.get().to_dict()["unrelatedField"], "preserve")
            self.assertEqual(client.collection("referral_codes").document(allocated).get().to_dict()["userId"], uid)
            again = namespace["commit_referral_identity"](client.transaction(), uid, collision)
            self.assertEqual(again["code"], allocated)
            with self.assertRaises(ReferralCodeCollision):
                namespace["commit_referral_identity"](client.transaction(), uid + "-new", collision)
            self.assertFalse(client.collection("referrals").document(uid + "-new").get().exists)
        finally:
            owner.delete()
            for code in (allocated, collision):
                if code:
                    client.collection("referral_codes").document(code).delete()
            client.close()
