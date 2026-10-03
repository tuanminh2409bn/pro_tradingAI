"""Provider acceptance rejects missing bars, wrong markets and forming data."""

import unittest
from unittest.mock import patch
from datetime import datetime, timezone

from feature_engine import validate_candle_history
from market_sessions import aligned, expected_closure, market_open
from tradingview_history import (
    TradingViewSeries, _pack, fetch_tv_series,
    fetch_tradingview_mtf_history, validate_tv_series,
)
import json


def ts(value):
    return int(datetime.fromisoformat(value).replace(tzinfo=timezone.utc).timestamp())


class SessionCalendarTests(unittest.TestCase):
    def test_ny_daily_alignment_tracks_dst(self):
        self.assertTrue(aligned(ts("2026-10-01T21:00"), 86400, "oanda_metals_ny"))
        self.assertTrue(aligned(ts("2026-12-01T22:00"), 86400, "oanda_metals_ny"))
        self.assertFalse(aligned(ts("2026-10-01T22:00"), 86400, "oanda_metals_ny"))

    def test_expected_daily_break_does_not_accept_missing_open_market_bars(self):
        self.assertTrue(expected_closure(ts("2026-10-01T20:45"), ts("2026-10-01T22:00"), 900, "oanda_metals_ny"))
        self.assertFalse(expected_closure(ts("2026-10-01T19:45"), ts("2026-10-01T22:00"), 900, "oanda_metals_ny"))
        self.assertFalse(expected_closure(ts("2026-10-01T20:45"), ts("2026-10-01T22:00"), 900, "crypto_utc"))

    def test_weekend_and_spring_dst_are_explicit(self):
        self.assertFalse(market_open(ts("2026-10-03T12:00"), "oanda_metals_ny"))
        self.assertTrue(market_open(ts("2026-10-04T22:05"), "oanda_metals_ny"))
        self.assertTrue(expected_closure(ts("2026-03-05T22:00"), ts("2026-03-08T21:00"), 86400, "oanda_metals_ny"))

    def test_published_good_friday_closure_only_applies_to_metals(self):
        previous, current = ts("2026-04-01T21:00"), ts("2026-04-05T21:00")
        self.assertTrue(expected_closure(previous, current, 86400, "oanda_metals_ny"))
        self.assertFalse(expected_closure(previous, current, 86400, "oanda_fx_ny"))

    def test_utc_gate_is_unchanged_and_provider_gate_checks_quality(self):
        bar = {"t": ts("2026-10-01T21:00"), "o": 100, "h": 102, "l": 99, "c": 101, "v": 10}
        now = ts("2026-10-03T12:00")
        self.assertFalse(validate_candle_history([bar], "D1", 1, now_ts=now)["valid"])
        self.assertTrue(validate_candle_history([bar], "D1", 1, now_ts=now, session_profile="oanda_metals_ny")["valid"])
        bar["h"] = 98
        self.assertFalse(validate_candle_history([bar], "D1", 1, now_ts=now, session_profile="oanda_metals_ny")["valid"])


