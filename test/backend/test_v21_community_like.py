"""Owner-bound, replay-safe Community likes at the Firestore transaction boundary."""

from __future__ import annotations

import ast
import asyncio
import re
import unittest
from pathlib import Path
from types import SimpleNamespace


class HttpError(Exception):
    def __init__(self, status_code, detail):
        self.status_code = status_code
        self.detail = detail


class Snapshot:
    def __init__(self, data):
        self.exists = data is not None
        self._data = data

    def to_dict(self):
        return self._data


class Ref:
    def __init__(self, store, path=()):
        self.store = store
        self.path = path

    def collection(self, name):
        return Ref(self.store, (*self.path, name))

    def document(self, name):
        return Ref(self.store, (*self.path, name))

    def get(self, transaction=None):
        return Snapshot(self.store.get(self.path))


class Transaction:
    def __init__(self, store):
        self.store = store

    def create(self, ref, value):
        if ref.path in self.store:
            raise AssertionError("marker created twice")
        self.store[ref.path] = dict(value)

    def update(self, ref, value):
        self.store[ref.path].update(value)


def load_functions(store):
    source = (Path(__file__).resolve().parents[2] / "server.py").read_text(encoding="utf-8")
    nodes = [
        node for node in ast.parse(source).body
        if isinstance(node, (ast.FunctionDef, ast.AsyncFunctionDef))
        and node.name in {"commit_community_like", "like_community_post"}
    ]
    for node in nodes:
        node.decorator_list = []

    async def verify(header, claimed):
        if not header:
            raise HttpError(401, "Authentication required")
        if header != "Bearer alice" or claimed not in {"", "alice"}:
            raise HttpError(403, "User mismatch")
        return "alice"

    namespace = {
        "CommunityLikeRequest": object,
        "Header": lambda default=None: default,
        "HTTPException": HttpError,
        "verified_user_id": verify,
        "re": re,
        "asyncio": asyncio,
        "db": Ref(store),
        "firestore": SimpleNamespace(SERVER_TIMESTAMP="server-time"),
        "cloud_firestore": SimpleNamespace(transactional=lambda fn: fn),
    }
    namespace["db"].transaction = lambda: Transaction(store)
    exec(compile(ast.fix_missing_locations(ast.Module(body=nodes, type_ignores=[])),
                 "server.py", "exec"), namespace)
    return namespace


class CommunityLikeTests(unittest.IsolatedAsyncioTestCase):
    async def test_single_like_and_replay_keep_one_marker_and_count(self):
        store = {("community", "post123"): {"likes": 0, "userId": "bob"}}
        functions = load_functions(store)
        request = SimpleNamespace(postId="post123", userId="alice")
        first = await functions["like_community_post"](request, "Bearer alice")
        second = await functions["like_community_post"](request, "Bearer alice")
        self.assertEqual(first, {"liked": True, "alreadyLiked": False, "likes": 1})
        self.assertEqual(second, {"liked": True, "alreadyLiked": True, "likes": 1})
        self.assertEqual(store[("community", "post123")]["likes"], 1)
        self.assertEqual(store[("community", "post123", "likes", "alice")]["userId"], "alice")
        other = functions["commit_community_like"](
            Transaction(store), Ref(store, ("community", "post123")), "bob"
        )
        self.assertEqual(other["likes"], 2)
        self.assertEqual(store[("community", "post123")]["likes"], 2)

    async def test_cross_user_and_invalid_post_cannot_write(self):
        store = {("community", "post123"): {"likes": 0}}
        functions = load_functions(store)
        for request, header, code in (
            (SimpleNamespace(postId="post123", userId="alice"), None, 401),
            (SimpleNamespace(postId="post123", userId="bob"), "Bearer alice", 403),
            (SimpleNamespace(postId="../other", userId="alice"), "Bearer alice", 422),
            (SimpleNamespace(postId="missing", userId="alice"), "Bearer alice", 404),
        ):
            with self.subTest(post=request.postId):
                with self.assertRaises(HttpError) as error:
                    await functions["like_community_post"](request, header)
                self.assertEqual(error.exception.status_code, code)
        self.assertEqual(store[("community", "post123")]["likes"], 0)


if __name__ == "__main__":
    unittest.main()
