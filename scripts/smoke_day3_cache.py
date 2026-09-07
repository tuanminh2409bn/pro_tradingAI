#!/usr/bin/env python3
import asyncio
from analysis_cache import AnalysisCache, analysis_cache_key, ttl_for_timeframe
from feature_engine import compute_features, build_signal_from_features


async def main():
    c = AnalysisCache("redis://127.0.0.1:6380/0")
    await c.connect()
    candles = [
        {
            "t": 1700000000 + i * 300,
            "o": 4400 + i * 0.2,
            "h": 4401 + i * 0.2,
            "l": 4399 + i * 0.2,
            "c": 4400.1 + i * 0.2,
        }
        for i in range(40)
    ]
    f = compute_features(
        "XAUUSD", "5", candles, candles[-1]["c"], now_ts=candles[-1]["t"] + 400
    )
    key = analysis_cache_key("XAUUSD", "5", f["last_closed_candle_timestamp"])
    s1 = build_signal_from_features(f)
    await c.set(key, s1, ttl_for_timeframe("5"))
    s2 = await c.get(key)
    print("backend", c.backend)
    print("key", key)
    print(
        "identical",
        s1["type"] == s2["type"]
        and s1["entryPrice"] == s2["entryPrice"]
        and s1["probability"] == s2["probability"],
    )
    print("fallback", s2.get("fallback"))


asyncio.run(main())
