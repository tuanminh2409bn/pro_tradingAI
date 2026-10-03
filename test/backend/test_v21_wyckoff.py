"""Conservative, evidence-backed Wyckoff classification tests."""

from __future__ import annotations

import unittest

from feature_engine import compute_vsa_features, detect_wyckoff_phase


class WyckoffTests(unittest.TestCase):
    def test_volume_spring_below_range_and_close_back_inside_is_phase_c(self):
        candles = [
            {"t": i, "o": 100, "h": 101, "l": 99, "c": 100, "v": 10}
            for i in range(1, 21)
        ]
        candles.append({"t": 21, "o": 99, "h": 101, "l": 98, "c": 100.5, "v": 30})
        vsa = compute_vsa_features(candles)

        result = detect_wyckoff_phase(candles, vsa)

        self.assertEqual(result["phase"], "PHASE C")
        self.assertEqual(result["event"], "SPRING")
        self.assertEqual(result["evidence"]["source_id"], "WYCKOFF:21:SPRING")

    def test_ambiguous_range_omits_wyckoff_phase(self):
        candles = [
            {"t": i, "o": 100, "h": 101, "l": 99, "c": 100, "v": 10}
            for i in range(1, 22)
        ]
        self.assertIsNone(detect_wyckoff_phase(candles, compute_vsa_features(candles)))

    def test_volume_upthrust_above_range_and_close_back_inside_is_phase_c(self):
        candles = [
            {"t": i, "o": 100, "h": 101, "l": 99, "c": 100, "v": 10}
            for i in range(1, 21)
        ]
        candles.append({"t": 21, "o": 101, "h": 102, "l": 99, "c": 99.5, "v": 30})
        result = detect_wyckoff_phase(candles, compute_vsa_features(candles))
        self.assertEqual(result["event"], "UPTHRUST")


if __name__ == "__main__":
    unittest.main()
