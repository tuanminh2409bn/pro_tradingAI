"""Trusted server market-history selection tests."""

import unittest

from market_history import build_trusted_mtf_history, symbol_bound_price


def five_minute_history(count: int, *, start: int = 0) -> list[dict]:
    return [
        {
            "t": start + index * 300,
            "o": 100.0,
            "h": 102.0,
            "l": 99.0,
            "c": 101.0,
            "v": 10.0,
        }
        for index in range(count)
    ]


class TrustedMarketHistoryTests(unittest.TestCase):
    def test_analysis_price_never_uses_another_symbols_mark(self):
        self.assertEqual(
            symbol_bound_price("BTCUSD", {"XAUUSD": 2500.0}, []), 0.0
        )
        self.assertEqual(
            symbol_bound_price(
                "BTCUSD", {"XAUUSD": 2500.0}, [{"c": 90_000.0}]
            ),
            90_000.0,
        )
        self.assertEqual(
            symbol_bound_price("BTCUSD", {"BTCUSD": 91_000.0}, [{"c": 90_000.0}]),
            91_000.0,
        )

    def test_incomplete_source_bucket_cannot_become_valid_mtf_history(self):
        candles = five_minute_history(7500, start=300)
        # Removing one M5 bar used to leave an apparently complete M15 bar.
        candles.pop(-30)
        result = build_trusted_mtf_history(
            requested_symbol="XAUUSD",
            execution_timeframe="15",
            provider_symbol="XAUUSD",
            provider_timeframe="5",
            provider_candles=candles,
            now_ts=candles[-1]["t"] + 300,
        )
        self.assertFalse(result.available)
        self.assertIn("invalid_m15", result.reason)

    def test_higher_provider_timeframe_cannot_supply_lower_execution(self):
        candles = five_minute_history(2000, start=300)
        result = build_trusted_mtf_history(
            requested_symbol="XAUUSD",
            execution_timeframe="5",
            provider_symbol="XAUUSD",
            provider_timeframe="60",
            provider_candles=candles,
            now_ts=600_300,
        )
        self.assertFalse(result.available)
        self.assertEqual(result.reason, "provider_timeframe_too_coarse")

    def test_scalping_uses_exact_closed_server_owned_histories(self):
        candles = five_minute_history(2000, start=300)
        result = build_trusted_mtf_history(
            requested_symbol="XAUUSD",
            execution_timeframe="5",
            provider_symbol="XAUUSD",
            provider_timeframe="5",
            provider_candles=candles,
            now_ts=candles[-1]["t"] + 300,
        )
        self.assertTrue(result.available, result.reason)
        self.assertEqual(len(result.execution), 120)
        self.assertEqual(len(result.htf1), 120)
        self.assertEqual(len(result.htf2), 150)
        self.assertEqual(result.source, "server_market_stream")

    def test_foreign_symbol_and_insufficient_history_fail_closed(self):
        candles = five_minute_history(120, start=300)
        mismatch = build_trusted_mtf_history(
            requested_symbol="BTCUSD",
            execution_timeframe="5",
            provider_symbol="XAUUSD",
            provider_timeframe="5",
            provider_candles=candles,
            now_ts=100_000,
        )
        self.assertFalse(mismatch.available)
        self.assertEqual(mismatch.reason, "server_symbol_mismatch")

        insufficient = build_trusted_mtf_history(
            requested_symbol="XAUUSD",
            execution_timeframe="5",
            provider_symbol="XAUUSD",
            provider_timeframe="5",
            provider_candles=candles,
            now_ts=100_000,
        )
        self.assertFalse(insufficient.available)
        self.assertIn("expected_120_candles", insufficient.reason)


if __name__ == "__main__":
    unittest.main()
