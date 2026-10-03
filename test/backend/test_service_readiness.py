"""Run the production status writer with bounded provider stubs, no credentials."""

import ast
import math
import unittest
from pathlib import Path
from types import SimpleNamespace

import asyncio
import httpx


def load_status(payload, *, status_code=200, key="unit-test-key", timeout=False):
    requests = []
    writes = []

    async def handler(request):
        requests.append(request)
        if timeout:
            raise httpx.ReadTimeout("Provider timeout", request=request)
        return httpx.Response(status_code, json=payload)

    transport = httpx.MockTransport(handler)
    record = SimpleNamespace(set=lambda data, **kwargs: writes.append(data))
    source = (Path(__file__).resolve().parents[2] / "server.py").read_text()
    nodes = []
    for node in ast.parse(source).body:
        if isinstance(node, ast.AsyncFunctionDef) and node.name == "_check_service_status":
            nodes.append(node)
        elif isinstance(node, ast.ClassDef) and node.name == "TradingViewStreamer":
            node.body = [method for method in node.body if isinstance(method, ast.FunctionDef)
                         and method.name in {"__init__", "chart_symbol_clean", "set_last_price"}]
            nodes.append(node)
    clock = SimpleNamespace(monotonic=lambda: 1000.0)
    namespace = {
        "httpx": SimpleNamespace(
            AsyncClient=lambda **kwargs: httpx.AsyncClient(transport=transport, **kwargs),
            HTTPError=httpx.HTTPError,
        ),
        "asyncio": asyncio, "time": clock, "math": math,
        "DEEPSEEK_API_KEY": key,
        "normalize_symbol": lambda value: value.split(":")[-1].upper(),
        "analysis_cache": SimpleNamespace(backend="memory"),
        "_MASTER_PROMPT_CACHE_TTL": 60,
        "firestore": SimpleNamespace(SERVER_TIMESTAMP="server-time"),
        "db": SimpleNamespace(collection=lambda path: SimpleNamespace(document=lambda uid: record)),
    }
    exec(compile(ast.fix_missing_locations(ast.Module(body=nodes, type_ignores=[])),
                 "server.py", "exec"), namespace)
    namespace["streamer"] = namespace["TradingViewStreamer"]()
    return namespace, requests, writes


class ServiceReadinessTests(unittest.IsolatedAsyncioTestCase):
    async def test_zero_balance_is_not_ai_readiness(self):
        namespace, requests, writes = load_status({"is_available": False})
        await namespace["_check_service_status"]()
        self.assertIs(writes[-1]["ai_online"], False)
        self.assertEqual([(r.method, str(r.url)) for r in requests],
                         [("GET", "https://api.deepseek.com/user/balance")])
        self.assertEqual(requests[0].headers.get("Authorization"), "Bearer unit-test-key")

    async def test_only_explicit_available_balance_enables_ai(self):
        for payload, expected in (({"is_available": True}, True),
                                  ({"is_available": "true"}, False), ({}, False), ([], False)):
            with self.subTest(payload=payload):
                namespace, _, writes = load_status(payload)
                await namespace["_check_service_status"]()
                self.assertIs(writes[-1]["ai_online"], expected)
                self.assertNotIn("balance_infos", writes[-1])
                self.assertIs(writes[-1]["mt4_online"], False)

    async def test_http_failure_and_timeout_fail_closed(self):
        for status_code in (401, 402, 429, 503):
            namespace, _, writes = load_status({"is_available": True}, status_code=status_code)
            await namespace["_check_service_status"]()
            self.assertIs(writes[-1]["ai_online"], False)
        namespace, _, writes = load_status({}, timeout=True)
        await namespace["_check_service_status"]()
        self.assertIs(writes[-1]["ai_online"], False)

    async def test_missing_key_never_calls_provider_or_broker(self):
        namespace, requests, writes = load_status({}, key="")
        await namespace["_check_service_status"]()
        self.assertEqual(requests, [])
        self.assertIs(writes[-1]["ai_online"], False)
        self.assertIs(writes[-1]["mt4_online"], False)

    async def test_only_recent_finite_symbol_marks_enable_data_status(self):
        namespace, _, writes = load_status({}, key="")
        streamer = namespace["streamer"]
        streamer.last_prices = {"BTCUSD": 83000.0}
        for observed, price, expected in ((1000, 83000, True), (819, 83000, False),
                                          (1001, 83000, False), (1000, float("nan"), False)):
            streamer.last_prices["BTCUSD"] = price
            streamer.price_observed_at = {"BTCUSD": observed}
            await namespace["_check_service_status"]()
            self.assertIs(writes[-1]["data_online"], expected)

    async def test_browser_sessions_share_observation_times_without_chart_state(self):
        namespace, _, _ = load_status({}, key="")
        parent = namespace["streamer"]
        session = namespace["TradingViewStreamer"](
            shared_last_prices=parent.last_prices,
            shared_price_observed_at=parent.price_observed_at,
        )
        session.symbol = "BITSTAMP:BTCUSD"
        session.set_last_price("BTCUSD", 83000.0)
        self.assertEqual(parent.price_observed_at["BTCUSD"], 1000.0)
        self.assertEqual(parent.last_prices["BTCUSD"], 83000.0)
        self.assertEqual(parent.last_price, 0.0)
        self.assertEqual(parent.symbol, "OANDA:XAUUSD")
        for invalid in (float("nan"), float("inf"), -1, True):
            session.set_last_price("ETHUSD", invalid)
        self.assertNotIn("ETHUSD", parent.price_observed_at)
        self.assertNotIn("ETHUSD", parent.last_prices)


if __name__ == "__main__":
    unittest.main()
