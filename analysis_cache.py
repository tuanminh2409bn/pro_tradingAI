"""
Day 3 analysis cache + stampede lock.

cache_key = analysis:{symbol}:{timeframe}:{last_closed_candle_timestamp}

Uses Redis when REDIS_URL is reachable; otherwise in-process memory with TTL
(so local/dev still gets determinism + single-flight within one worker).
"""
from __future__ import annotations

import asyncio
import inspect
import json
import os
import time
from typing import Any, Awaitable, Callable


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

TIMEFRAME_ALIASES = {
    "M1": "1",
    "M5": "5",
    "M15": "15",
    "H1": "60",
    "H4": "240",
    "D": "1440",
    "1D": "1440",
    "D1": "1440",
}


def _normalize_timeframe(timeframe: str) -> str:
    tf = str(timeframe).strip().upper()
    return TIMEFRAME_ALIASES.get(tf, tf)


def analysis_cache_key(symbol: str, timeframe: str, last_closed_ts: int) -> str:
    sym = (symbol or "XAUUSD").upper().replace(" ", "")
    tf = _normalize_timeframe(timeframe)
    return f"analysis:{sym}:{tf}:{int(last_closed_ts)}"


def analysis_lock_key(cache_key: str) -> str:
    return f"analysis_lock:{cache_key}"


def ttl_for_timeframe(timeframe: str) -> int:
    tf = _normalize_timeframe(timeframe)
    return int(TTL_BY_TF.get(tf, 240))


def _log_redis_failure(operation: str, *, fallback: bool = False) -> None:
    """Log cache degradation without exposing URLs or provider error details."""
    suffix = " — using in-memory cache" if fallback else ""
    print(f"[AnalysisCache] Redis {operation} failed{suffix}")


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
            print("[AnalysisCache] Connected to Redis")
        except Exception:
            self._redis = None
            self._redis_ok = False
            _log_redis_failure("connection", fallback=True)

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
            except Exception:
                _log_redis_failure("GET")
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
            except Exception:
                _log_redis_failure("SET")
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
            except Exception:
                _log_redis_failure("LOCK")
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
            except Exception:
                _log_redis_failure("UNLOCK")
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

    async def get_or_compute(
        self,
        cache_key: str,
        ttl: int,
        producer: Callable[[], Awaitable[dict]],
        *,
        lock_ttl: int = 90,
        wait_timeout_sec: float = 60.0,
        poll_sec: float = 0.25,
        timeout_factory: Callable[[], dict | Awaitable[dict]] | None = None,
    ) -> tuple[dict, bool]:
        """Return one shared market artifact; run ``producer`` once per miss.

        The boolean is true only when this caller reused an existing artifact.
        A timeout fallback is optional and remains deterministic at the caller.
        """
        cached = await self.get(cache_key)
        if cached is not None:
            return cached, True

        owns_lock = await self.acquire_lock(cache_key, ttl=lock_ttl)
        if not owns_lock:
            cached = await self.wait_for(
                cache_key,
                timeout_sec=wait_timeout_sec,
                poll_sec=poll_sec,
            )
            if cached is not None:
                return cached, True
            if timeout_factory is None:
                raise TimeoutError("analysis cache single-flight wait timed out")
            fallback = timeout_factory()
            value = await fallback if inspect.isawaitable(fallback) else fallback
            await self.set(cache_key, value, ttl)
            return value, False

        try:
            cached = await self.get(cache_key)
            if cached is not None:
                return cached, True
            value = await producer()
            await self.set(cache_key, value, ttl)
            return value, False
        finally:
            await self.release_lock(cache_key)


# Process-wide singleton
analysis_cache = AnalysisCache()
