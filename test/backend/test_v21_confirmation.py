"""Deterministic confirmation-candle fixtures for V2.1."""

from __future__ import annotations

import unittest

from feature_engine import detect_confirmation


class ConfirmationTests(unittest.TestCase):
    def test_bullish_engulfing(self):
        result = detect_confirmation(
            [
                {"t": 1, "o": 101, "h": 102, "l": 98, "c": 99},
                {"t": 2, "o": 98.5, "h": 102, "l": 98, "c": 101.5},
            ]
        )
        self.assertEqual(result["type"], "bullish_engulfing")
        self.assertEqual(result["candle_time"], 2)

    def test_bearish_engulfing(self):
        result = detect_confirmation(
            [
                {"t": 1, "o": 99, "h": 102, "l": 98, "c": 101},
                {"t": 2, "o": 101.5, "h": 102, "l": 98, "c": 98.5},
            ]
        )
        self.assertEqual(result["type"], "bearish_engulfing")

    def test_bullish_pinbar(self):
        result = detect_confirmation(
            [{"t": 3, "o": 100, "h": 100.4, "l": 97, "c": 100.2}]
        )
        self.assertEqual(result["type"], "bullish_pinbar")

    def test_doji_without_dominant_wick_is_not_confirmation(self):
        result = detect_confirmation(
            [{"t": 4, "o": 100, "h": 101, "l": 99, "c": 100.05}]
        )
        self.assertIsNone(result)


if __name__ == "__main__":
    unittest.main()
