"""Offline checks for the manual TradingView diagnostic, not product fixtures."""

import unittest
from unittest.mock import patch

from scripts import tradingview_probe as probe


class TradingViewProbeTests(unittest.TestCase):
    def test_packets_reject_truncated_frame(self):
        self.assertEqual(probe._parse_packets("~m~8~m~{}"), [])

    def test_concatenated_packets(self):
        self.assertEqual(probe._parse_packets(probe._pack("{}") + probe._pack("~h~1")), ["{}", "~h~1"])

    def test_precision_and_missing_volume_are_preserved(self):
        bars = probe._extract_candles([{"sds_1": {"s": [{"v": [300, 1.12345, 1.13, 1.12, 1.12346]}]}}])
        self.assertEqual(bars[0]["close"], 1.12346)
        self.assertIsNone(bars[0]["volume"])

    def test_closed_count_and_volume_are_required(self):
        bar = {"time": 300, "open": 1, "high": 2, "low": 1, "close": 2, "volume": None}
        result = probe.summarize_history([bar], "5", 1, now_ts=600)
        self.assertFalse(result["ohlcv_complete"])
        self.assertEqual(result["missing_volume"], 1)
        bar["volume"] = 3
        self.assertTrue(probe.summarize_history([bar], "5", 1, now_ts=600)["ohlcv_complete"])
        self.assertFalse(probe.summarize_history([bar], "5", 1, now_ts=599)["ohlcv_complete"])

    def test_invalid_ohlc_is_not_usable(self):
        bar = {"time": 300, "open": 1, "high": 1, "low": 2, "close": 1, "volume": 3}
        self.assertFalse(probe.summarize_history([bar], "5", 1, now_ts=600)["ohlcv_complete"])
        bar.update(high=2, low=1, volume=float("nan"))
        self.assertFalse(probe.summarize_history([bar], "5", 1, now_ts=600)["ohlcv_complete"])

    def test_all_zero_volume_is_not_complete(self):
        bar = {"time": 300, "open": 1, "high": 2, "low": 1, "close": 2, "volume": 0}
        self.assertFalse(probe.summarize_history([bar], "5", 1, now_ts=600)["ohlcv_complete"])

    def test_malformed_params_are_ignored(self):
        self.assertEqual(probe._extract_candles(None), [])

    def test_backend_gate_preserves_alignment_requirement(self):
        bar = {"time": 301, "open": 1, "high": 2, "low": 1, "close": 2, "volume": 3}
        result = probe.check_backend_history([bar], "5", 1, now_ts=601)
        self.assertFalse(result["valid"])
        self.assertIn("timestamp_not_aligned", result["issues"])

    def test_timeout_returns_error_even_after_partial_data(self):
        class Connection:
            def __enter__(self): return self
            def __exit__(self, *args): pass
            def send(self, data): pass
            def recv(self, timeout): raise TimeoutError
        with patch.object(probe, "_connect", return_value=Connection()):
            candles, error = probe.fetch_tv_history(timeout=1)
        self.assertIsNone(candles)
        self.assertEqual(error, "timeout_before_series_completed")

    def test_daily_and_h4_are_supported(self):
        self.assertEqual(probe.TF_SECONDS["240"], 14400)
        self.assertEqual(probe.TF_SECONDS["1D"], 86400)


if __name__ == "__main__":
    unittest.main()
