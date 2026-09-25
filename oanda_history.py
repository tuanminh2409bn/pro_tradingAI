"""Optional, server-only OANDA Practice OHLCV history boundary.

OANDA's `volume` is a count of prices during a candle (tick volume), not
exchange-traded units. No caller may turn an unavailable response into a signal.
"""

from __future__ import annotations

import re
from datetime import datetime, timezone

from feature_engine import candle_interval_sec, required_mtf_datasets, validate_candle_history
from market_history import TrustedMtfHistory


_INSTRUMENTS = frozenset({
    "XAUUSD", "XAGUSD", "EURUSD", "GBPUSD", "USDJPY", "USDCHF",
    "AUDUSD", "USDCAD", "NZDUSD", "EURGBP", "EURJPY", "GBPJPY",
    "EURAUD", "GBPAUD", "AUDNZD", "CADCHF", "AUDCAD", "NZDJPY",
})
_TIMEFRAMES = {"5": "scalping", "15": "day_trading", "60": "swing"}
_GRANULARITIES = {"M5": "M5", "M15": "M15", "H1": "H1", "H4": "H4", "D1": "D"}
_BASE_URL = "https://api-fxpractice.oanda.com"


def parse_oanda_candles(payload: dict, instrument: str, granularity: str) -> list[dict]:
    """Reject identity, shape, completeness, or volume errors at ingress."""
    if (
        not isinstance(payload, dict)
        or payload.get("instrument") != instrument
        or payload.get("granularity") != granularity
        or not isinstance(payload.get("candles"), list)
    ):
        raise ValueError("OANDA candle identity unavailable")
    result: list[dict] = []
    for raw in payload["candles"]:
        if not isinstance(raw, dict) or raw.get("complete") is not True:
            raise ValueError("OANDA candle incomplete")
        volume = raw.get("volume")
        if not isinstance(volume, int) or isinstance(volume, bool) or volume < 0:
            raise ValueError("OANDA volume unavailable")
        mid = raw.get("mid")
        if not isinstance(mid, dict):
            raise ValueError("OANDA midpoint unavailable")
        try:
            clock = datetime.fromisoformat(raw["time"].replace("Z", "+00:00"))
            if clock.tzinfo is None or clock.utcoffset() is None:
                raise ValueError("OANDA timestamp unavailable")
            result.append({
                "t": int(clock.astimezone(timezone.utc).timestamp()),
                "o": float(mid["o"]), "h": float(mid["h"]),
                "l": float(mid["l"]), "c": float(mid["c"]), "v": volume,
            })
        except (AttributeError, KeyError, TypeError, ValueError, OverflowError):
            raise ValueError("OANDA candle malformed") from None
    return result


async def fetch_oanda_mtf_history(
    *, symbol: str, execution_timeframe: str, account_id: str, token: str,
    client, now_ts: int,
) -> TrustedMtfHistory:
    """Fetch three exact closed series; fail closed on any provider error."""
    mode = _TIMEFRAMES.get(str(execution_timeframe))
    if mode is None:
        return TrustedMtfHistory(False, "unsupported_execution_timeframe")
    if symbol not in _INSTRUMENTS:
        return TrustedMtfHistory(False, "unsupported_oanda_symbol")
    if not re.fullmatch(r"[A-Za-z0-9-]{1,64}", account_id or "") or not token:
        return TrustedMtfHistory(False, "oanda_practice_not_configured")
    instrument = f"{symbol[:3]}_{symbol[3:]}"
    histories: list[tuple[dict, ...]] = []
    for timeframe, count in required_mtf_datasets(mode):
        granularity = _GRANULARITIES[timeframe]
        try:
            response = await client.get(
                f"{_BASE_URL}/v3/accounts/{account_id}/instruments/{instrument}/candles",
                headers={"Authorization": f"Bearer {token}"},
                params={
                    "price": "M", "granularity": granularity, "count": count + 1,
                    "dailyAlignment": 0, "alignmentTimezone": "UTC",
                    "smooth": "false",
                },
                timeout=5.0,
            )
            response.raise_for_status()
            payload = response.json()
            if not isinstance(payload, dict) or not isinstance(payload.get("candles"), list):
                raise ValueError("OANDA response malformed")
            closed = [
                candle for candle in payload["candles"]
                if isinstance(candle, dict) and candle.get("complete") is True
            ]
            candles = parse_oanda_candles(
                {**payload, "candles": closed[-count:]}, instrument, granularity
            )
        except Exception:
            return TrustedMtfHistory(False, f"oanda_{timeframe.lower()}_unavailable")
        check = validate_candle_history(
            candles, timeframe, count, now_ts=now_ts
        )
        if not check["valid"]:
            return TrustedMtfHistory(
                False, f"invalid_{timeframe.lower()}:{','.join(check['issues'])}"
            )
        if now_ts - (candles[-1]["t"] + candle_interval_sec(timeframe)) > 2 * candle_interval_sec(timeframe):
            return TrustedMtfHistory(False, f"stale_{timeframe.lower()}_history")
        histories.append(tuple(candles))
    return TrustedMtfHistory(
        True, "", histories[0], histories[1], histories[2],
        source="oanda_practice_tick_volume",
    )
