"""Real transactional replay/concurrency checks, restricted to local Emulator."""

import ast
import os
import re
import time
import unittest
import uuid
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path
from types import SimpleNamespace

from community_api import community_write_intent
from google.api_core.exceptions import Aborted


@unittest.skipUnless(re.fullmatch(r"(?:localhost|127\.0\.0\.1):[0-9]+",
                                os.environ.get("FIRESTORE_EMULATOR_HOST", "")),
                     "requires a loopback Firestore Emulator")
class CommunityWriteEmulatorTests(unittest.TestCase):
    def test_parallel_post_and_comment_replays_create_one_each(self):
        from fastapi import HTTPException
        from google.auth.credentials import AnonymousCredentials
        from google.cloud import firestore

        source = (Path(__file__).resolve().parents[2] / "server.py").read_text(encoding="utf-8")
        nodes = [node for node in ast.parse(source).body if isinstance(node, ast.FunctionDef)
                 and node.name in {"commit_community_post", "commit_community_comment", "run_firestore_transaction"}]
        namespace = {"cloud_firestore": firestore, "HTTPException": HTTPException,
                     "firestore": SimpleNamespace(SERVER_TIMESTAMP=firestore.SERVER_TIMESTAMP),
                     "Aborted": Aborted, "time": time}
        exec(compile(ast.fix_missing_locations(ast.Module(body=nodes, type_ignores=[])),
                     "server.py", "exec"), namespace)
        client = firestore.Client(project="protrading-ai-2026", credentials=AnonymousCredentials())
        namespace["db"] = client
        operation = uuid.uuid4().hex
        post_id, content = community_write_intent("alice", operation, "Emulator market note")
        post_ref = client.collection("community").document(post_id)
        author = {"userName": "QA Emulator", "avatarUrl": ""}
        try:
            with ThreadPoolExecutor(max_workers=6) as pool:
                results = list(pool.map(lambda _: namespace["run_firestore_transaction"](
                    namespace["commit_community_post"], post_ref, "alice", content, author), range(20)))
            self.assertEqual({result["postId"] for result in results}, {post_id})
            comment_id, reply = community_write_intent("bob", operation, "Emulator reply", post_id)
            comment_ref = post_ref.collection("comments").document(comment_id)
            with ThreadPoolExecutor(max_workers=6) as pool:
                results = list(pool.map(lambda _: namespace["run_firestore_transaction"](
                    namespace["commit_community_comment"], post_ref, comment_ref, "bob", reply, author), range(20)))
            self.assertEqual({result["commentId"] for result in results}, {comment_id})
            self.assertEqual(post_ref.get().to_dict()["comments"], 1)
            self.assertEqual(len(list(post_ref.collection("comments").stream())), 1)
            self.assertEqual(comment_ref.get().to_dict()["userId"], "bob")
            with self.assertRaises(HTTPException) as error:
                namespace["run_firestore_transaction"](
                    namespace["commit_community_comment"], post_ref, comment_ref, "bob", "Changed reply", author)
            self.assertEqual(error.exception.status_code, 409)
            self.assertEqual(post_ref.get().to_dict()["comments"], 1)
            post_ref.delete()
            with self.assertRaises(HTTPException) as error:
                namespace["run_firestore_transaction"](
                    namespace["commit_community_comment"], post_ref, comment_ref, "bob", reply, author)
            self.assertEqual(error.exception.status_code, 404)
        finally:
            for doc in post_ref.collection("comments").stream():
                doc.reference.delete()
            post_ref.delete()
            client.close()
