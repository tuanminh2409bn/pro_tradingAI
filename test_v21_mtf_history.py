"""Exact, closed, aligned MTF history validation for V2.1."""

from __future__ import annotations

import unittest

from feature_engine import (
    build_mtf_feature_pack,
    build_unavailable_signal,
    required_mtf_datasets,
    validate_candle_history,
)


def _series(count: int, interval: int, *, start: int = 0) -> list[dict]:
    return [
        {
            "t": start + index * interval,
            "o": 100,
            "h": 102,
            "l": 99,
            "c": 101,
            "v": 10,
        }
        for index in range(1, count + 1)
    ]


class MtfHistoryTests(unittest.TestCase):
    def test_mode_matrix_has_exact_execution_htf1_htf2_counts(self):
        self.assertEqual(required_mtf_datasets("scalping"), (("M5", 120), ("M15", 120), ("H1", 150)))
        self.assertEqual(required_mtf_datasets("day_trading"), (("M15", 120), ("H1", 120), ("H4", 150)))
        self.assertEqual(required_mtf_datasets("swing"), (("H1", 120), ("H4", 120), ("D1", 150)))

    def test_exact_closed_aligned_series_is_valid(self):
        candles = _series(120, 300)
        result = validate_candle_history(candles, "M5", 120, now_ts=40_000)
        self.assertTrue(result["valid"])
        self.assertEqual(result["issues"], [])

    def test_wrong_count_gap_and_forming_bar_are_reported(self):
        candles = _series(119, 300)
        candles[50]["t"] += 300
        result = validate_candle_history(candles, "M5", 120, now_ts=candles[-1]["t"] + 100)
        self.assertFalse(result["valid"])
        self.assertIn("expected_120_candles", result["issues"])
        self.assertIn("timestamps_not_strictly_increasing", result["issues"])
        self.assertIn("forming_candle_present", result["issues"])

    def test_invalid_ohlcv_and_missing_volume_are_rejected(self):
        candles = _series(120, 300)
        candles[3]["h"] = 98
        candles[4].pop("v")
        result = validate_candle_history(candles, "M5", 120, now_ts=40_000)
        self.assertIn("invalid_ohlcv", result["issues"])
        self.assertIn("missing_volume", result["issues"])

    def test_all_zero_provider_volume_is_labeled_unavailable(self):
        candles = _series(120, 300)
        for candle in candles:
            candle["v"] = 0
        result = validate_candle_history(candles, "M5", 120, now_ts=40_000)
        self.assertIn("volume_unavailable", result["issues"])

    def test_insufficient_mtf_pack_is_labeled_unavailable_and_has_no_analysis(self):
        pack = build_mtf_feature_pack(
            "XAUUSD",
            "5",
            _series(20, 300),
            101,
            now_ts=40_000,
        )
        self.assertFalse(pack["analysis_available"])
        signal = build_unavailable_signal(pack)
        self.assertFalse(signal["setup_ready"])
        self.assertEqual(signal["type"], "NEUTRAL")
        self.assertEqual(signal["entryPrice"], None)
        self.assertTrue(all(not layer["items"] for layer in signal["layers"]))
        self.assertIn("DATA UNAVAILABLE", signal["forecast_text"])


if __name__ == "__main__":
    unittest.main()
