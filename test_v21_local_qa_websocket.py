"""Local QA WebSocket must never open an external market stream."""

import ast
import asyncio
import json
import unittest
from pathlib import Path
from types import SimpleNamespace


class _Disconnected(Exception):
    pass


class _Socket:
    def __init__(self):
        self.messages = iter((
            {"action": "set_interval", "interval": "15"},
            {"action": "set_symbol", "symbol": "EURUSD"},
        ))
        self.sent = []
        self.accepted = False

    async def accept(self):
        self.accepted = True

    async def send_text(self, text):
        self.sent.append(json.loads(text))

    async def receive_text(self):
        try:
            return json.dumps(next(self.messages))
        except StopIteration:
            raise _Disconnected() from None


class _Session:
    instance = None

    def __init__(self, shared_last_prices):
        type(self).instance = self
        self.candle_map = {}
        self.last_price = 0.0
        self.last_prices = shared_last_prices
        self.account_info = {"status": "UNAVAILABLE"}
        self.connections = set()
        self._pending_delta = {}
        self.start_calls = 0
        self.stop_calls = 0

    def chart_symbol_clean(self):
        return "XAUUSD"

    async def start(self):
        self.start_calls += 1

    async def stop(self):
        self.stop_calls += 1


class LocalQaWebSocketTests(unittest.TestCase):
    def test_interval_and_symbol_changes_do_not_start_provider(self):
        source = (Path(__file__).parent / "server.py").read_text(encoding="utf-8")
        endpoint = next(
            node for node in ast.parse(source).body
            if isinstance(node, ast.AsyncFunctionDef) and node.name == "websocket_endpoint"
        )
        endpoint.decorator_list = []
        namespace = {
            "WebSocket": _Socket,
            "WebSocketDisconnect": _Disconnected,
            "TradingViewStreamer": _Session,
            "streamer": SimpleNamespace(last_prices={}),
            "LOCAL_QA_MODE": True,
            "ALLOWED_TV_INTERVALS": {"5", "15"},
            "TV_SYMBOL_MAP": {"EURUSD": "OANDA:EURUSD"},
            "normalize_symbol": lambda value: value,
            "json": json,
        }
        exec(compile(ast.fix_missing_locations(ast.Module(
            body=[endpoint], type_ignores=[],
        )), "server.py", "exec"), namespace)
        socket = _Socket()

        asyncio.run(namespace["websocket_endpoint"](socket))

        self.assertTrue(socket.accepted)
        self.assertEqual(socket.sent[0]["type"], "init")
        self.assertEqual(_Session.instance.start_calls, 0)
        self.assertEqual(_Session.instance.stop_calls, 1)
        self.assertFalse(_Session.instance.connections)


if __name__ == "__main__":
    unittest.main()
