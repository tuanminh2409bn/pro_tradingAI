#!/usr/bin/env python3
"""Day 6 — Journal schema dual-write + news impact + admin cache status."""

from __future__ import annotations

import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parent
SERVER = (ROOT / "server.py").read_text(encoding="utf-8")
JOURNAL = (ROOT / "lib/data/models/journal_models.dart").read_text(encoding="utf-8")
SIGNAL = (ROOT / "lib/data/models/trading_models.dart").read_text(encoding="utf-8")


class Day6Tests(unittest.TestCase):
    def test_close_trade_dual_writes_journal_fields(self):
        chunk = SERVER.split("@app.post(\"/api/trade/close\")", 1)[1].split("@app.", 1)[0]
        for key in ("'action'", "'entryPrice'", "'exitPrice'", "'netProfit'"):
            self.assertIn(key, chunk)

    def test_news_impact_keywords(self):
        self.assertIn("HIGH_IMPACT_KEYWORDS", SERVER)
        self.assertIn("def _compute_impact", SERVER)
        self.assertIn('"impact": impact', SERVER)

    def test_admin_service_reports_redis_cache(self):
        chunk = SERVER.split("async def _check_service_status", 1)[1].split(
            "# ─────────────────────────────────────────────────────────────", 1
        )[0]
        self.assertIn("redis_online", chunk)
        self.assertIn("redis_backend", chunk)
        self.assertIn("_MASTER_PROMPT_CACHE_TTL", chunk)

    def test_journal_from_firestore_normalizer(self):
        self.assertIn("fromFirestoreMap", JOURNAL)
        self.assertIn("openPrice", JOURNAL)
        self.assertIn("netProfit", JOURNAL)

    def test_signal_news_red_zone_helper(self):
        self.assertIn("withNewsRedZone", SIGNAL)
        self.assertIn("news_column", SIGNAL)


if __name__ == "__main__":
    unittest.main()
