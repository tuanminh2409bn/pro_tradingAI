"""
Day 3 analysis cache + stampede lock.

cache_key = analysis:{symbol}:{timeframe}:{last_closed_candle_timestamp}

Uses Redis when REDIS_URL is reachable; otherwise in-process memory with TTL
(so local/dev still gets determinism + single-flight within one worker).
"""
from __future__ import annotations

import asyncio
import json
import os
import time
from typing import Any


# Midpoints of the ranges requested by the client
TTL_BY_TF = {
    "1": 60,
    "5": 240,      # 180–300s
    "15": 600,     # 450–900s
    "60": 2400,    # 1800–3600s
    "240": 7200,
    "1440": 28800,
    "D": 28800,
    "1D": 28800,
}


def analysis_cache_key(symbol: str, timeframe: str, last_closed_ts: int) -> str:
    sym = (symbol or "XAUUSD").upper().replace(" ", "")
    tf = str(timeframe).strip()
    if tf in ("D", "1D"):
        tf = "1440"
    return f"analysis:{sym}:{tf}:{int(last_closed_ts)}"


def analysis_lock_key(cache_key: str) -> str:
    return f"analysis_lock:{cache_key}"


def ttl_for_timeframe(timeframe: str) -> int:
    tf = str(timeframe).strip()
    if tf in ("D", "1D"):
        tf = "1440"
    return int(TTL_BY_TF.get(tf, 240))


class AnalysisCache:
    def __init__(self, redis_url: str | None = None):
        self.redis_url = redis_url or os.environ.get("REDIS_URL", "").strip()
        self._redis = None
        self._redis_ok = False
        self._mem: dict[str, tuple[float, str]] = {}  # key -> (expires_at, json)
        self._holders: dict[str, float] = {}  # lock_key -> acquired_at
        self._lock_guard = asyncio.Lock()

    @property
    def backend(self) -> str:
        return "redis" if self._redis_ok else "memory"

    async def connect(self) -> None:
        if not self.redis_url:
            print("[AnalysisCache] REDIS_URL not set — using in-memory cache")
            return
        try:
            import redis.asyncio as redis  # type: ignore

            client = redis.from_url(self.redis_url, decode_responses=True)
            await client.ping()
            self._redis = client
            self._redis_ok = True
            print(f"[AnalysisCache] Connected to Redis ({self.redis_url})")
        except Exception as e:
            self._redis = None
            self._redis_ok = False
            print(f"[AnalysisCache] Redis unavailable ({e}) — using in-memory cache")

    def _mem_get(self, key: str) -> dict | None:
        item = self._mem.get(key)
        if not item:
            return None
        exp, payload = item
        if time.time() > exp:
            self._mem.pop(key, None)
            return None
        return json.loads(payload)

    def _mem_set(self, key: str, value: dict, ttl: int) -> None:
        self._mem[key] = (time.time() + max(1, ttl), json.dumps(value, separators=(",", ":")))

    async def get(self, key: str) -> dict | None:
        if self._redis_ok and self._redis is not None:
            try:
                raw = await self._redis.get(key)
                if raw:
                    return json.loads(raw)
            except Exception as e:
                print(f"[AnalysisCache] GET error: {e}")
        return self._mem_get(key)

    async def set(self, key: str, value: dict, ttl: int) -> None:
        # Never persist Firestore sentinel / per-user fields in shared cache
        clean = {
            k: v for k, v in value.items()
            if k not in ("createdAt", "userId", "status") and not callable(v)
        }
        payload = json.dumps(clean, separators=(",", ":"), default=str)
        if self._redis_ok and self._redis is not None:
            try:
                await self._redis.set(key, payload, ex=max(1, ttl))
            except Exception as e:
                print(f"[AnalysisCache] SET error: {e}")
        self._mem_set(key, clean, ttl)

    async def acquire_lock(self, cache_key: str, ttl: int = 90) -> bool:
        """
        Distributed/single-flight lock.
        Returns True if this caller should run the LLM pipeline.
        """
        lock_key = analysis_lock_key(cache_key)
        if self._redis_ok and self._redis is not None:
            try:
                ok = await self._redis.set(lock_key, "1", nx=True, ex=max(30, ttl))
                return bool(ok)
            except Exception as e:
                print(f"[AnalysisCache] LOCK error: {e}")
        async with self._lock_guard:
            now = time.time()
            # Expire stale local locks
            stale = [k for k, ts in self._holders.items() if now - ts > max(30, ttl)]
            for k in stale:
                self._holders.pop(k, None)
            if lock_key in self._holders:
                return False
            self._holders[lock_key] = now
            return True

    async def release_lock(self, cache_key: str) -> None:
        lock_key = analysis_lock_key(cache_key)
        if self._redis_ok and self._redis is not None:
            try:
                await self._redis.delete(lock_key)
            except Exception as e:
                print(f"[AnalysisCache] UNLOCK error: {e}")
        async with self._lock_guard:
            self._holders.pop(lock_key, None)

    async def wait_for(
        self,
        cache_key: str,
        timeout_sec: float = 45.0,
        poll_sec: float = 0.25,
    ) -> dict | None:
        """Poll until cache is populated (stampede waiters)."""
        deadline = time.time() + timeout_sec
        while time.time() < deadline:
            hit = await self.get(cache_key)
            if hit is not None:
                return hit
            await asyncio.sleep(poll_sec)
        return None


# Process-wide singleton
analysis_cache = AnalysisCache()
