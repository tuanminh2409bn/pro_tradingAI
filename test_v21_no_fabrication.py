"""V2.1 analysis must omit visuals that have no supporting evidence."""

from __future__ import annotations

import unittest

from feature_engine import build_signal_from_features


class NoFabricationTests(unittest.TestCase):
    def test_empty_evidence_does_not_invent_analysis_layers(self):
        signal = build_signal_from_features(
            {
                "symbol": "XAUUSD",
                "bias": "BUY",
                "current_price": 2400.0,
                "atr": 10.0,
                "candle_interval_sec": 300,
                "last_closed_candle_timestamp": 1_700_000_000,
                "order_blocks": [],
                "fvgs": [],
                "swing_highs": [],
                "swing_lows": [],
                "structure": {"trend": "Neutral", "events": []},
                "setup_ready": False,
                "veto": False,
            }
        )

        all_items = [
            item
            for layer in signal["layers"]
            for item in (layer.get("items") or [])
        ]
        item_types = {item.get("type") for item in all_items}
        texts = " ".join(
            str(item.get("text") or item.get("label") or "") for item in all_items
        )

        self.assertNotIn("ghost_box", item_types)
        self.assertNotIn("wyckoff_phase", item_types)
        self.assertNotIn("$$$", texts)
        self.assertNotIn("STOP", texts)
        self.assertNotIn("OB (", texts)
        self.assertEqual(signal["probability"], 0)

    def test_real_order_block_is_preserved(self):
        signal = build_signal_from_features(
            {
                "symbol": "XAUUSD",
                "bias": "BUY",
                "current_price": 2400.0,
                "atr": 10.0,
                "candle_interval_sec": 300,
                "last_closed_candle_timestamp": 1_700_000_000,
                "order_blocks": [
                    {
                        "bias": "bullish",
                        "top": 2402.0,
                        "bottom": 2398.0,
                        "t_start": 1_699_999_100,
                        "t_end": 1_699_999_400,
                    }
                ],
                "fvgs": [],
                "swing_highs": [],
                "swing_lows": [],
                "structure": {"trend": "Bullish", "events": []},
                "setup_ready": False,
                "veto": False,
            }
        )

        structural = next(layer for layer in signal["layers"] if layer["layer"] == 1)
        self.assertEqual(len(structural["items"]), 1)
        self.assertEqual(structural["items"][0]["label"], "OB")

    def test_invalid_htf_history_does_not_emit_trend_or_ghost_overlay(self):
        signal = build_signal_from_features(
            {
                "symbol": "XAUUSD",
                "timeframe": "5",
                "bias": "BUY",
                "current_price": 100,
                "atr": 1,
                "last_closed_candle_timestamp": 1_700_000_000,
                "htf1": {
                    "timeframe": "H4",
                    "history_valid": False,
                    "structure": {"trend": "Bearish"},
                    "order_blocks": [
                        {"bias": "bearish", "top": 101, "bottom": 99, "t_start": 123}
                    ],
                },
            }
        )
        overlays = next(layer for layer in signal["layers"] if layer["layer"] == 5)["items"]
        self.assertEqual(overlays, [])


if __name__ == "__main__":
    unittest.main()
