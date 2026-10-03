"""Provider-independent Macro/Risk Guard fixtures for V2.1."""

from __future__ import annotations

import unittest

from feature_engine import (
    build_signal_from_features,
    evaluate_macro_risk_guard,
    evaluate_setup_and_veto,
    is_executable_signal,
    normalize_macro_events,
)


class MacroRiskTests(unittest.TestCase):
    def test_macro_events_are_currency_aware_and_keep_provenance(self):
        result = normalize_macro_events(
            [
                {
                    "event_id": "nfp-1",
                    "source": "licensed-calendar",
                    "event_time": 1_700_001_800,
                    "retrieved_at": 1_700_000_000,
                    "impact": "HIGH",
                    "currencies": ["USD"],
                    "title": "Non-farm payrolls",
                },
                {
                    "event_id": "jpy-1",
                    "source": "licensed-calendar",
                    "event_time": 1_700_001_800,
                    "retrieved_at": 1_700_000_000,
                    "impact": "HIGH",
                    "currencies": ["JPY"],
                    "title": "BOJ decision",
                },
            ],
            symbol="XAUUSD",
            now_ts=1_700_000_100,
        )
        self.assertEqual(result["status"], "AVAILABLE")
        self.assertEqual([event["event_id"] for event in result["events"]], ["nfp-1"])
        self.assertEqual(
            result["events"][0]["provenance"],
            {
                "source": "licensed-calendar",
                "source_id": "nfp-1",
                "timestamp": 1_700_001_800,
            },
        )

    def test_stale_or_missing_news_is_labeled_not_fabricated(self):
        stale = normalize_macro_events(
            [
                {
                    "event_id": "old-1",
                    "source": "licensed-calendar",
                    "event_time": 1_700_001_800,
                    "retrieved_at": 1_699_990_000,
                    "impact": "HIGH",
                    "currencies": ["USD"],
                    "title": "Old snapshot",
                }
            ],
            symbol="EURUSD",
            now_ts=1_700_000_100,
            max_source_age_sec=900,
        )
        unavailable = normalize_macro_events([], symbol="EURUSD", now_ts=1_700_000_100)
        self.assertEqual(stale["status"], "STALE")
        self.assertEqual(stale["events"], [])
        self.assertEqual(unavailable["status"], "UNAVAILABLE")

    def test_high_impact_event_inside_window_freezes_hard_setup(self):
        macro = normalize_macro_events(
            [
                {
                    "event_id": "cpi-1",
                    "source": "licensed-calendar",
                    "event_time": 1_700_000_600,
                    "retrieved_at": 1_700_000_000,
                    "impact": "HIGH",
                    "currencies": ["USD"],
                    "title": "CPI release",
                }
            ],
            symbol="XAUUSD",
            now_ts=1_700_000_100,
        )
        guard = evaluate_macro_risk_guard(macro)
        result = evaluate_setup_and_veto(
            {
                "current_price": 100,
                "atr": 1,
                "bias": "BUY",
                "order_blocks": [{"bias": "bullish", "top": 101, "bottom": 99}],
                "confirmation": {"type": "bullish_engulfing"},
                "consensus_percent": 100,
                "macro_risk_guard": guard,
            }
        )
        self.assertTrue(guard["veto"])
        self.assertEqual(guard["veto_data"]["event_id"], "cpi-1")
        self.assertTrue(result["veto"])
        self.assertFalse(result["setup_ready"])

    def test_stale_macro_snapshot_cannot_invent_an_event_veto(self):
        guard = evaluate_macro_risk_guard(
            {"status": "STALE", "label": "Macro data stale", "events": []}
        )
        self.assertFalse(guard["available"])
        self.assertFalse(guard["veto"])
        self.assertEqual(guard["label"], "Macro data stale")

    def test_high_impact_event_is_appended_to_layer5_with_evidence(self):
        macro = normalize_macro_events(
            [
                {
                    "event_id": "fed-1",
                    "source": "licensed-calendar",
                    "event_time": 1_700_000_600,
                    "retrieved_at": 1_700_000_000,
                    "impact": "HIGH",
                    "currencies": ["USD"],
                    "title": "Federal Reserve decision",
                }
            ],
            symbol="XAUUSD",
            now_ts=1_700_000_100,
        )
        signal = build_signal_from_features(
            {
                "symbol": "XAUUSD",
                "timeframe": "M5",
                "bias": "NEUTRAL",
                "current_price": 100,
                "atr": 1,
                "last_closed_candle_timestamp": 1_700_000_000,
                "macro_events": macro,
            }
        )
        items = next(layer for layer in signal["layers"] if layer["layer"] == 5)["items"]
        news = [item for item in items if item.get("type") == "news_column"]
        self.assertEqual(len(news), 1)
        self.assertEqual(news[0]["event_id"], "fed-1")
        self.assertEqual(news[0]["start_time"], 1_699_998_800)
        self.assertEqual(news[0]["duration_min"], 45)
        self.assertNotIn("time_x", news[0])
        self.assertEqual(news[0]["evidence"]["source"], "licensed-calendar")

    def test_reward_risk_below_two_cannot_execute(self):
        base = {
            "setup_ready": True,
            "veto": False,
            "type": "BUY",
            "entryPrice": 100,
            "slPrice": 99,
            "tpPrices": [101.99, 103, 104],
        }
        self.assertFalse(is_executable_signal(base))
        self.assertTrue(is_executable_signal({**base, "tpPrices": [102, 103, 104]}))

    def test_sell_reward_risk_is_symmetric_and_requires_three_targets(self):
        base = {
            "setup_ready": True,
            "veto": False,
            "type": "SELL",
            "entryPrice": 100,
            "slPrice": 101,
        }
        self.assertFalse(is_executable_signal({**base, "tpPrices": [98]}))
        self.assertTrue(is_executable_signal({**base, "tpPrices": [98, 97, 96]}))


if __name__ == "__main__":
    unittest.main()
