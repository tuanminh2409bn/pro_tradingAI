"""Deterministic, explicit calendars for accepted TradingView market series.

OANDA hours: https://www.oanda.com/bvi-en/cfds/hours-of-operation/
Unknown calendars and holidays fail closed; missing bars are never synthesized.
"""

from datetime import datetime, timedelta, timezone
from zoneinfo import ZoneInfo

PROFILES = frozenset({"utc", "crypto_utc", "oanda_fx_ny", "oanda_metals_ny"})
# Explicit published closure, not an exception inferred from missing candles.
# https://www.oanda.com/uk-en/trading/holiday-trading-hours/
METALS_CLOSED_TRADE_DATES = frozenset({"2026-04-03"})


def _zone(profile):
    return ZoneInfo("America/New_York") if profile.startswith("oanda_") else timezone.utc


def aligned(timestamp, interval, profile):
    if profile not in PROFILES:
        return False
    if profile in {"utc", "crypto_utc"}:
        return timestamp % interval == 0
    local = datetime.fromtimestamp(timestamp, _zone(profile))
    seconds = local.hour * 3600 + local.minute * 60 + local.second
    return (seconds - 17 * 3600) % interval == 0


def market_open(timestamp, profile):
    if profile == "crypto_utc":
        return True
    if profile not in {"oanda_fx_ny", "oanda_metals_ny"}:
        return False
    local = datetime.fromtimestamp(timestamp, _zone(profile))
    minute = local.hour * 60 + local.minute
    trade_date = local.date() + timedelta(days=1 if minute >= 17 * 60 else 0)
    if profile == "oanda_metals_ny" and trade_date.isoformat() in METALS_CLOSED_TRADE_DATES:
        return False
    # Conservatively expect the partial opening metals bar at 18:00 as
    # observed in TradingView, even where the broker schedule says 18:05.
    opening = 18 * 60 if profile == "oanda_metals_ny" else 17 * 60 + 5
    closing = 16 * 60 + 59
    if local.weekday() == 5 or (local.weekday() == 4 and minute >= closing):
        return False
    if local.weekday() == 6 and minute < opening:
        return False
    return minute < closing or minute >= opening


def next_bar(timestamp, interval, profile):
    local = datetime.fromtimestamp(timestamp, _zone(profile))
    return int((local + timedelta(seconds=interval)).timestamp())


def bar_expected(timestamp, interval, profile):
    if profile == "crypto_utc":
        return True
    end = next_bar(timestamp, interval, profile)
    # An H4/D1 bar can include a scheduled break and still have trading time.
    return any(market_open(point, profile) for point in range(int(timestamp), end, 60))


def expected_closure(previous, current, interval, profile):
    if profile not in {"oanda_fx_ny", "oanda_metals_ny"}:
        return False
    if current <= previous or current - previous > 7 * 86400:
        return False
    candidate = next_bar(previous, interval, profile)
    while candidate < current:
        if bar_expected(candidate, interval, profile):
            return False
        candidate = next_bar(candidate, interval, profile)
    return candidate == current


def fresh_history(last_timestamp, interval, now_ts, profile):
    if now_ts - next_bar(last_timestamp, interval, profile) <= 2 * interval:
        return True
    candidate = next_bar(last_timestamp, interval, profile)
    if now_ts - candidate > 7 * 86400:
        return False
    while next_bar(candidate, interval, profile) <= now_ts:
        if bar_expected(candidate, interval, profile):
            return False
        candidate = next_bar(candidate, interval, profile)
    return True
