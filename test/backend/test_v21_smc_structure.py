"""Deterministic SMC structure invariants for V2.1."""

from __future__ import annotations

import unittest

from feature_engine import (
    _structure_events,
    build_signal_from_features,
    compute_features,
    evaluate_setup_and_veto,
)


class SmcStructureTests(unittest.TestCase):
    def test_higher_high_and_higher_low_is_bullish(self):
        result = _structure_events(
            [{"t": 1, "price": 100}, {"t": 3, "price": 110}],
            [{"t": 2, "price": 90}, {"t": 4, "price": 95}],
        )
        self.assertEqual(result["trend"], "Bullish")
        self.assertEqual(result["last_bos"], "bullish")
        self.assertEqual(
            result["events"][0],
            {
                "type": "BOS",
                "bias": "bullish",
                "time_start": 1,
                "price_start": 100,
                "time_end": 3,
                "price_end": 110,
            },
        )

    def test_lower_high_and_lower_low_is_bearish(self):
        result = _structure_events(
            [{"t": 1, "price": 110}, {"t": 3, "price": 105}],
            [{"t": 2, "price": 95}, {"t": 4, "price": 90}],
        )
        self.assertEqual(result["trend"], "Bearish")
        self.assertEqual(result["last_bos"], "bearish")
        self.assertEqual(result["events"][0]["time_start"], 2)
        self.assertEqual(result["events"][0]["price_start"], 95)
        self.assertEqual(result["events"][0]["time_end"], 4)
        self.assertEqual(result["events"][0]["price_end"], 90)

    def test_mixed_structure_is_neutral(self):
        result = _structure_events(
            [{"t": 1, "price": 100}, {"t": 3, "price": 110}],
            [{"t": 2, "price": 95}, {"t": 4, "price": 90}],
        )
        self.assertEqual(result["trend"], "Neutral")
        self.assertEqual(result["events"], [])

    def test_break_below_prior_bullish_structure_is_bearish_choch(self):
        result = _structure_events(
            [
                {"t": 1, "price": 100},
                {"t": 3, "price": 110},
                {"t": 5, "price": 105},
            ],
            [
                {"t": 2, "price": 90},
                {"t": 4, "price": 95},
                {"t": 6, "price": 85},
            ],
        )
        self.assertEqual(result["trend"], "Bearish")
        self.assertEqual(result["last_choch"], "bearish")
        self.assertEqual(result["events"][0]["type"], "CHOCH")

    def test_displacement_break_is_mss(self):
        result = _structure_events(
            [
                {"t": 1, "price": 100},
                {"t": 3, "price": 110},
                {"t": 5, "price": 105},
            ],
            [
                {"t": 2, "price": 90},
                {"t": 4, "price": 95},
                {"t": 6, "price": 85},
            ],
            displacement=True,
        )
        self.assertEqual(result["events"][0]["type"], "MSS")

    def test_neutral_market_does_not_default_to_buy(self):
        candles = [
            {"t": 1_700_000_000 + i * 300, "o": 100, "h": 101, "l": 99, "c": 100, "v": 10}
            for i in range(8)
        ]
        features = compute_features("XAUUSD", "M5", candles, 100, now_ts=2_000_000_000)
        self.assertEqual(features["bias"], "NEUTRAL")

    def test_signal_builder_without_direction_fails_closed_as_neutral(self):
        signal = build_signal_from_features(
            {
                "symbol": "XAUUSD",
                "current_price": 100,
                "atr": 1,
                "last_closed_candle_timestamp": 1_700_000_000,
            }
        )
        self.assertEqual(signal["type"], "NEUTRAL")
        self.assertFalse(signal["setup_ready"])
        self.assertIsNone(signal["entryPrice"])
        self.assertIsNone(signal["slPrice"])
        self.assertEqual(signal["tpPrices"], [])

    def test_neutral_market_cannot_become_hard_setup(self):
        gate = evaluate_setup_and_veto(
            {
                "bias": "NEUTRAL",
                "current_price": 100,
                "atr": 1,
                "order_blocks": [{"bias": "bearish", "top": 101, "bottom": 99}],
                "confirmation": {"type": "bearish_engulfing"},
                "consensus_percent": 100,
            }
        )
        self.assertFalse(gate["setup_ready"])

    def test_hard_buy_uses_structural_stop_and_minimum_two_r_target(self):
        signal = build_signal_from_features(
            {
                "symbol": "XAUUSD",
                "bias": "BUY",
                "current_price": 100,
                "atr": 1,
                "touch_zone": {"bias": "bullish", "top": 100.2, "bottom": 99.5},
                "setup_ready": True,
                "veto": False,
                "consensus_percent": 80,
            }
        )
        self.assertEqual(signal["slPrice"], 99.4)
        self.assertGreaterEqual(signal["tpPrices"][0] - 100, 2 * (100 - signal["slPrice"]))

    def test_hard_sell_uses_structural_stop_and_minimum_two_r_target(self):
        signal = build_signal_from_features(
            {
                "symbol": "XAUUSD",
                "bias": "SELL",
                "current_price": 100,
                "atr": 1,
                "touch_zone": {"bias": "bearish", "top": 100.5, "bottom": 99.8},
                "setup_ready": True,
                "veto": False,
                "consensus_percent": 80,
            }
        )
        self.assertEqual(signal["slPrice"], 100.6)
        self.assertGreaterEqual(100 - signal["tpPrices"][0], 2 * (signal["slPrice"] - 100))


if __name__ == "__main__":
    unittest.main()
