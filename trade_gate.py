"""Pure, fail-closed checks for authenticated paper-trade intents."""

from __future__ import annotations

import asyncio
import hashlib
import math
import re
from typing import Any

from feature_engine import is_executable_signal


_CHART_ID = re.compile(
    r"^([A-Z0-9._-]{2,20})_(M5|M15|H1|H4|D1|5|15|60|240|1440)_([1-9][0-9]*)$"
)
_INTENT_KEY = re.compile(r"^[A-Za-z0-9_-]{16,128}$")
_TF_SECONDS = {
    "M5": 300, "5": 300, "M15": 900, "15": 900,
    "H1": 3600, "60": 3600, "H4": 14400, "240": 14400,
    "D1": 86400, "1440": 86400,
}
_MODE_TF = {
    "scalping": {300, 900, 3600},
    "day_trading": {900, 3600, 14400},
    "swing": {3600, 14400, 86400},
}


class TradeDenied(ValueError):
    """The order is not authorized by the current server-side signal."""


class AuthDenied(ValueError):
    def __init__(self, status_code: int):
        super().__init__("Authentication required" if status_code == 401 else "User mismatch")
        self.status_code = status_code


async def verify_user_identity(
    authorization: str | None,
    claimed_uid: str,
    verifier: Any,
    *,
    invalid_errors: tuple[type[Exception], ...],
    required_role: str | None = None,
) -> str:
    """Verify the bearer token without trusting a body or path user ID."""
    if not authorization or not authorization.startswith("Bearer "):
        raise AuthDenied(401)
    token = authorization[7:].strip()
    if not token:
        raise AuthDenied(401)
    try:
        decoded = await asyncio.to_thread(verifier, token)
    except invalid_errors:
        raise AuthDenied(401) from None
    uid = decoded.get("uid") if isinstance(decoded, dict) else None
    if not isinstance(uid, str) or not uid:
        raise AuthDenied(401)
    if claimed_uid and claimed_uid != uid:
        raise AuthDenied(403)
    if required_role is not None and decoded.get("role") != required_role:
        raise AuthDenied(403)
    return uid


def trade_document_id(uid: str, intent_key: str) -> str:
    if not uid or not isinstance(intent_key, str) or not _INTENT_KEY.fullmatch(intent_key):
        raise TradeDenied("Invalid idempotency key")
    digest = hashlib.sha256(f"{uid}\0{intent_key}".encode()).hexdigest()
    return f"trade_{digest}"


def _positive_number(value: Any) -> bool:
    return (
        isinstance(value, (int, float))
        and not isinstance(value, bool)
        and math.isfinite(value)
        and value > 0
    )


def _same_price(left: Any, right: Any) -> bool:
    return _positive_number(left) and _positive_number(right) and math.isclose(
        float(left), float(right), rel_tol=0, abs_tol=1e-8
    )


def validate_trade_intent(
    uid: str, intent: dict[str, Any], signal: dict[str, Any] | None, *, now: float
) -> str:
    """Return the validated symbol, or reject any client/server contract mismatch."""
    if not isinstance(signal, dict):
        raise TradeDenied("Signal unavailable")
    chart_id = intent.get("signalChartId")
    match = _CHART_ID.fullmatch(chart_id) if isinstance(chart_id, str) else None
    if not match:
        raise TradeDenied("Invalid chart ID")
    symbol, timeframe, timestamp_text = match.groups()
    interval = _TF_SECONDS[timeframe]
    timestamp = int(timestamp_text)
    if timestamp + interval > now + 1 or now - timestamp > 2 * interval + 1:
        raise TradeDenied("Signal is stale")
    layers = signal.get("layers")
    if (
        signal.get("userId") != uid
        or signal.get("status") != "ACTIVE"
        or signal.get("chart_id") != chart_id
        or signal.get("symbol") != symbol
        or signal.get("market_source") != "oanda_practice_tick_volume"
        or signal.get("market_closed_at") != timestamp
        or intent.get("symbol") != symbol
        or interval not in _MODE_TF.get(intent.get("tradingMode"), set())
        or not is_executable_signal(signal)
        or not isinstance(layers, list)
        or not any(
            isinstance(layer, dict) and layer.get("layer") == 4
            for layer in layers
        )
    ):
        raise TradeDenied("No current Hard Setup for this order")
    if intent.get("action") != signal.get("type"):
        raise TradeDenied("Direction mismatch")
    if not _positive_number(intent.get("volume")):
        raise TradeDenied("Invalid lot size")
    if not _same_price(intent.get("entryPrice"), signal.get("entryPrice")):
        raise TradeDenied("Entry mismatch")
    if not _same_price(intent.get("slPrice"), signal.get("slPrice")):
        raise TradeDenied("Stop mismatch")
    submitted = intent.get("tpPrices")
    targets = signal.get("tpPrices")
    if (
        not isinstance(submitted, list)
        or not 1 <= len(submitted) <= 3
        or not isinstance(targets, list)
        or not all(any(_same_price(tp, approved) for approved in targets) for tp in submitted)
    ):
        raise TradeDenied("Target mismatch")
    return symbol
