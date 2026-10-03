"""Direct Firestore analysis requests must be bounded before provider work."""

import unittest
import ast
from pathlib import Path
from types import SimpleNamespace

from analysis_contract import validate_client_analysis_request


class AnalysisRequestBoundaryTests(unittest.TestCase):
    def test_accepts_supported_mode_timeframes(self):
        for mode, timeframes in {
            "scalping": ("5", "15", "60"),
            "day_trading": ("15", "60", "240"),
            "swing": ("60", "240", "1440"),
        }.items():
            for timeframe in timeframes:
                with self.subTest(mode=mode, timeframe=timeframe):
                    self.assertEqual(validate_client_analysis_request({
                        "userId": "alice", "status": "PENDING",
                        "symbol": "XAUUSD", "timeframe": timeframe,
                        "execution_tf": timeframe, "trading_mode": mode,
                    }), [])

    def test_rejects_invalid_or_unbounded_input(self):
        valid = {
            "userId": "alice", "status": "PENDING", "symbol": "XAUUSD",
            "timeframe": "5", "execution_tf": "5", "trading_mode": "scalping",
        }
        for payload in (
            {}, {**valid, "symbol": "X" * 500},
            {**valid, "symbol": "../../secret"},
            {**valid, "timeframe": "infinite"},
            {**valid, "execution_tf": "60"},
            {**valid, "trading_mode": "swing"},
            {**valid, "extra": "untrusted"},
            {**valid, "status": "PROCESSING"},
        ):
            with self.subTest(payload=payload):
                self.assertTrue(validate_client_analysis_request(payload))

    def test_listener_refuses_invalid_request_before_scheduling(self):
        source = (Path(__file__).resolve().parents[2] / "server.py").read_text(encoding="utf-8")
        node = next(node for node in ast.parse(source).body
                    if isinstance(node, ast.FunctionDef)
                    and node.name == "on_analysis_request_snapshot")
        writes = []
        scheduled = []
        queue = SimpleNamespace(
            collection=lambda name: SimpleNamespace(
                document=lambda doc_id: SimpleNamespace(
                    update=lambda value: writes.append((name, doc_id, value))
                )
            )
        )
        namespace = {
            "validate_client_analysis_request": validate_client_analysis_request,
            "db": queue,
            "main_loop": SimpleNamespace(is_closed=lambda: False),
            "asyncio": SimpleNamespace(run_coroutine_threadsafe=lambda job, loop: scheduled.append(job)),
            "process_ai_analysis": lambda *args: args,
        }
        exec(compile(ast.fix_missing_locations(ast.Module(body=[node], type_ignores=[])),
                     "server.py", "exec"), namespace)
        handler = namespace["on_analysis_request_snapshot"]
        payload = {
            "userId": "alice", "status": "PENDING", "symbol": "XAUUSD",
            "timeframe": "5", "execution_tf": "5", "trading_mode": "scalping",
        }
        def change(request):
            return SimpleNamespace(
                type=SimpleNamespace(name="ADDED"),
                document=SimpleNamespace(id="request-1", to_dict=lambda: request),
            )
        handler(None, [change({**payload, "timeframe": "bad"})], None)
        self.assertEqual(scheduled, [])
        self.assertEqual(writes, [("analysis_requests", "request-1", {
            "status": "ERROR", "error": "invalid_request",
        })])
        handler(None, [change(payload)], None)
        self.assertEqual(len(scheduled), 1)


if __name__ == "__main__":
    unittest.main()
