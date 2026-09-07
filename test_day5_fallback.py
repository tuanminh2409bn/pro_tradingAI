#!/usr/bin/env python3
"""Day 5 — AI chat fallback contract (no raw exception to clients)."""

from __future__ import annotations

import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parent
SERVER = (ROOT / "server.py").read_text(encoding="utf-8")


class Day5ChatFallbackTests(unittest.TestCase):
    def test_ai_chat_endpoint_returns_fallback_flag(self):
        self.assertIn('@app.post("/api/ai/chat")', SERVER)
        self.assertIn('"fallback": False', SERVER)
        self.assertIn('"fallback": True', SERVER)
        fn = SERVER.split('@app.post("/api/ai/chat")', 1)[1].split("@app.", 1)[0]
        self.assertIn("temperature=0.0", fn)

    def test_ai_chat_friendly_message_no_exception_leak(self):
        fn = SERVER.split('@app.post("/api/ai/chat")', 1)[1].split("@app.", 1)[0]
        self.assertIn(
            "Hệ thống AI đang thực hiện phân tích kỹ thuật tạm thời",
            fn,
        )
        except_body = fn.split("except Exception as e:", 1)[1]
        return_block = except_body.split("return {", 1)[1].split("}", 1)[0]
        self.assertNotIn("str(e)", return_block)
        self.assertNotIn("{e}", return_block)
        self.assertIn('"fallback": True', return_block)

    def test_chat_message_model_has_is_fallback(self):
        models = (ROOT / "lib/data/models/trading_models.dart").read_text(
            encoding="utf-8"
        )
        self.assertIn("final bool isFallback;", models)


if __name__ == "__main__":
    unittest.main()
