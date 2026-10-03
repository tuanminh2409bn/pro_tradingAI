"""Bounded anonymous TradingView series, shared by the probe and backend.

This is an unofficial provider. Quote/volume provenance is retained; unknown
sessions, missing data and outages fail closed. No browser candle input is used.
"""

from __future__ import annotations

import asyncio
import json
import math
import re
import secrets
import time
from dataclasses import dataclass, field

from feature_engine import candle_interval_sec, required_mtf_datasets, validate_candle_history
from market_history import TrustedMtfHistory
from market_sessions import fresh_history, market_open, next_bar

TV_WS_URL = "wss://data.tradingview.com/socket.io/websocket"
TF_SECONDS = {"1": 60, "5": 300, "15": 900, "60": 3600, "240": 14400, "1D": 86400}
TV_SYMBOL_MAP = {
    "XAUUSD": "OANDA:XAUUSD", "XAGUSD": "OANDA:XAGUSD",
    "EURUSD": "OANDA:EURUSD", "GBPUSD": "OANDA:GBPUSD",
    "USDJPY": "OANDA:USDJPY", "USDCHF": "OANDA:USDCHF",
    "AUDUSD": "OANDA:AUDUSD", "USDCAD": "OANDA:USDCAD",
    "NZDUSD": "OANDA:NZDUSD", "EURGBP": "OANDA:EURGBP",
    "EURJPY": "OANDA:EURJPY", "GBPJPY": "OANDA:GBPJPY",
    "EURAUD": "OANDA:EURAUD", "GBPAUD": "OANDA:GBPAUD",
    "AUDNZD": "OANDA:AUDNZD", "CADCHF": "OANDA:CADCHF",
    "AUDCAD": "OANDA:AUDCAD", "NZDJPY": "OANDA:NZDJPY",
    "BTCUSD": "BITSTAMP:BTCUSD", "ETHUSD": "BITSTAMP:ETHUSD",
    "BNBUSD": "BINANCE:BNBUSDT", "SOLUSD": "BINANCE:SOLUSDT",
    "XRPUSD": "BITSTAMP:XRPUSD", "ADAUSD": "BINANCE:ADAUSDT",
    "US30": "FOREXCOM:DJI", "US500": "FOREXCOM:SPX500",
    "US100": "FOREXCOM:NAS100", "UK100": "FOREXCOM:UK100",
    "DE40": "FOREXCOM:DE40", "JP225": "FOREXCOM:JPN225",
    "USOIL": "NYMEX:CL1!", "UKOIL": "ICEEUR:B1!",
    "NGAS": "NYMEX:NG1!", "XPTUSD": "OANDA:XPTUSD",
}
_MODES = {"5": "scalping", "15": "day_trading", "60": "swing"}
_WIRE = {"M5": "5", "M15": "15", "H1": "60", "H4": "240", "D1": "1D"}
_limiter = asyncio.Semaphore(4)


@dataclass(frozen=True)
class TradingViewSeries:
    candles: tuple[dict, ...] = ()
    metadata: dict = field(default_factory=dict)
    error: str = ""


def _finite(value):
    return isinstance(value, (int, float)) and not isinstance(value, bool) and math.isfinite(value)


def _pack(message):
    return f"~m~{len(message)}~m~{message}"


def _tv_send(ws, method, params):
    ws.send(_pack(json.dumps({"m": method, "p": params}, separators=(",", ":"))))


def _parse_packets(raw):
    if not isinstance(raw, str):
        return []
    packets, pos = [], 0
    while pos < len(raw):
        match = re.match(r"~m~(\d+)~m~", raw[pos:])
        if not match:
            break
        start = pos + match.end()
        end = start + int(match.group(1))
        if end > len(raw):
            break
        packets.append(raw[start:end])
        pos = end
    return packets


def _extract_candles(params):
    if not isinstance(params, list):
        return []
    candles = []
    for param in params:
        if not isinstance(param, dict):
            continue
        for value in param.values():
            bars = value.get("s", []) if isinstance(value, dict) else value
            if not isinstance(bars, list):
                continue
            for bar in bars:
                values = bar.get("v") if isinstance(bar, dict) else None
                if isinstance(values, list) and len(values) >= 5:
                    candles.append(dict(zip(
                        ("time", "open", "high", "low", "close", "volume"),
                        values[:5] + [values[5] if len(values) > 5 else None],
                    )))
    return candles


def _connect(*args, **kwargs):
    from websockets.sync.client import connect
    return connect(*args, **kwargs)


