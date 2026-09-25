"""Hand-calculated VSA evidence tests for V2.1."""

from __future__ import annotations

import unittest

from feature_engine import compute_vsa_features


def _candle(t: int, volume: float, *, open_: float = 100, close: float = 100.2, spread: float = 1):
    return {
        "t": t,
        "o": open_,
        "h": max(open_, close) + spread / 2,
        "l": min(open_, close) - spread / 2,
        "c": close,
        "v": volume,
    }


class VsaTests(unittest.TestCase):
    def test_three_x_volume_is_a_measured_buying_climax(self):
        candles = [_candle(i, 10) for i in range(1, 6)]
        candles.append(_candle(6, 30, open_=100, close=102, spread=4))

        result = compute_vsa_features(candles)

        self.assertEqual(result["volume_baseline"], 10)
        self.assertTrue(result["volume_spike"])
        self.assertEqual(result["confirmation"], {"type": "buying_climax", "candle_time": 6})
        self.assertEqual(result["candle_overrides"][0]["fill_color"], "#8A2BE2")
        self.assertEqual(result["liquidity_markers"][0]["text"], "STOP")

    def test_just_below_three_x_does_not_emit_climax_or_stop(self):
        candles = [_candle(i, 10) for i in range(1, 6)]
        candles.append(_candle(6, 29.99, open_=100, close=100.2, spread=1))

        result = compute_vsa_features(candles)

        self.assertFalse(result["volume_spike"])
        self.assertNotIn("confirmation", result)
        self.assertEqual(result["candle_overrides"], [])
        self.assertEqual(result["liquidity_markers"], [])

    def test_missing_volume_emits_no_vsa_evidence(self):
        candles = [_candle(i, 0) for i in range(1, 7)]
        result = compute_vsa_features(candles)
        self.assertEqual(result["volume_baseline"], 0)
        self.assertFalse(result["volume_spike"])
        self.assertEqual(result["candle_overrides"], [])

    def test_lower_low_on_falling_volume_emits_bullish_divergence(self):
        candles = [_candle(i, 10) for i in range(1, 5)]
        candles.append({"t": 5, "o": 100, "h": 101, "l": 98, "c": 99, "v": 20})
        candles.append({"t": 6, "o": 99, "h": 100, "l": 97, "c": 98.5, "v": 15})

        result = compute_vsa_features(candles)

        self.assertEqual(result["candle_overrides"][0]["divergence_direction"], "up")
        self.assertEqual(result["candle_overrides"][0]["divergence_color"], "#00FF7F")

    def test_low_volume_narrow_up_bar_is_no_demand(self):
        candles = [_candle(i, 10) for i in range(1, 6)]
        candles.append(_candle(6, 5, open_=100, close=100.2, spread=0.2))
        result = compute_vsa_features(candles)
        self.assertEqual(result["candle_overrides"][0]["kind"], "no_demand")
        self.assertEqual(result["candle_overrides"][0]["label_bottom"], "ND")
        self.assertEqual(result["candle_overrides"][0]["fill_color"], "#FFFFFF")

    def test_wide_spread_has_gold_border_without_inventing_climax(self):
        candles = [_candle(i, 10) for i in range(1, 6)]
        candles.append(_candle(6, 10, open_=100, close=100.2, spread=3))
        result = compute_vsa_features(candles)
        override = result["candle_overrides"][0]
        self.assertEqual(override["kind"], "spread_alert")
        self.assertEqual(override["border_color"], "#FFD700")
        self.assertNotIn("fill_color", override)


if __name__ == "__main__":
    unittest.main()
