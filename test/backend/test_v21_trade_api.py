"""Exercise the real trade handler body with an in-memory Firestore boundary."""

from __future__ import annotations

import ast
import asyncio
import hashlib
import json
import re
import unittest
from datetime import datetime, timezone
from pathlib import Path
from types import SimpleNamespace

from test.backend.test_v21_trade_gate import hard_signal, intent
from trade_gate import TradeDenied, trade_document_id, validate_trade_intent
from cutoff_state import cutoff_active


class HttpError(Exception):
    def __init__(self, status_code, detail):
        self.status_code = status_code
        self.detail = detail


class FakeConflict(Exception):
    pass


class Snapshot:
    def __init__(self, data):
        self.exists = data is not None
        self._data = data

    def to_dict(self):
        return self._data


class FakeRef:
    def __init__(self, store, path):
        self.store = store
        self.path = path

    def collection(self, name):
        return FakeRef(self.store, (*self.path, name))

    def document(self, name):
        return FakeRef(self.store, (*self.path, name))

    def get(self, transaction=None):
        return Snapshot(self.store.get(self.path))

    def create(self, data):
        if self.path in self.store:
            raise FakeConflict()
        self.store[self.path] = data

    def transaction(self):
        return FakeTransaction()


class FakeTransaction:
    def create(self, ref, data):
        ref.create(data)


class Request:
    def __init__(self, data):
        self.data = data
        for key, value in data.items():
            setattr(self, key, value)

    def model_dump(self, exclude=None):
        return {key: value for key, value in self.data.items() if key not in (exclude or ())}


def load_handler(store, *, cutoff=False):
    source = (Path(__file__).resolve().parents[2] / "server.py").read_text(encoding="utf-8")
    nodes = [
        node for node in ast.parse(source).body
        if isinstance(node, (ast.FunctionDef, ast.AsyncFunctionDef))
        and node.name in {"create_current_paper_trade", "execute_trade"}
    ]
    for node in nodes:
        node.decorator_list = []
    metric = SimpleNamespace(finish=lambda **kwargs: None)

    async def verified_user_id(header, claimed):
        if header != "Bearer valid" or claimed != "alice":
            raise HttpError(401, "Authentication required")
        return "alice"

    async def require_backend_operation(operation):
        return None

    async def require_daily_loss_capacity(user_id):
        if cutoff:
            raise HttpError(403, "Daily loss cutoff active")

    namespace = {
        "TradeRequest": Request,
        "Header": lambda default=None, alias=None: default,
        "HTTPException": HttpError,
        "Conflict": FakeConflict,
        "asyncio": asyncio,
        "hashlib": hashlib,
        "json": json,
        "re": re,
        "time": SimpleNamespace(time=lambda: 1_800_000_300),
        "datetime": SimpleNamespace(now=lambda tz: datetime.fromtimestamp(1_800_000_300, timezone.utc)),
        "timezone": timezone,
        "db": FakeRef(store, ()),
        "firestore": SimpleNamespace(SERVER_TIMESTAMP="server-time"),
        "cloud_firestore": SimpleNamespace(transactional=lambda fn: fn),
        "operation_recorder": SimpleNamespace(start=lambda op: metric),
        "Operation": SimpleNamespace(PAPER_EXECUTION="paper"),
        "OperationOutcome": SimpleNamespace(SUCCESS="success", FAILURE="failure"),
        "FailureCode": SimpleNamespace(INTERNAL_ERROR="internal"),
        "BackendOperation": SimpleNamespace(EXECUTION="execution"),
        "verified_user_id": verified_user_id,
        "require_backend_operation": require_backend_operation,
        "require_daily_loss_capacity": require_daily_loss_capacity,
        "TradeDenied": TradeDenied,
        "trade_document_id": trade_document_id,
        "validate_trade_intent": validate_trade_intent,
        "cutoff_active": cutoff_active,
        "_cutoff_ref": lambda user_id: FakeRef(store, ("users", user_id, "risk_state", "daily_cutoff")),
    }
    exec(compile(ast.fix_missing_locations(ast.Module(body=nodes, type_ignores=[])), "server.py", "exec"), namespace)
    return namespace["execute_trade"]


class TradeApiTests(unittest.IsolatedAsyncioTestCase):
    async def test_transaction_rejects_active_persisted_cutoff_even_after_precheck(self):
        store = {
            ("signals", "signal-1"): hard_signal(),
            ("users", "alice", "risk_state", "daily_cutoff"): {
                "active": True, "sessionDate": "2026-09-24",
            },
        }
        handler = load_handler(store)
        request = Request({**intent(), "userId": "alice", "signalId": "signal-1"})
        with self.assertRaises(HttpError) as error:
            await handler(request, "Bearer valid", "intent-000000001")
        self.assertEqual(error.exception.status_code, 403)
        self.assertFalse(any(path[:3] == ("users", "alice", "trades") for path in store))

    async def test_direct_api_call_cannot_bypass_daily_loss_cutoff(self):
        store = {("signals", "signal-1"): hard_signal()}
        handler = load_handler(store, cutoff=True)
        request = Request({**intent(), "userId": "alice", "signalId": "signal-1"})
        with self.assertRaises(HttpError) as error:
            await handler(request, "Bearer valid", "intent-000000001")
        self.assertEqual(error.exception.status_code, 403)
        self.assertFalse(any(path[:3] == ("users", "alice", "trades") for path in store))

    async def test_soft_signal_cannot_be_executed_by_direct_api_call(self):
        store = {("signals", "signal-1"): {**hard_signal(), "setup_ready": False}}
        handler = load_handler(store)
        request = Request({**intent(), "userId": "alice", "signalId": "signal-1"})
        with self.assertRaises(HttpError) as error:
            await handler(request, "Bearer valid", "intent-000000001")
        self.assertEqual(error.exception.status_code, 403)
        self.assertFalse(any(path[:3] == ("users", "alice", "trades") for path in store))

    async def test_retry_replays_one_paper_trade_and_conflicting_body_fails(self):
        store = {("signals", "signal-1"): hard_signal()}
        handler = load_handler(store)
        request = Request({**intent(), "userId": "alice", "signalId": "signal-1"})
        first = await handler(request, "Bearer valid", "intent-000000001")
        second = await handler(request, "Bearer valid", "intent-000000001")
        self.assertEqual(first, second)
        self.assertEqual(
            len([path for path in store if path[:3] == ("users", "alice", "trades")]), 1
        )
        altered = Request({**request.data, "volume": 0.2})
        with self.assertRaises(HttpError) as error:
            await handler(altered, "Bearer valid", "intent-000000001")
        self.assertEqual(error.exception.status_code, 409)


if __name__ == "__main__":
    unittest.main()
