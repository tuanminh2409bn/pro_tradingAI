"""Community writes bind identity and count retries exactly once."""

from __future__ import annotations

import ast
import asyncio
import time
import unittest
from pathlib import Path
from types import SimpleNamespace

from community_api import community_write_intent
from google.api_core.exceptions import Aborted
from test.backend.test_v21_community_like import HttpError, Ref as BaseRef, Transaction


class Ref(BaseRef):
    @property
    def id(self):
        return self.path[-1]

    def collection(self, name):
        return Ref(self.store, (*self.path, name))

    def document(self, name):
        return Ref(self.store, (*self.path, name))


def load_functions(store):
    source = (Path(__file__).resolve().parents[2] / "server.py").read_text(encoding="utf-8")
    names = {"commit_community_post", "commit_community_comment",
             "community_author", "create_community_post", "create_community_comment", "run_firestore_transaction"}
    nodes = [node for node in ast.parse(source).body
             if isinstance(node, (ast.FunctionDef, ast.AsyncFunctionDef)) and node.name in names]
    for node in nodes:
        node.decorator_list = []

    async def verify(header, claimed):
        if not header:
            raise HttpError(401, "Authentication required")
        if header != "Bearer alice" or claimed not in {"", "alice"}:
            raise HttpError(403, "User mismatch")
        return "alice"

    namespace = {
        "CommunityPostRequest": object, "CommunityCommentRequest": object,
        "Header": lambda default=None: default, "HTTPException": HttpError,
        "verified_user_id": verify, "community_write_intent": community_write_intent,
        "asyncio": asyncio, "db": Ref(store), "time": time, "Aborted": Aborted,
        "auth": SimpleNamespace(get_user=lambda uid: SimpleNamespace(
            disabled=False, display_name="Alice", photo_url=None)),
        "firestore": SimpleNamespace(SERVER_TIMESTAMP="server-time"),
        "cloud_firestore": SimpleNamespace(transactional=lambda fn: fn),
    }
    namespace["db"].transaction = lambda **kwargs: Transaction(store)
    exec(compile(ast.fix_missing_locations(ast.Module(body=nodes, type_ignores=[])),
                 "server.py", "exec"), namespace)
    return namespace


class CommunityWriteTests(unittest.IsolatedAsyncioTestCase):
    async def test_post_retry_uses_one_owner_bound_document_and_cannot_change_content(self):
        store = {}
        functions = load_functions(store)
        request = SimpleNamespace(userId="", requestId="post_request_123456", content="  Market note  ")
        first = await functions["create_community_post"](request, "Bearer alice")
        retry = await functions["create_community_post"](request, "Bearer alice")
        self.assertEqual(first, retry)
        self.assertEqual(len(store), 1)
        post = store[("community", first["postId"])]
        self.assertEqual(post["content"], "Market note")
        self.assertEqual(post["userId"], "alice")
        self.assertFalse(post["tradeVerified"])
        request.content = "Changed note"
        with self.assertRaises(HttpError) as error:
            await functions["create_community_post"](request, "Bearer alice")
        self.assertEqual(error.exception.status_code, 409)
        self.assertEqual(post["content"], "Market note")

    async def test_comment_retry_creates_one_comment_and_updates_counter_once(self):
        store = {("community", "post123"): {"comments": 0, "userId": "bob"}}
        functions = load_functions(store)
        request = SimpleNamespace(userId="alice", requestId="comment_request_123456",
                                  content="A public reply", postId="post123")
        first = await functions["create_community_comment"](request, "Bearer alice")
        retry = await functions["create_community_comment"](request, "Bearer alice")
        self.assertEqual(first["commentId"], retry["commentId"])
        self.assertEqual(store[("community", "post123")]["comments"], 1)
        comment = store[("community", "post123", "comments", first["commentId"])]
        self.assertEqual(comment["userId"], "alice")
        request.content = "Different reply"
        with self.assertRaises(HttpError) as error:
            await functions["create_community_comment"](request, "Bearer alice")
        self.assertEqual(error.exception.status_code, 409)
        self.assertEqual(store[("community", "post123")]["comments"], 1)

    async def test_invalid_identity_payload_parent_and_counter_never_write(self):
        store = {("community", "post123"): {"comments": True}}
        functions = load_functions(store)
        for overrides, header, code in (
            ({}, None, 401), ({"userId": "bob"}, "Bearer alice", 403),
            ({"requestId": "../other"}, "Bearer alice", 422),
            ({"postId": "../other"}, "Bearer alice", 422),
            ({"postId": "missing"}, "Bearer alice", 404),
            ({"content": " "}, "Bearer alice", 422),
            ({"content": "x" * 1001}, "Bearer alice", 422),
            ({}, "Bearer alice", 409),
        ):
            request = SimpleNamespace(userId="", requestId="comment_request_123456",
                                      content="Reply", postId="post123")
            request.__dict__.update(overrides)
            with self.subTest(code=code, overrides=list(overrides)):
                with self.assertRaises(HttpError) as error:
                    await functions["create_community_comment"](request, header)
                self.assertEqual(error.exception.status_code, code)
                self.assertEqual(len(store), 1)

    async def test_author_never_falls_back_to_private_email_and_disabled_cannot_post(self):
        store = {}
        functions = load_functions(store)
        record = SimpleNamespace(disabled=False, display_name="", photo_url=None,
                                 email="private@example.test")
        functions["auth"].get_user = lambda uid: record
        self.assertEqual(await functions["community_author"]("alice"),
                         {"userName": "Community member", "avatarUrl": ""})
        record.disabled = True
        with self.assertRaises(HttpError) as error:
            await functions["community_author"]("alice")
        self.assertEqual(error.exception.status_code, 403)

    def test_operation_ids_are_scoped_to_identity_and_post(self):
        first = community_write_intent("alice", "operation_12345678", "note", "post123")
        other_user = community_write_intent("bob", "operation_12345678", "note", "post123")
        other_post = community_write_intent("alice", "operation_12345678", "note", "post456")
        self.assertEqual(len(first[0]), 64)
        self.assertNotEqual(first[0], other_user[0])
        self.assertNotEqual(first[0], other_post[0])


if __name__ == "__main__":
    unittest.main()
