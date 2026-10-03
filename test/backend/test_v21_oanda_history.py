"""OANDA Practice candle boundary tests; no network or credentials required."""

from __future__ import annotations

import asyncio
import unittest
from datetime import datetime, timezone

from oanda_history import fetch_oanda_mtf_history, parse_oanda_candles


class FakeResponse:
    def __init__(self, payload):
        self.payload = payload

    def raise_for_status(self):
        return None

    def json(self):
        return self.payload


class FakeClient:
    def __init__(self, payloads):
        self.payloads = payloads
        self.calls = []

    async def get(self, url, *, headers, params, timeout):
        self.calls.append((url, headers, params, timeout))
        await asyncio.sleep(0)
        return FakeResponse(self.payloads[params["granularity"]])


def payload(granularity, count, interval, *, start=86400):
    candles = []
    for index in range(count):
        timestamp = datetime.fromtimestamp(start + index * interval, timezone.utc)
        candles.append({
            "time": timestamp.isoformat().replace("+00:00", "Z"),
            "complete": True,
            "volume": 10,
            "mid": {"o": "100", "h": "102", "l": "99", "c": "101"},
        })
    return {"instrument": "XAU_USD", "granularity": granularity, "candles": candles}


class OandaHistoryTests(unittest.IsolatedAsyncioTestCase):
    def test_parser_rejects_foreign_instrument_forming_bar_and_missing_volume(self):
        sample = payload("M5", 120, 300)
        with self.assertRaises(ValueError):
            parse_oanda_candles(sample, "EUR_USD", "M5")
        sample["instrument"] = "EUR_USD"
        sample["candles"][-1]["complete"] = False
        with self.assertRaises(ValueError):
            parse_oanda_candles(sample, "EUR_USD", "M5")
        sample["candles"][-1]["complete"] = True
        sample["candles"][-1].pop("volume")
        with self.assertRaises(ValueError):
            parse_oanda_candles(sample, "EUR_USD", "M5")

    async def test_fetches_three_exact_histories_with_fixed_utc_alignment(self):
        end = 1_800_000
        responses = {
            "M5": payload("M5", 120, 300, start=end - 120 * 300),
            "M15": payload("M15", 120, 900, start=end - 120 * 900),
            "H1": payload("H1", 150, 3600, start=end - 150 * 3600),
        }
        client = FakeClient(responses)
        result = await fetch_oanda_mtf_history(
            symbol="XAUUSD",
            execution_timeframe="5",
            account_id="practice-1",
            token="opaque-test-token",
            client=client,
            now_ts=end,
        )
        self.assertTrue(result.available, result.reason)
        self.assertEqual([len(result.execution), len(result.htf1), len(result.htf2)], [120, 120, 150])
        self.assertEqual(result.source, "oanda_practice_tick_volume")
        self.assertEqual([call[2]["granularity"] for call in client.calls], ["M5", "M15", "H1"])
        self.assertTrue(all(call[2]["dailyAlignment"] == 0 for call in client.calls))
        self.assertTrue(all(call[2]["alignmentTimezone"] == "UTC" for call in client.calls))
        self.assertTrue(all(call[3] == 5.0 for call in client.calls))

    async def test_gap_and_wrong_symbol_fail_closed(self):
        end = 1_800_000
        responses = {
            "M5": payload("M5", 120, 300, start=end - 120 * 300),
            "M15": payload("M15", 120, 900, start=end - 120 * 900),
            "H1": payload("H1", 150, 3600, start=end - 150 * 3600),
        }
        responses["M15"]["candles"].pop(50)
        client = FakeClient(responses)
        result = await fetch_oanda_mtf_history(
            symbol="XAUUSD", execution_timeframe="5", account_id="practice-1",
            token="opaque-test-token", client=client, now_ts=end,
        )
        self.assertFalse(result.available)
        self.assertIn("invalid_m15", result.reason)
        self.assertEqual(len(client.calls), 2)

        result = await fetch_oanda_mtf_history(
            symbol="BTCUSD", execution_timeframe="5", account_id="practice-1",
            token="opaque-test-token", client=client, now_ts=end,
        )
        self.assertFalse(result.available)
        self.assertEqual(result.reason, "unsupported_oanda_symbol")


if __name__ == "__main__":
    unittest.main()
