"""Real Firestore transaction semantics for replay-safe likes, emulator only."""

from __future__ import annotations

import ast
import os
import re
import unittest
import uuid
from pathlib import Path
from types import SimpleNamespace


EMULATOR = os.environ.get("FIRESTORE_EMULATOR_HOST", "")


@unittest.skipUnless(
    re.fullmatch(r"(?:127\.0\.0\.1|localhost):[0-9]+", EMULATOR),
    "requires a loopback Firestore Emulator",
)
class CommunityLikeEmulatorTests(unittest.TestCase):
    def test_transaction_counts_two_users_once_each(self):
        from fastapi import HTTPException
        from google.auth.credentials import AnonymousCredentials
        from google.cloud import firestore as cloud_firestore

        source = (Path(__file__).resolve().parents[2] / "server.py").read_text(encoding="utf-8")
        node = next(
            node for node in ast.parse(source).body
            if isinstance(node, ast.FunctionDef)
            and node.name == "commit_community_like"
        )
        namespace = {
            "cloud_firestore": cloud_firestore,
            "firestore": SimpleNamespace(SERVER_TIMESTAMP=cloud_firestore.SERVER_TIMESTAMP),
            "HTTPException": HTTPException,
        }
        exec(compile(ast.fix_missing_locations(ast.Module(body=[node], type_ignores=[])),
                     "server.py", "exec"), namespace)
        commit_like = namespace["commit_community_like"]

        client = cloud_firestore.Client(
            project="protrading-ai-2026", credentials=AnonymousCredentials()
        )
        post_ref = client.collection("community").document(f"like-{uuid.uuid4().hex}")
        post_ref.set({"userId": "owner", "content": "Market note", "likes": 0})
        try:
            first = commit_like(client.transaction(), post_ref, "alice")
            replay = commit_like(client.transaction(), post_ref, "alice")
            second = commit_like(client.transaction(), post_ref, "bob")
            self.assertEqual((first["likes"], replay["likes"], second["likes"]), (1, 1, 2))
            self.assertTrue(replay["alreadyLiked"])
            self.assertEqual(post_ref.get().to_dict()["likes"], 2)
        finally:
            post_ref.collection("likes").document("alice").delete()
            post_ref.collection("likes").document("bob").delete()
            post_ref.delete()


if __name__ == "__main__":
    unittest.main()
