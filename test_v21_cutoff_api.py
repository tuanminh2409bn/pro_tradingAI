"""Exercise cutoff transaction bodies without Firebase credentials."""

from __future__ import annotations

import ast
import unittest
from datetime import datetime, timezone
from pathlib import Path
from types import SimpleNamespace

from cutoff_state import cutoff_active, utc_session
from daily_loss_guard import evaluate_daily_loss


class HttpError(Exception):
    def __init__(self, status_code, detail):
        self.status_code = status_code
        self.detail = detail


class Snapshot:
    def __init__(self, data):
        self.exists = data is not None
        self.data = data

    def to_dict(self):
        return self.data


class Ref:
    def __init__(self, store):
        self.store = store

    def get(self, transaction=None):
        return Snapshot(self.store.get("cutoff"))


class Transaction:
    def __init__(self, store):
        self.store = store

    def set(self, ref, data):
        self.store["cutoff"] = dict(data)

    def update(self, ref, data):
        self.store["cutoff"].update(data)


def load_cutoff_functions():
    source = (Path(__file__).parent / "server.py").read_text(encoding="utf-8")
    names = {
        "_cutoff_public_state", "record_cutoff_review",
        "record_cutoff_acknowledgement", "persist_daily_loss_cutoff",
    }
    nodes = [
        node for node in ast.parse(source).body
        if isinstance(node, (ast.FunctionDef, ast.AsyncFunctionDef)) and node.name in names
    ]
    for node in nodes:
        node.decorator_list = []
    namespace = {
        "datetime": datetime,
        "timezone": timezone,
        "cutoff_active": cutoff_active,
        "utc_session": utc_session,
        "HTTPException": HttpError,
        "firestore": SimpleNamespace(SERVER_TIMESTAMP="server-timestamp"),
        "cloud_firestore": SimpleNamespace(transactional=lambda fn: fn),
    }
    exec(compile(ast.fix_missing_locations(ast.Module(body=nodes, type_ignores=[])), "server.py", "exec"), namespace)
    return namespace


class CutoffApiTests(unittest.TestCase):
    def test_trip_review_ack_and_next_utc_session(self):
        functions = load_cutoff_functions()
        store = {}
        ref = Ref(store)
        transaction = Transaction(store)
        trip_time = datetime(2026, 9, 24, 23, 59, tzinfo=timezone.utc)
        decision = evaluate_daily_loss(
            balance=1000, max_daily_loss_percent=5,
            realized_pnl=-20, floating_pnl=-30,
        )
        functions["persist_daily_loss_cutoff"](transaction, ref, decision, trip_time)
        self.assertTrue(cutoff_active(store["cutoff"], trip_time))
        self.assertEqual(store["cutoff"]["sessionDate"], "2026-09-24")
        reviewed = functions["record_cutoff_review"](transaction, ref)
        self.assertTrue(reviewed["reviewed"])
        self.assertEqual(reviewed["lossLimit"], 50)
        acknowledged = functions["record_cutoff_acknowledgement"](transaction, ref)
        self.assertTrue(acknowledged["acknowledged"])
        self.assertTrue(cutoff_active(store["cutoff"], trip_time))
        self.assertFalse(
            cutoff_active(store["cutoff"], datetime(2026, 9, 25, tzinfo=timezone.utc))
        )

    def test_ack_before_review_is_rejected_and_latch_is_not_overwritten(self):
        functions = load_cutoff_functions()
        store = {"cutoff": {"active": True, "sessionDate": "2026-09-24", "lossLimit": 50}}
        ref = Ref(store)
        transaction = Transaction(store)
        with self.assertRaises(HttpError) as error:
            functions["record_cutoff_acknowledgement"](transaction, ref)
        self.assertEqual(error.exception.status_code, 409)
        later = evaluate_daily_loss(
            balance=1000, max_daily_loss_percent=5,
            realized_pnl=-70, floating_pnl=0,
        )
        functions["persist_daily_loss_cutoff"](
            transaction, ref, later, datetime(2026, 9, 25, tzinfo=timezone.utc)
        )
        self.assertEqual(store["cutoff"]["sessionDate"], "2026-09-24")


if __name__ == "__main__":
    unittest.main()
