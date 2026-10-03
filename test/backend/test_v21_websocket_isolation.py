"""Verify each Web client owns independent chart session state."""

import ast
import asyncio
import json
import unittest
from pathlib import Path
from types import SimpleNamespace


class Disconnect(Exception):
    pass


class FakeSocket:
    def __init__(self, messages):
        self.messages = list(messages)
        self.sent = []
        self.accepted = False

    async def accept(self):
        self.accepted = True

    async def send_text(self, message):
        self.sent.append(json.loads(message))

    async def receive_text(self):
        if self.messages:
            return json.dumps(self.messages.pop(0))
        raise Disconnect()


class FakeSession:
    instances = []

    def __init__(self, shared_last_prices=None, shared_price_observed_at=None):
        self.candle_map = {}
        self.last_price = 0.0
        self.last_prices = shared_last_prices
        self.price_observed_at = shared_price_observed_at
        self.account_info = {"status": "UNAVAILABLE", "source": "unavailable"}
        self.connections = set()
        self.interval = "5"
        self.symbol = "OANDA:XAUUSD"
        self._pending_delta = {}
        self.started = 0
        self.stopped = False
        self.__class__.instances.append(self)

    def chart_symbol_clean(self):
        return self.symbol.split(":")[-1]

    async def start(self):
        self.started += 1

    async def stop(self):
        self.stopped = True
        self.connections.clear()


def load_endpoint():
    source = (Path(__file__).resolve().parents[2] / "server.py").read_text(encoding="utf-8")
    node = next(
        node
        for node in ast.parse(source).body
        if isinstance(node, ast.AsyncFunctionDef) and node.name == "websocket_endpoint"
    )
    node.decorator_list = []
    shared_prices = {"XAUUSD": 2000.0}
    namespace = {
        "WebSocket": object,
        "WebSocketDisconnect": Disconnect,
        "TradingViewStreamer": FakeSession,
        "streamer": SimpleNamespace(last_prices=shared_prices, price_observed_at={}),
        "LOCAL_QA_MODE": False,
        "TV_SYMBOL_MAP": {
            "XAUUSD": "OANDA:XAUUSD",
            "BTCUSD": "BITSTAMP:BTCUSD",
        },
        "ALLOWED_TV_INTERVALS": frozenset({"5", "15", "60", "240", "1440"}),
        "normalize_symbol": lambda value: value.upper().replace("/", ""),
        "json": json,
    }
    exec(
        compile(
            ast.fix_missing_locations(ast.Module(body=[node], type_ignores=[])),
            "server.py",
            "exec",
        ),
        namespace,
    )
    return namespace["websocket_endpoint"], shared_prices


class WebSocketIsolationTests(unittest.IsolatedAsyncioTestCase):
    async def asyncSetUp(self):
        FakeSession.instances.clear()

    async def test_two_clients_cannot_change_each_others_chart_state(self):
        endpoint, shared_prices = load_endpoint()
        symbol_client = FakeSocket([{"action": "set_symbol", "symbol": "BTCUSD"}])
        interval_client = FakeSocket([{"action": "set_interval", "interval": "240"}])

        await asyncio.gather(endpoint(symbol_client), endpoint(interval_client))

        self.assertEqual(len(FakeSession.instances), 2)
        first, second = FakeSession.instances
        self.assertIsNot(first, second)
        self.assertEqual((first.symbol, first.interval), ("BITSTAMP:BTCUSD", "5"))
        self.assertEqual((second.symbol, second.interval), ("OANDA:XAUUSD", "240"))
        self.assertIs(first.last_prices, shared_prices)
        self.assertIs(second.last_prices, shared_prices)
        self.assertIs(first.price_observed_at, second.price_observed_at)
        self.assertTrue(first.stopped)
        self.assertTrue(second.stopped)

    async def test_invalid_selection_does_not_restart_or_mutate_session(self):
        endpoint, _ = load_endpoint()
        client = FakeSocket([
            {"action": "set_symbol", "symbol": "../../internal"},
            {"action": "set_interval", "interval": "99999"},
        ])

        await endpoint(client)

        session = FakeSession.instances[0]
        self.assertEqual((session.symbol, session.interval), ("OANDA:XAUUSD", "5"))
        self.assertEqual(session.started, 1)
        self.assertEqual(
            [message["message"] for message in client.sent if message["type"] == "error"],
            ["Unsupported symbol", "Unsupported interval"],
        )


if __name__ == "__main__":
    unittest.main()
