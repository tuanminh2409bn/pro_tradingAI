"""V2.1 volume and timestamp-aligned aggregation contract."""

from __future__ import annotations

import unittest

from feature_engine import aggregate_candles


class VolumePipelineTests(unittest.TestCase):
    def test_resample_aligns_to_timeframe_boundary_and_sums_volume(self):
        candles = [
            {"t": 1_700_000_100, "o": 10, "h": 12, "l": 9, "c": 11, "v": 100},
            {"t": 1_700_000_400, "o": 11, "h": 13, "l": 10, "c": 12, "v": 150},
            {"t": 1_700_000_700, "o": 12, "h": 14, "l": 11, "c": 13, "v": 250},
        ]

        result = aggregate_candles(candles, "5", "15")

        self.assertTrue(result)
        self.assertEqual(result[0]["t"] % 900, 0)
        self.assertEqual(sum(item["v"] for item in result), 500.0)

    def test_resample_keeps_ohlcv_for_each_timestamp_bucket(self):
        candles = [
            {"t": 900, "o": 10, "h": 11, "l": 9, "c": 10.5, "v": 10},
            {"t": 1200, "o": 10.5, "h": 13, "l": 10, "c": 12, "v": 20},
            {"t": 1500, "o": 12, "h": 12.5, "l": 8, "c": 9, "v": 30},
        ]

        result = aggregate_candles(candles, "5", "15")

        self.assertEqual(
            result,
            [{"t": 900, "o": 10.0, "h": 13.0, "l": 8.0, "c": 9.0, "v": 60.0}],
        )


if __name__ == "__main__":
    unittest.main()