class ProviderBoundaryTests(unittest.TestCase):
    def series(self, interval="5", count=121, *, now=1800000000):
        seconds = {"5": 300, "15": 900, "60": 3600}[interval]
        end = now // seconds * seconds
        bars = tuple({"time": end - (count - index) * seconds,
                      "open": 100, "high": 102, "low": 99, "close": 101,
                      "volume": 10} for index in range(count))
        return TradingViewSeries(bars, {"pro_name": "BITSTAMP:BTCUSD", "timezone": "Etc/UTC", "session": "24x7"})

    def test_missing_volume_zero_volume_and_stale_history_fail_closed(self):
        series = self.series(count=120)
        self.assertTrue(validate_tv_series(series, "5", 120, 1800000000)[1]["valid"])
        bars = tuple({**bar, "volume": None} for bar in series.candles)
        self.assertFalse(validate_tv_series(TradingViewSeries(bars, series.metadata), "5", 120, 1800000000)[1]["valid"])
        bars = tuple({**bar, "volume": 0} for bar in series.candles)
        self.assertIn("volume_unavailable", validate_tv_series(TradingViewSeries(bars, series.metadata), "5", 120, 1800000000)[1]["issues"])
        self.assertIn("stale_provider_history", validate_tv_series(series, "5", 120, 1800001000)[1]["issues"])

    def test_forming_bar_is_excluded(self):
        series = self.series(count=120)
        forming = {**series.candles[-1], "time": 1800000000}
        selected, check, _ = validate_tv_series(TradingViewSeries(series.candles + (forming,), series.metadata), "5", 120, 1800000001)
        self.assertTrue(check["valid"])
        self.assertEqual(len(selected), 120)
        self.assertEqual(selected[-1]["t"], 1799999700)

    def test_unknown_session_and_missing_open_market_bar_fail_closed(self):
        series = self.series(count=121)
        gap = series.candles[:60] + series.candles[61:]
        self.assertIn("unexpected_gap", validate_tv_series(TradingViewSeries(gap, series.metadata), "5", 120, 1800000000)[1]["issues"])
        self.assertIn("unsupported_market_session", validate_tv_series(TradingViewSeries(series.candles, {"pro_name": "FOREXCOM:NAS100"}), "5", 120, 1800000000)[1]["issues"])

    def test_identity_is_required_before_completed_series(self):
        def connector(messages):
            class Connection:
                def __enter__(self): return self
                def __exit__(self, *args): pass
                def send(self, data): pass
                def recv(self, timeout): return _pack(json.dumps(messages.pop(0)))
            return lambda *args, **kwargs: Connection()
        result = fetch_tv_series("BITSTAMP:BTCUSD", "5", connector=connector([{"m": "series_completed", "p": []}]))
        self.assertEqual(result.error, "provider_identity_unavailable")
        result = fetch_tv_series("BITSTAMP:BTCUSD", "5", connector=connector([{"m": "symbol_resolved", "p": [{"pro_name": "OANDA:XAUUSD"}]}]))
        self.assertEqual(result.error, "provider_symbol_mismatch")


class MtfProviderTests(unittest.IsolatedAsyncioTestCase):
    async def test_exact_mode_counts_and_preserved_source(self):
        boundary = ProviderBoundaryTests()
        calls = []
        def fetch(symbol, timeframe, count):
            calls.append((symbol, timeframe, count))
            if timeframe in {"240", "1D"}:
                seconds = 14400 if timeframe == "240" else 86400
                end = 1800000000 // seconds * seconds
                template = boundary.series(count=1)
                bars = tuple({**template.candles[0], "time": end - index * seconds} for index in range(count, 0, -1))
                return TradingViewSeries(bars, template.metadata)
            return boundary.series(timeframe, count)
        with patch("tradingview_history.fetch_tv_series", side_effect=fetch):
            for tf in ("5", "15", "60"):
                result = await fetch_tradingview_mtf_history(symbol="BTCUSD", execution_timeframe=tf, now_ts=1800000000)
                self.assertTrue(result.available, result.reason)
                self.assertEqual([len(result.execution), len(result.htf1), len(result.htf2)], [120, 120, 150])
                self.assertEqual(result.source, "tradingview:BITSTAMP:BTCUSD:exchange_volume")
        self.assertEqual(len(calls), 9)

    async def test_usdt_alias_and_unknown_symbol_make_no_network_call(self):
        with patch("tradingview_history.fetch_tv_series") as fetch:
            result = await fetch_tradingview_mtf_history(symbol="BNBUSD", execution_timeframe="5", now_ts=1800000000)
            self.assertFalse(result.available)
            self.assertEqual(result.reason, "quote_currency_mismatch_usd_usdt")
            result = await fetch_tradingview_mtf_history(symbol="FAKEUSD", execution_timeframe="5", now_ts=1800000000)
            self.assertFalse(result.available)
            fetch.assert_not_called()

    async def test_provider_error_does_not_produce_partial_analysis(self):
        with patch("tradingview_history.fetch_tv_series", return_value=TradingViewSeries(error="series_error")):
            result = await fetch_tradingview_mtf_history(symbol="BTCUSD", execution_timeframe="5", now_ts=1800000000)
        self.assertFalse(result.available)
        self.assertEqual(result.execution, ())
        self.assertIn("series_error", result.reason)
