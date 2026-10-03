"""Security regressions for Redis cache fallback logging."""

from __future__ import annotations

from contextlib import redirect_stdout
from io import StringIO
import unittest

from analysis_cache import AnalysisCache


class _FailingRedis:
    async def get(self, _key: str) -> None:
        raise RuntimeError("redis://cache-user:super-secret@internal-cache:6379/0")


class CacheSecurityTests(unittest.IsolatedAsyncioTestCase):
    async def test_redis_operation_failure_does_not_log_credentials_or_endpoint(self):
        cache = AnalysisCache("redis://cache-user:super-secret@internal-cache:6379/0")
        cache._redis = _FailingRedis()
        cache._redis_ok = True
        output = StringIO()

        with redirect_stdout(output):
            self.assertIsNone(await cache.get("missing"))

        message = output.getvalue()
        self.assertIn("Redis GET failed", message)
        self.assertNotIn("super-secret", message)
        self.assertNotIn("cache-user", message)
        self.assertNotIn("internal-cache", message)
        self.assertNotIn("redis://", message)


if __name__ == "__main__":
    unittest.main()
