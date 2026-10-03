"""Deterministic cache, TTL, and single-flight regressions for V2.1."""

from __future__ import annotations

import asyncio
from unittest.mock import patch
import unittest

from analysis_cache import AnalysisCache, analysis_cache_key, ttl_for_timeframe


class AnalysisCacheTests(unittest.IsolatedAsyncioTestCase):
    def test_cache_key_is_market_only_and_normalizes_daily_timeframe(self):
        self.assertEqual(
            analysis_cache_key(" xau usd ", "D1", 1_700_000_000),
            "analysis:XAUUSD:1440:1700000000",
        )

    def test_ttl_aliases_cover_every_supported_v21_timeframe(self):
        self.assertEqual(ttl_for_timeframe("M5"), 240)
        self.assertEqual(ttl_for_timeframe("M15"), 600)
        self.assertEqual(ttl_for_timeframe("H1"), 2400)
        self.assertEqual(ttl_for_timeframe("H4"), 7200)
        self.assertEqual(ttl_for_timeframe("D1"), 28800)

    async def test_memory_entry_expires_at_its_ttl(self):
        cache = AnalysisCache()
        with patch("analysis_cache.time.time", return_value=100.0):
            await cache.set("analysis:XAUUSD:5:1", {"value": 1}, ttl=10)
        with patch("analysis_cache.time.time", return_value=109.9):
            self.assertEqual(await cache.get("analysis:XAUUSD:5:1"), {"value": 1})
        with patch("analysis_cache.time.time", return_value=110.1):
            self.assertIsNone(await cache.get("analysis:XAUUSD:5:1"))

    async def test_concurrent_misses_call_producer_exactly_once(self):
        cache = AnalysisCache()
        calls = 0

        async def producer() -> dict:
            nonlocal calls
            calls += 1
            await asyncio.sleep(0.02)
            return {"symbol": "XAUUSD", "setup_ready": False}

        results = await asyncio.gather(
            *[
                cache.get_or_compute(
                    "analysis:XAUUSD:5:1",
                    ttl=30,
                    producer=producer,
                    wait_timeout_sec=1,
                    poll_sec=0.005,
                )
                for _ in range(8)
            ]
        )

        self.assertEqual(calls, 1)
        self.assertTrue(all(result[0]["symbol"] == "XAUUSD" for result in results))
        self.assertEqual(sum(1 for _, cache_hit in results if not cache_hit), 1)

    async def test_cache_hit_never_calls_producer(self):
        cache = AnalysisCache()
        await cache.set("analysis:XAUUSD:5:1", {"value": "cached"}, ttl=30)

        async def producer() -> dict:
            self.fail("producer must not run on a cache hit")

        value, cache_hit = await cache.get_or_compute(
            "analysis:XAUUSD:5:1", ttl=30, producer=producer
        )
        self.assertTrue(cache_hit)
        self.assertEqual(value, {"value": "cached"})


if __name__ == "__main__":
    unittest.main()
