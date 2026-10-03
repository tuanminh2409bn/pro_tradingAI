"""Regression tests for Firebase identity on private Web API handlers."""

from __future__ import annotations

import ast
import asyncio
import re
import unittest
from pathlib import Path
from types import SimpleNamespace

from market_history import symbol_bound_chat_context


class HttpError(Exception):
    def __init__(self, status_code, detail):
        self.status_code = status_code
        self.detail = detail


class Request:
    def __init__(self, **values):
        self.__dict__.update(values)


def load_handlers(verified_user_id):
    source = (Path(__file__).resolve().parents[2] / "server.py").read_text(encoding="utf-8")
    wanted = {"link_account", "ai_chat"}
    nodes = [
        node
        for node in ast.parse(source).body
        if isinstance(node, ast.AsyncFunctionDef) and node.name in wanted
    ]
    for node in nodes:
        node.decorator_list = []

    metric = SimpleNamespace(finish=lambda **kwargs: None)
    namespace = {
        "LinkAccountRequest": Request,
        "AIChatRequest": Request,
        "Header": lambda default=None, alias=None: default,
        "verified_user_id": verified_user_id,
        "operation_recorder": SimpleNamespace(start=lambda operation: metric),
        "Operation": SimpleNamespace(AI_CHAT="ai_chat"),
        "OperationOutcome": SimpleNamespace(FALLBACK="fallback", SUCCESS="success", FAILURE="failure"),
        "FailureCode": SimpleNamespace(PROVIDER_UNAVAILABLE="provider_unavailable", INTERNAL_ERROR="internal_error"),
        "BackendOperation": SimpleNamespace(ANALYSIS="analysis"),
        "DEEPSEEK_API_KEY": "",
        "DEEPSEEK_MODEL": "deepseek-flash",
        "LOCAL_QA_MODE": False,
        "asyncio": asyncio,
        "re": re,
        "HTTPException": HttpError,
        "symbol_bound_chat_context": symbol_bound_chat_context,
        "normalize_symbol": lambda symbol: symbol,
    }
    exec(
        compile(
            ast.fix_missing_locations(ast.Module(body=nodes, type_ignores=[])),
            "server.py",
            "exec",
        ),
        namespace,
    )
    return namespace


class PrivateApiAuthTests(unittest.IsolatedAsyncioTestCase):
    async def test_local_qa_never_calls_broker_provider(self):
        async def allow(header, claimed, *, required_role=None):
            return claimed

        handlers = load_handlers(allow)
        handlers["LOCAL_QA_MODE"] = True
        request = Request(
            userId="alice", platform="mt5", server="broker.example",
            login="1001", password="local-only",
        )
        with self.assertRaises(HttpError) as error:
            await handlers["link_account"](request, "Bearer alice")
        self.assertEqual(error.exception.status_code, 503)

    async def test_missing_token_stops_broker_link_before_provider_or_storage(self):
        calls = []

        async def deny(header, claimed, *, required_role=None):
            calls.append((header, claimed, required_role))
            raise HttpError(401, "Authentication required")

        handlers = load_handlers(deny)
        request = Request(
            userId="alice",
            platform="mt5",
            server="broker.example",
            login="1001",
            password="secret",
        )
        with self.assertRaises(HttpError) as error:
            await handlers["link_account"](request, None)
        self.assertEqual(error.exception.status_code, 401)
        self.assertEqual(calls, [(None, "alice", "verified_partner")])

    async def test_cross_user_chat_claim_is_rejected_before_ai_or_market_access(self):
        calls = []

        async def deny(header, claimed):
            calls.append((header, claimed))
            raise HttpError(403, "User identity mismatch")

        handlers = load_handlers(deny)
        request = Request(
            userId="bob",
            message="Analyze gold",
            symbol="XAUUSD",
            timeframe="5",
        )
        with self.assertRaises(HttpError) as error:
            await handlers["ai_chat"](request, "Bearer alice")
        self.assertEqual(error.exception.status_code, 403)
        self.assertEqual(calls, [("Bearer alice", "bob")])

    async def test_authenticated_chat_keeps_provider_outage_fallback(self):
        async def allow(header, claimed):
            self.assertEqual(header, "Bearer alice")
            self.assertEqual(claimed, "alice")
            return "alice"

        handlers = load_handlers(allow)
        handlers["require_backend_operation"] = lambda operation: asyncio.sleep(0)
        request = Request(
            userId="alice",
            message="Analyze gold",
            symbol="XAUUSD",
            timeframe="5",
        )
        result = await handlers["ai_chat"](request, "Bearer alice")
        self.assertEqual(result["status"], "error")
        self.assertTrue(result["fallback"])

    async def test_chat_never_passes_foreign_chart_price_to_model(self):
        async def allow(header, claimed):
            return "alice"

        handlers = load_handlers(allow)
        handlers["DEEPSEEK_API_KEY"] = "test-key"
        handlers["require_backend_operation"] = lambda operation: asyncio.sleep(0)
        handlers["get_chat_master_prompt"] = lambda: asyncio.sleep(0, result="Master")
        handlers["streamer"] = SimpleNamespace(
            chart_symbol_clean=lambda: "XAUUSD",
            interval="5", last_price=3050.5,
        )
        prompts = []

        def create(**kwargs):
            self.assertEqual(kwargs['model'], 'deepseek-flash')
            self.assertEqual(kwargs['temperature'], 0.0)
            prompts.append(kwargs["messages"][0]["content"])
            return SimpleNamespace(choices=[SimpleNamespace(message=SimpleNamespace(content="General answer"))])

        handlers["ai_client"] = SimpleNamespace(
            chat=SimpleNamespace(completions=SimpleNamespace(create=create))
        )
        request = Request(userId="alice", message="Discuss EURUSD",
                          symbol="EURUSD", timeframe="5")
        result = await handlers["ai_chat"](request, "Bearer alice")
        self.assertEqual(result["status"], "success")
        self.assertEqual(len(prompts), 1)
        self.assertIn("Live market context unavailable", prompts[0])
        self.assertNotIn("3050.5", prompts[0])

    async def test_broker_link_writes_only_under_verified_owner(self):
        writes = {}
        case = self

        async def allow(header, claimed, *, required_role=None):
            self.assertEqual(
                (header, claimed, required_role),
                ("Bearer alice", "alice", "verified_partner"),
            )
            return "alice"

        class AccountApi:
            async def create_account(self, payload):
                self_payload = dict(payload)
                case.assertNotIn("userId", self_payload)
                return {"id": "broker-1"}

        class Ref:
            def __init__(self, path=()):
                self.path = path

            def collection(self, name):
                return Ref((*self.path, name))

            def document(self, name):
                return Ref((*self.path, name))

            def set(self, data):
                writes[self.path] = dict(data)

        handlers = load_handlers(allow)
        handlers.update(
            MetaApi=lambda token: SimpleNamespace(metatrader_account_api=AccountApi()),
            META_API_TOKEN="provider-token",
            db=Ref(),
            firestore=SimpleNamespace(SERVER_TIMESTAMP="server-time"),
        )
        request = Request(
            userId="alice",
            platform="mt5",
            server="broker.example",
            login="1001",
            password="secret",
        )
        result = await handlers["link_account"](request, "Bearer alice")
        self.assertEqual(result, {"status": "success", "accountId": "broker-1"})
        path = ("users", "alice", "broker_accounts", "broker-1")
        self.assertIn(path, writes)
        self.assertNotIn("password", writes[path])


if __name__ == "__main__":
    unittest.main()
