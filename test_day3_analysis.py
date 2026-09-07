"""Day 3 — FeatureEngine, cache key/TTL, deterministic fallback, stampede (memory)."""
from __future__ import annotations

import asyncio
import json
import unittest

from analysis_cache import AnalysisCache, analysis_cache_key, ttl_for_timeframe
from feature_engine import (
    build_signal_from_features,
    compute_features,
    features_prompt_block,
    last_closed_candle_timestamp,
)


def _synth_candles(n: int = 40, start: float = 4400.0, step: float = 0.5, t0: int = 1_700_000_000):
    candles = []
    price = start
    for i in range(n):
        o = price
        c = price + (step if i % 3 else -step * 0.6)
        h = max(o, c) + 0.8
        l = min(o, c) - 0.8
        candles.append({"t": t0 + i * 300, "o": o, "h": h, "l": l, "c": c})
        price = c
    return candles


class TestFeatureEngine(unittest.TestCase):
    def test_cache_key_format(self):
        key = analysis_cache_key("xauusd", "5", 1700000000)
        self.assertEqual(key, "analysis:XAUUSD:5:1700000000")

    def test_ttl_matrix(self):
        self.assertEqual(ttl_for_timeframe("5"), 240)
        self.assertEqual(ttl_for_timeframe("15"), 600)
        self.assertEqual(ttl_for_timeframe("60"), 2400)

    def test_last_closed_excludes_forming(self):
        candles = _synth_candles(10, t0=1_700_000_000)
        # now inside last bar
        now = candles[-1]["t"] + 60
        ts = last_closed_candle_timestamp(candles, "5", now_ts=now)
        self.assertEqual(ts, candles[-2]["t"])

    def test_features_no_raw_dump_in_prompt(self):
        candles = _synth_candles()
        feats = compute_features("XAUUSD", "5", candles, candles[-1]["c"], now_ts=candles[-1]["t"] + 400)
        block = features_prompt_block(feats)
        self.assertIn("ATR(14)", block)
        self.assertIn("ORDER_BLOCKS", block)
        self.assertNotIn("Recent 10 candles", block)
        self.assertNotRegex(block, r"\bO:\d")

    def test_fallback_deterministic(self):
        candles = _synth_candles()
        feats = compute_features("XAUUSD", "5", candles, candles[-1]["c"], now_ts=candles[-1]["t"] + 400)
        a = build_signal_from_features(feats)
        b = build_signal_from_features(feats)
        self.assertEqual(a, b)
        self.assertTrue(a.get("fallback"))
        self.assertIn(a["type"], ("BUY", "SELL"))
        # Soft stage may strip Layer 4 → 4 layers; hard keeps 5
        self.assertIn(len(a["layers"]), (4, 5))
        if not a.get("setup_ready") or a.get("veto"):
            self.assertTrue(all(int(l.get("layer", -1)) != 4 for l in a["layers"]))


class TestAnalysisCache(unittest.IsolatedAsyncioTestCase):
    async def test_memory_cache_hit_and_stampede_lock(self):
        cache = AnalysisCache(redis_url="")
        await cache.connect()
        key = analysis_cache_key("XAUUSD", "5", 111)
        self.assertIsNone(await cache.get(key))

        got1 = await cache.acquire_lock(key)
        got2 = await cache.acquire_lock(key)
        self.assertTrue(got1)
        self.assertFalse(got2)

        payload = {"type": "BUY", "entryPrice": 1.0, "userId": "should-strip"}
        await cache.set(key, payload, ttl=60)
        await cache.release_lock(key)

        hit = await cache.get(key)
        self.assertIsNotNone(hit)
        self.assertEqual(hit["type"], "BUY")
        self.assertNotIn("userId", hit)

        # Second waiter sees cache
        waiter = asyncio.create_task(cache.wait_for(key, timeout_sec=2))
        self.assertEqual(await waiter, hit)

        # Identical JSON for same payload
        await cache.set(key, {"type": "BUY", "entryPrice": 1.0}, ttl=60)
        a = json.dumps(await cache.get(key), sort_keys=True)
        b = json.dumps(await cache.get(key), sort_keys=True)
        self.assertEqual(a, b)


if __name__ == "__main__":
    unittest.main()
