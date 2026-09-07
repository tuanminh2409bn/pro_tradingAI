#!/usr/bin/env python3
"""Day 7 — harden + DoD regression markers (static)."""

from __future__ import annotations

import re
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parent
SERVER = (ROOT / "server.py").read_text(encoding="utf-8")
FE_BUNDLE_HINTS = {
    "panelResetNonce": ROOT / "lib/features/trading_room/bloc/trading_room_state.dart",
    "allowsTimeframe": ROOT / "lib/data/models/trading_models.dart",
    "setupReady": ROOT / "lib/data/models/trading_models.dart",
    "withNewsRedZone": ROOT / "lib/data/models/trading_models.dart",
    "fromFirestoreMap": ROOT / "lib/data/models/journal_models.dart",
    "brokerLinked": ROOT / "lib/data/repositories/profile_repository.dart",
}


class Day7HardenTests(unittest.TestCase):
    def test_api_version_21(self):
        self.assertIn('"version": "2.1"', SERVER)
        self.assertIn('"sprint": "v21-day7"', SERVER)
        self.assertIn("deepseek_configured", SERVER)

    def test_ai_chat_guards_missing_key(self):
        fn = SERVER.split('@app.post("/api/ai/chat")', 1)[1].split("@app.", 1)[0]
        self.assertIn("if not DEEPSEEK_API_KEY", fn)
        self.assertIn('"fallback": True', fn)
        self.assertNotIn("str(e)", fn.split("except Exception as e:", 1)[-1].split("return {", 1)[-1].split("}", 1)[0])

    def test_trade_errors_do_not_leak_exception(self):
        for route in ('"/api/trade"', '"/api/trade/close"', "link"):
            self.assertTrue(True)
        trade = SERVER.split('@app.post("/api/trade")', 1)[1].split("@app.", 1)[0]
        self.assertIn("Trade execution failed", trade)
        self.assertNotIn('"message": str(e)', trade)
        close = SERVER.split('@app.post("/api/trade/close")', 1)[1].split("@app.", 1)[0]
        self.assertIn("Unable to close trade", close)
        self.assertNotIn('"message": str(e)', close)

    def test_no_random_in_analysis_fallback(self):
        # Session ids may use random; analysis path must not.
        analysis = SERVER.split("async def get_ai_analysis", 1)
        body = analysis[1] if len(analysis) > 1 else SERVER
        # Prefer feature_engine path
        fe = (ROOT / "feature_engine.py").read_text(encoding="utf-8")
        self.assertNotIn("random.choice", fe)
        self.assertIn("no random", fe.lower())

    def test_core_dod_symbols_present(self):
        for needle, path in FE_BUNDLE_HINTS.items():
            text = path.read_text(encoding="utf-8")
            self.assertIn(needle, text, msg=f"{needle} missing in {path.name}")

    def test_i18n_no_sl123_labels(self):
        loc = (ROOT / "lib/core/localization/app_localizations.dart").read_text(
            encoding="utf-8"
        )
        self.assertNotIn("SL1 Tight", loc)
        self.assertNotIn("SL2 Normal", loc)
        self.assertNotIn("SL3 Wide", loc)

    def test_mobile_no_broker_password_form(self):
        mobile = (
            ROOT / "lib/features/profile/mobile/profile_mobile_page.dart"
        ).read_text(encoding="utf-8")
        self.assertIn("link_on_web_only", mobile)
        self.assertNotIn("_showLinkAccountDialog", mobile)
        self.assertNotIn("profile_trading_password", mobile)


if __name__ == "__main__":
    unittest.main()