def fetch_tv_series(symbol, interval, n_bars=151, timeout=12, *, connector=None):
    """Complete a private chart session within timeout; never share chart state."""
    if interval not in TF_SECONDS or not 1 <= n_bars <= 1500 or not 0 < timeout <= 60:
        raise ValueError("invalid_probe_parameters")
    try:
        from websockets.exceptions import WebSocketException
    except ImportError:
        if connector is None:
            return TradingViewSeries(error="missing_websockets_dependency")
        # Offline tests can inject a transport without network dependencies.
        WebSocketException = OSError
    chart = "cs_" + secrets.token_hex(6)
    candles, metadata = [], {}
    deadline = time.monotonic() + timeout
    try:
        with (connector or _connect)(TV_WS_URL, origin="https://www.tradingview.com", open_timeout=timeout, close_timeout=1) as ws:
            _tv_send(ws, "set_auth_token", ["unauthorized_user_token"])
            _tv_send(ws, "chart_create_session", [chart, ""])
            _tv_send(ws, "switch_timezone", [chart, "Etc/UTC"])
            _tv_send(ws, "resolve_symbol", [chart, "sds_sym_1", "=" + json.dumps({"symbol": symbol, "adjustment": "splits", "session": "regular"})])
            _tv_send(ws, "create_series", [chart, "sds_1", "s1", "sds_sym_1", interval, n_bars, ""])
            while time.monotonic() < deadline:
                for packet in _parse_packets(ws.recv(timeout=max(.001, deadline - time.monotonic()))):
                    if packet.startswith("~h~"):
                        ws.send(_pack(packet))
                        continue
                    try:
                        data = json.loads(packet)
                    except json.JSONDecodeError:
                        continue
                    if not isinstance(data, dict):
                        continue
                    method, params = data.get("m"), data.get("p", [])
                    if not isinstance(params, list):
                        return TradingViewSeries(error="malformed_provider_message")
                    if method == "symbol_resolved" and params and isinstance(params[-1], dict):
                        metadata = {key: params[-1].get(key) for key in ("pro_name", "timezone", "session", "type", "pricescale", "currency_code", "volume_type")}
                        if metadata.get("pro_name") != symbol:
                            return TradingViewSeries(error="provider_symbol_mismatch")
                    elif method in ("timescale_update", "du"):
                        candles.extend(_extract_candles(params))
                    elif method == "series_completed":
                        if not metadata:
                            return TradingViewSeries(error="provider_identity_unavailable")
                        if any(not _finite(bar["time"]) or bar["time"] != int(bar["time"]) for bar in candles):
                            return TradingViewSeries(error="invalid_provider_timestamp")
                        unique = {int(bar["time"]): bar for bar in candles}
                        ordered = tuple(unique[key] for key in sorted(unique))
                        return TradingViewSeries(ordered, metadata)
                    elif method in ("protocol_error", "critical_error", "symbol_error", "series_error"):
                        return TradingViewSeries(error=method)
    except TimeoutError:
        return TradingViewSeries(error="timeout_before_series_completed")
    except (OSError, WebSocketException) as error:
        return TradingViewSeries(error=f"connection_failed:{type(error).__name__}")
    return TradingViewSeries(error="timeout_before_series_completed")


def session_profile(symbol, metadata):
    if symbol.startswith("OANDA:") and metadata.get("timezone") == "America/New_York" and metadata.get("session") == "1700-1700":
        if symbol in {"OANDA:XAUUSD", "OANDA:XAGUSD"}:
            return "oanda_metals_ny"
        if metadata.get("type") == "forex":
            return "oanda_fx_ny"
    if symbol.startswith(("BITSTAMP:", "BINANCE:")) and metadata.get("timezone") in {"Etc/UTC", "UTC"} and metadata.get("session") == "24x7":
        return "crypto_utc"
    return ""


def validate_tv_series(series, interval, count, now_ts):
    """Select exact closed OHLCV and validate explicit provider session rules."""
    if series.error:
        return (), {"valid": False, "issues": [series.error], "count": 0}, ""
    profile = session_profile(str(series.metadata.get("pro_name", "")), series.metadata)
    if not profile:
        return (), {"valid": False, "issues": ["unsupported_market_session"], "count": 0}, ""
    closed = [bar for bar in series.candles if next_bar(bar["time"], TF_SECONDS[interval], profile) <= now_ts]
    selected = tuple(dict(zip(
        ("t", "o", "h", "l", "c", "v"),
        (int(bar["time"]), bar["open"], bar["high"], bar["low"], bar["close"], bar["volume"]),
    )) for bar in closed[-count:])
    check = validate_candle_history(list(selected), interval, count, now_ts=now_ts, session_profile=profile)
    if check["valid"] and not fresh_history(selected[-1]["t"], TF_SECONDS[interval], now_ts, profile):
        check = {"valid": False, "issues": ["stale_provider_history"], "count": len(selected)}
    return selected, check, profile


async def fetch_tradingview_mtf_history(*, symbol, execution_timeframe, now_ts):
    mode = _MODES.get(str(execution_timeframe))
    provider = TV_SYMBOL_MAP.get(symbol)
    source = f"tradingview:{provider or symbol}"
    if not mode or not provider:
        return TrustedMtfHistory(False, "unsupported_tradingview_market", source=source)
    # Existing UI aliases for USDT cannot become USD execution prices.
    if provider.endswith("USDT") and symbol.endswith("USD"):
        return TrustedMtfHistory(False, "quote_currency_mismatch_usd_usdt", source=source)
    histories, profile = [], ""
    for timeframe, count in required_mtf_datasets(mode):
        async with _limiter:
            series = await asyncio.to_thread(fetch_tv_series, provider, _WIRE[timeframe], count + 1)
        selected, check, profile = validate_tv_series(series, _WIRE[timeframe], count, now_ts)
        if not check["valid"]:
            return TrustedMtfHistory(False, f"invalid_{timeframe.lower()}:{','.join(check['issues'])}", source=source)
        histories.append(selected)
    suffix = "tick_volume" if provider.startswith("OANDA:") else "exchange_volume"
    is_open = market_open(now_ts, profile)
    return TrustedMtfHistory(
        is_open, "" if is_open else "market_closed", *histories,
        source=f"{source}:{suffix}", session_profile=profile,
    )
