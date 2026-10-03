"""
Day 3 FeatureEngine — pure Python SMC/ATR precompute.
Only a compact feature summary is sent to the LLM (no raw OHLCV dump).
"""
from __future__ import annotations

import re
from copy import deepcopy
from math import isfinite
from typing import Any

from market_sessions import aligned, expected_closure, next_bar

MACRO_WINDOW_BEFORE_SEC = 1800
MACRO_WINDOW_AFTER_SEC = 900


TF_INTERVAL_SEC = {
    "1": 60,
    "5": 300,
    "15": 900,
    "60": 3600,
    "240": 14400,
    "1440": 86400,
    "D": 86400,
    "1D": 86400,
}


def normalize_timeframe(tf: str) -> str:
    t = str(tf).strip()
    aliases = {
        "M5": "5",
        "M15": "15",
        "H1": "60",
        "H4": "240",
        "D": "1440",
        "D1": "1440",
        "1D": "1440",
    }
    return aliases.get(t.upper(), t)


def candle_interval_sec(timeframe: str) -> int:
    return TF_INTERVAL_SEC.get(normalize_timeframe(timeframe), 300)


def required_mtf_datasets(mode: str) -> tuple[tuple[str, int], tuple[str, int], tuple[str, int]]:
    matrix = {
        "scalping": (("M5", 120), ("M15", 120), ("H1", 150)),
        "day_trading": (("M15", 120), ("H1", 120), ("H4", 150)),
        "swing": (("H1", 120), ("H4", 120), ("D1", 150)),
    }
    if mode not in matrix:
        raise ValueError(f"Unsupported trading mode: {mode}")
    return matrix[mode]


def _symbol_currencies(symbol: str) -> set[str]:
    clean = "".join(character for character in str(symbol).upper() if character.isalnum())
    aliases = {
        "XAUUSD": {"XAU", "USD"},
        "XAGUSD": {"XAG", "USD"},
        "BTCUSD": {"BTC", "USD"},
        "ETHUSD": {"ETH", "USD"},
        "US30": {"USD"},
        "US100": {"USD"},
        "US500": {"USD"},
        "USOIL": {"USD"},
    }
    if clean in aliases:
        return aliases[clean]
    if len(clean) == 6:
        return {clean[:3], clean[3:]}
    return set()


def normalize_macro_events(
    events: list[dict],
    *,
    symbol: str,
    now_ts: int,
    max_source_age_sec: int = 900,
) -> dict[str, Any]:
    """Validate and filter provider events without inventing missing macro data."""
    relevant_currencies = _symbol_currencies(symbol)
    normalized: list[dict[str, Any]] = []
    stale_count = 0
    for raw in events or []:
        if not isinstance(raw, dict):
            continue
        try:
            event_id = str(raw["event_id"]).strip()
            source = str(raw["source"]).strip()
            title = str(raw["title"]).strip()
            event_time = int(raw["event_time"])
            retrieved_at = int(raw["retrieved_at"])
            impact = str(raw["impact"]).upper()
            currencies = {
                str(currency).upper()
                for currency in raw["currencies"]
                if isinstance(currency, str) and currency.strip()
            }
        except (KeyError, TypeError, ValueError):
            continue
        if (
            not event_id
            or not source
            or not title
            or event_time <= 0
            or retrieved_at <= 0
            or impact not in {"LOW", "MEDIUM", "HIGH"}
            or not currencies
        ):
            continue
        source_age = now_ts - retrieved_at
        if source_age < -60 or source_age > max(1, max_source_age_sec):
            stale_count += 1
            continue
        if relevant_currencies and currencies.isdisjoint(relevant_currencies):
            continue
        normalized.append({
            "event_id": event_id,
            "title": title,
            "source": source,
            "event_time": event_time,
            "impact": impact,
            "currencies": sorted(currencies),
            "freshness_sec": max(0, source_age),
            "seconds_to_event": event_time - now_ts,
            "provenance": {
                "source": source,
                "source_id": event_id,
                "timestamp": event_time,
            },
        })
    normalized.sort(key=lambda event: (event["event_time"], event["event_id"]))
    status = "AVAILABLE" if normalized else "STALE" if stale_count else "UNAVAILABLE"
    label = {
        "AVAILABLE": "Macro events available",
        "STALE": "Macro data stale",
        "UNAVAILABLE": "Macro data unavailable",
    }[status]
    return {"status": status, "label": label, "events": normalized}


def evaluate_macro_risk_guard(
    macro: dict[str, Any],
    *,
    window_before_sec: int = MACRO_WINDOW_BEFORE_SEC,
    window_after_sec: int = MACRO_WINDOW_AFTER_SEC,
) -> dict[str, Any]:
    """Freeze entries around fresh, relevant HIGH-impact scheduled events."""
    status = str(macro.get("status") or "UNAVAILABLE").upper()
    label = str(macro.get("label") or "Macro data unavailable")
    if status != "AVAILABLE":
        return {"available": False, "veto": False, "veto_data": None, "label": label}
    for event in macro.get("events") or []:
        if not isinstance(event, dict) or event.get("impact") != "HIGH":
            continue
        try:
            seconds_to_event = int(event["seconds_to_event"])
        except (KeyError, TypeError, ValueError):
            continue
        if -max(0, window_after_sec) <= seconds_to_event <= max(0, window_before_sec):
            return {
                "available": True,
                "veto": True,
                "label": "HIGH-impact macro event window",
                "veto_data": {
                    "source": "macro",
                    "reason": "high_impact_news",
                    "event_id": event.get("event_id"),
                    "event_time": event.get("event_time"),
                    "currencies": deepcopy(event.get("currencies") or []),
                    "provenance": deepcopy(event.get("provenance")),
                },
            }
    return {"available": True, "veto": False, "veto_data": None, "label": label}


def _expected_market_closure(previous_ts: int, current_ts: int) -> bool:
    from datetime import datetime, timezone

    previous = datetime.fromtimestamp(previous_ts, timezone.utc)
    current = datetime.fromtimestamp(current_ts, timezone.utc)
    return previous.weekday() == 4 and current.weekday() in {6, 0} and current_ts - previous_ts <= 3 * 86400


def validate_candle_history(
    candles: list[dict],
    timeframe: str,
    expected_count: int,
    *,
    now_ts: float | None = None,
    session_profile: str = "utc",
) -> dict[str, Any]:
    """Validate exact, closed, ordered OHLCV history before analysis."""
    import time as _time

    issues: list[str] = []

    def issue(name: str) -> None:
        if name not in issues:
            issues.append(name)

    if len(candles) != expected_count:
        issue(f"expected_{expected_count}_candles")
    interval = candle_interval_sec(timeframe)
    timestamps: list[int] = []
    volumes: list[float] = []
    for candle in candles:
        if not isinstance(candle, dict):
            issue("invalid_ohlcv")
            continue
        if "v" not in candle and "volume" not in candle:
            issue("missing_volume")
        try:
            timestamp = int(candle.get("t") or 0)
            open_price = float(candle["o"])
            high = float(candle["h"])
            low = float(candle["l"])
            close = float(candle["c"])
            volume = float(candle.get("v") if "v" in candle else candle.get("volume"))
        except (KeyError, TypeError, ValueError):
            issue("invalid_ohlcv")
            continue
        timestamps.append(timestamp)
        volumes.append(volume)
        if (
            timestamp <= 0
            or not all(isfinite(value) for value in (open_price, high, low, close, volume))
            or high < max(open_price, close)
            or low > min(open_price, close)
            or high < low
            or volume < 0
        ):
            issue("invalid_ohlcv")
        if not aligned(timestamp, interval, session_profile):
            issue("timestamp_not_aligned")

    if timestamps != sorted(set(timestamps)):
        issue("timestamps_not_strictly_increasing")
    else:
        for previous, current in zip(timestamps, timestamps[1:]):
            valid_gap = (
                _expected_market_closure(previous, current)
                if session_profile == "utc"
                else expected_closure(previous, current, interval, session_profile)
            )
            if current != next_bar(previous, interval, session_profile) and not valid_gap:
                issue("unexpected_gap")
                break
    now = float(now_ts if now_ts is not None else _time.time())
    if volumes and all(volume == 0 for volume in volumes):
        issue("volume_unavailable")
    if timestamps and next_bar(timestamps[-1], interval, session_profile) > now:
        issue("forming_candle_present")
    return {"valid": not issues, "issues": issues, "count": len(candles)}


def last_closed_candle_timestamp(
    candles: list[dict],
    timeframe: str,
    now_ts: float | None = None,
    session_profile: str = "utc",
) -> int:
    """Open-time of the last *closed* candle (excludes the forming bar when possible)."""
    import time as _time

    interval = candle_interval_sec(timeframe)
    now = float(now_ts if now_ts is not None else _time.time())
    if not candles:
        return int(now // interval) * interval - interval

    ordered = sorted(candles, key=lambda c: int(c.get("t", 0)))
    last = ordered[-1]
    last_t = int(last.get("t", 0))
    if next_bar(last_t, interval, session_profile) <= now + 1:
        return last_t
    if len(ordered) >= 2:
        return int(ordered[-2].get("t", last_t))
    return last_t


def _atr(candles: list[dict], period: int = 14) -> float:
    if len(candles) < 2:
        return 0.0
    trs: list[float] = []
    prev_close = float(candles[0]["c"])
    for c in candles[1:]:
        h, l, cl = float(c["h"]), float(c["l"]), float(c["c"])
        tr = max(h - l, abs(h - prev_close), abs(l - prev_close))
        trs.append(tr)
        prev_close = cl
    if not trs:
        return 0.0
    window = trs[-period:] if len(trs) >= period else trs
    return sum(window) / len(window)


def _swing_points(candles: list[dict], left: int = 2, right: int = 2) -> tuple[list[dict], list[dict]]:
    highs: list[dict] = []
    lows: list[dict] = []
    n = len(candles)
    for i in range(left, n - right):
        h = float(candles[i]["h"])
        l = float(candles[i]["l"])
        is_sh = all(h >= float(candles[j]["h"]) for j in range(i - left, i + right + 1) if j != i)
        is_sl = all(l <= float(candles[j]["l"]) for j in range(i - left, i + right + 1) if j != i)
        if is_sh:
            highs.append({"t": int(candles[i]["t"]), "price": round(h, 5)})
        if is_sl:
            lows.append({"t": int(candles[i]["t"]), "price": round(l, 5)})
    return highs[-8:], lows[-8:]


def _detect_fvgs(candles: list[dict], limit: int = 5) -> list[dict]:
    """3-candle Fair Value Gaps (bullish: c0.high < c2.low; bearish: c0.low > c2.high)."""
    out: list[dict] = []
    for i in range(2, len(candles)):
        c0, c2 = candles[i - 2], candles[i]
        h0, l0 = float(c0["h"]), float(c0["l"])
        h2, l2 = float(c2["h"]), float(c2["l"])
        if h0 < l2:
            out.append({
                "bias": "bullish",
                "top": round(l2, 5),
                "bottom": round(h0, 5),
                "t": int(c2["t"]),
            })
        elif l0 > h2:
            out.append({
                "bias": "bearish",
                "top": round(l0, 5),
                "bottom": round(h2, 5),
                "t": int(c2["t"]),
            })
    return out[-limit:]


def _detect_order_blocks(candles: list[dict], atr: float, limit: int = 3) -> list[dict]:
    """Heuristic OB: last opposite candle before an impulsive move (>= 1.2 ATR body)."""
    if len(candles) < 4 or atr <= 0:
        return []
    obs: list[dict] = []
    for i in range(3, len(candles)):
        c = candles[i]
        body = abs(float(c["c"]) - float(c["o"]))
        if body < atr * 1.2:
            continue
        bullish_impulse = float(c["c"]) > float(c["o"])
        prev = candles[i - 1]
        # Prefer opposite-color predecessor as OB
        prev_bull = float(prev["c"]) >= float(prev["o"])
        if bullish_impulse and not prev_bull:
            obs.append({
                "bias": "bullish",
                "top": round(max(float(prev["o"]), float(prev["c"])), 5),
                "bottom": round(min(float(prev["o"]), float(prev["c"]), float(prev["l"])), 5),
                "t_start": int(prev["t"]),
                "t_end": int(c["t"]),
            })
        elif (not bullish_impulse) and prev_bull:
            obs.append({
                "bias": "bearish",
                "top": round(max(float(prev["o"]), float(prev["c"]), float(prev["h"])), 5),
                "bottom": round(min(float(prev["o"]), float(prev["c"])), 5),
                "t_start": int(prev["t"]),
                "t_end": int(c["t"]),
            })
    return obs[-limit:]


def _structure_events(
    swing_highs: list[dict],
    swing_lows: list[dict],
    *,
    displacement: bool = False,
) -> dict[str, Any]:
    """Deterministic BOS/CHOCH from successive swing breaks."""
    events: list[dict] = []
    trend = "Neutral"
    last_bos = None
    last_choch = None

    sh = swing_highs[-4:]
    sl = swing_lows[-4:]
    has_pair = len(sh) >= 2 and len(sl) >= 2
    higher_high = has_pair and sh[-1]["price"] > sh[-2]["price"]
    lower_high = has_pair and sh[-1]["price"] < sh[-2]["price"]
    higher_low = has_pair and sl[-1]["price"] > sl[-2]["price"]
    lower_low = has_pair and sl[-1]["price"] < sl[-2]["price"]

    prior_bullish = (
        len(sh) >= 3
        and len(sl) >= 3
        and sh[-2]["price"] > sh[-3]["price"]
        and sl[-2]["price"] > sl[-3]["price"]
    )
    prior_bearish = (
        len(sh) >= 3
        and len(sl) >= 3
        and sh[-2]["price"] < sh[-3]["price"]
        and sl[-2]["price"] < sl[-3]["price"]
    )
    if prior_bullish and lower_low:
        last_choch = "bearish"
        events.append({
            "type": "MSS" if displacement else "CHOCH",
            "bias": "bearish",
            "time_start": sl[-2]["t"],
            "price_start": sl[-2]["price"],
            "time_end": sl[-1]["t"],
            "price_end": sl[-1]["price"],
        })
        trend = "Bearish"
    elif prior_bearish and higher_high:
        last_choch = "bullish"
        events.append({
            "type": "MSS" if displacement else "CHOCH",
            "bias": "bullish",
            "time_start": sh[-2]["t"],
            "price_start": sh[-2]["price"],
            "time_end": sh[-1]["t"],
            "price_end": sh[-1]["price"],
        })
        trend = "Bullish"
    elif higher_high and higher_low:
        last_bos = "bullish"
        events.append({
            "type": "BOS",
            "bias": "bullish",
            "time_start": sh[-2]["t"],
            "price_start": sh[-2]["price"],
            "time_end": sh[-1]["t"],
            "price_end": sh[-1]["price"],
        })
        trend = "Bullish"
    elif lower_high and lower_low:
        last_bos = "bearish"
        events.append({
            "type": "BOS",
            "bias": "bearish",
            "time_start": sl[-2]["t"],
            "price_start": sl[-2]["price"],
            "time_end": sl[-1]["t"],
            "price_end": sl[-1]["price"],
        })
        trend = "Bearish"

    return {
        "trend": trend,
        "last_bos": last_bos,
        "last_choch": last_choch,
        "events": events[-4:],
    }


def compute_vsa_features(candles: list[dict]) -> dict[str, Any]:
    """Return only VSA evidence measured from the latest closed candle."""
    empty = {
        "volume_baseline": 0,
        "volume_spike": False,
        "candle_overrides": [],
        "liquidity_markers": [],
    }
    if len(candles) < 4:
        return empty

    current = candles[-1]
    prior = candles[max(0, len(candles) - 21):-1]
    prior_volumes = [float(c.get("v") or 0) for c in prior]
    if not prior_volumes or any(v <= 0 for v in prior_volumes):
        return empty

    volume_baseline = sum(prior_volumes) / len(prior_volumes)
    current_volume = float(current.get("v") or 0)
    volume_spike = current_volume >= 3 * volume_baseline
    prior_spreads = [float(c["h"]) - float(c["l"]) for c in prior]
    spread_baseline = sum(prior_spreads) / len(prior_spreads)
    current_spread = float(current["h"]) - float(current["l"])
    spread_alert = spread_baseline > 0 and current_spread >= 2 * spread_baseline
    candle_time = int(current.get("t") or 0)
    is_up = float(current["c"]) > float(current["o"])
    is_down = float(current["c"]) < float(current["o"])

    result: dict[str, Any] = {
        "volume_baseline": round(volume_baseline, 5),
        "volume_spike": volume_spike,
        "candle_overrides": [],
        "liquidity_markers": [],
    }
    override: dict[str, Any] = {"candle_time": candle_time}
    candle_evidence = {
        "source": "candle",
        "source_id": f"VSA:{candle_time}",
        "timestamp": max(1, candle_time),
    }
    if volume_spike and (is_up or is_down):
        confirmation_type = "buying_climax" if is_up else "selling_climax"
        result["confirmation"] = {"type": confirmation_type, "candle_time": candle_time}
        override.update({
            "kind": "climax",
            "fill_color": "#8A2BE2",
            "label_bottom": "STOP",
            "evidence": candle_evidence,
        })
        result["liquidity_markers"].append({
            "kind": "stop_marker",
            "text": "STOP",
            "color": "#8A2BE2",
            "time_x": candle_time,
            "price_y": float(current["h"] if is_up else current["l"]),
            "evidence": candle_evidence,
        })
    elif (
        current_volume <= 0.7 * volume_baseline
        and spread_baseline > 0
        and current_spread <= 0.7 * spread_baseline
        and (is_up or is_down)
    ):
        override.update({
            "kind": "no_demand" if is_up else "no_supply",
            "fill_color": "#FFFFFF",
            "label_bottom": "ND" if is_up else "NS",
            "evidence": candle_evidence,
        })
    if spread_alert:
        override["kind"] = override.get("kind") or "spread_alert"
        override["border_color"] = "#FFD700"
        override["spread_alert"] = True
        override["evidence"] = candle_evidence
    previous = candles[-2]
    previous_volume = float(previous.get("v") or 0)
    lower_low = float(current["l"]) < float(previous["l"])
    higher_high = float(current["h"]) > float(previous["h"])
    if current_volume < previous_volume and lower_low != higher_high:
        bullish_divergence = lower_low
        override["kind"] = override.get("kind") or "volume_divergence"
        override["divergence_direction"] = "up" if bullish_divergence else "down"
        override["divergence_color"] = "#00FF7F" if bullish_divergence else "#FF3B30"
        override["evidence"] = candle_evidence
    if len(override) > 1:
        result["candle_overrides"].append(override)
    return result


def detect_confirmation(candles: list[dict]) -> dict[str, Any] | None:
    """Detect an approved confirmation pattern on the latest closed candle."""
    if not candles:
        return None
    current = candles[-1]
    current_open = float(current["o"])
    current_close = float(current["c"])
    candle_time = int(current.get("t") or 0)

    if len(candles) >= 2:
        previous = candles[-2]
        previous_open = float(previous["o"])
        previous_close = float(previous["c"])
        bullish_engulfing = (
            previous_close < previous_open
            and current_close > current_open
            and current_open <= previous_close
            and current_close >= previous_open
        )
        bearish_engulfing = (
            previous_close > previous_open
            and current_close < current_open
            and current_open >= previous_close
            and current_close <= previous_open
        )
        if bullish_engulfing or bearish_engulfing:
            return {
                "type": "bullish_engulfing" if bullish_engulfing else "bearish_engulfing",
                "candle_time": candle_time,
            }

    high = float(current["h"])
    low = float(current["l"])
    candle_range = high - low
    if candle_range <= 0:
        return None
    body_high = max(current_open, current_close)
    body_low = min(current_open, current_close)
    body_ratio = abs(current_close - current_open) / candle_range
    upper_wick_ratio = (high - body_high) / candle_range
    lower_wick_ratio = (body_low - low) / candle_range
    if body_ratio <= 0.3 and lower_wick_ratio >= 0.6 and upper_wick_ratio <= 0.2:
        return {"type": "bullish_pinbar", "candle_time": candle_time}
    if body_ratio <= 0.3 and upper_wick_ratio >= 0.6 and lower_wick_ratio <= 0.2:
        return {"type": "bearish_pinbar", "candle_time": candle_time}
    return None


def detect_wyckoff_phase(
    candles: list[dict],
    vsa: dict[str, Any],
) -> dict[str, Any] | None:
    """Identify only an unambiguous, high-volume Phase C spring/upthrust."""
    if len(candles) < 21 or not bool(vsa.get("volume_spike")):
        return None
    current = candles[-1]
    prior = candles[-21:-1]
    support = min(float(candle["l"]) for candle in prior)
    resistance = max(float(candle["h"]) for candle in prior)
    low = float(current["l"])
    high = float(current["h"])
    close = float(current["c"])
    spring = low < support and close > support
    upthrust = high > resistance and close < resistance
    if spring == upthrust:
        return None
    candle_time = int(current.get("t") or 0)
    event = "SPRING" if spring else "UPTHRUST"
    return {
        "phase": "PHASE C",
        "event": event,
        "evidence": {
            "source": "candle",
            "source_id": f"WYCKOFF:{candle_time}:{event}",
            "timestamp": max(1, candle_time),
        },
    }


def compute_features(
    symbol: str,
    timeframe: str,
    candles: list[dict],
    current_price: float,
    now_ts: float | None = None,
    session_profile: str = "utc",
) -> dict[str, Any]:
    """Build compact technical summary for LLM / rule-based fallback."""
    ordered = sorted(candles, key=lambda c: int(c.get("t", 0))) if candles else []
    # Prefer closed candles for structure (drop forming bar when present)
    interval = candle_interval_sec(timeframe)
    import time as _time
    now = float(now_ts if now_ts is not None else _time.time())
    closed = [c for c in ordered if next_bar(int(c.get("t", 0)), interval, session_profile) <= now + 1]
    if len(closed) < 5:
        closed = ordered

    atr = round(_atr(closed, 14), 5)
    swing_highs, swing_lows = _swing_points(closed)
    fvgs = _detect_fvgs(closed)
    order_blocks = _detect_order_blocks(closed, atr if atr > 0 else 1.0)
    latest_body = abs(float(closed[-1]["c"]) - float(closed[-1]["o"])) if closed else 0
    structure = _structure_events(
        swing_highs,
        swing_lows,
        displacement=atr > 0 and latest_body >= atr * 1.2,
    )
    vsa = compute_vsa_features(closed)
    if "confirmation" not in vsa:
        confirmation = detect_confirmation(closed)
        if confirmation:
            vsa["confirmation"] = confirmation
    wyckoff_phase = detect_wyckoff_phase(closed, vsa)
    if wyckoff_phase:
        vsa["wyckoff_phase"] = wyckoff_phase

    bias = "BUY" if structure["trend"] == "Bullish" else "SELL" if structure["trend"] == "Bearish" else "NEUTRAL"
    if structure.get("last_choch") == "bullish":
        bias = "BUY"
    elif structure.get("last_choch") == "bearish":
        bias = "SELL"

    last_closed_ts = last_closed_candle_timestamp(ordered, timeframe, now_ts=now, session_profile=session_profile)
    price = float(current_price) if current_price and current_price > 0 else (
        float(closed[-1]["c"]) if closed else 0.0
    )

    return {
        "symbol": symbol,
        "timeframe": normalize_timeframe(timeframe),
        "last_closed_candle_timestamp": last_closed_ts,
        "candle_interval_sec": interval,
        "current_price": round(price, 5),
        "atr": atr,
        "swing_highs": swing_highs,
        "swing_lows": swing_lows,
        "order_blocks": order_blocks,
        "fvgs": fvgs,
        "structure": structure,
        "bias": bias,
        "candle_count_used": len(closed),
        **vsa,
    }


def features_prompt_block(features: dict[str, Any]) -> str:
    """Compact text block for the LLM — never dump raw candles."""
    return (
        f"SYMBOL: {features.get('symbol')}\n"
        f"TIMEFRAME: {features.get('timeframe')}\n"
        f"LAST_CLOSED_TS: {features.get('last_closed_candle_timestamp')}\n"
        f"CURRENT_PRICE: {features.get('current_price')}\n"
        f"ATR(14): {features.get('atr')}\n"
        f"BIAS: {features.get('bias')}\n"
        f"STRUCTURE: {features.get('structure')}\n"
        f"SWING_HIGHS: {features.get('swing_highs')}\n"
        f"SWING_LOWS: {features.get('swing_lows')}\n"
        f"ORDER_BLOCKS: {features.get('order_blocks')}\n"
        f"FVGS: {features.get('fvgs')}\n"
        f"SETUP_READY: {features.get('setup_ready')}\n"
        f"VETO: {features.get('veto')}\n"
        f"VETO_DATA: {features.get('veto_data')}\n"
        f"HTF1: {features.get('htf1')}\n"
        f"HTF2: {features.get('htf2')}\n"
    )


# ─── Day 4: MTF resample + setup_ready / HTF veto ─────────────

# Higher TF relative to execution TF (interval seconds → HTF1, HTF2)
_HTF_LADDER = ["1", "5", "15", "60", "240", "1440"]


def htf_pair_for_execution(timeframe: str) -> tuple[str, str]:
    tf = normalize_timeframe(timeframe)
    if tf not in _HTF_LADDER:
        return "60", "240"
    i = _HTF_LADDER.index(tf)
    h1 = _HTF_LADDER[min(i + 1, len(_HTF_LADDER) - 1)]
    h2 = _HTF_LADDER[min(i + 2, len(_HTF_LADDER) - 1)]
    if h1 == tf:
        h1 = _HTF_LADDER[min(i + 1, len(_HTF_LADDER) - 1)]
    return h1, h2


def aggregate_candles(candles: list[dict], from_tf: str, to_tf: str) -> list[dict]:
    """Resample OHLCV into timestamp-aligned timeframe buckets."""
    src = candle_interval_sec(from_tf)
    dst = candle_interval_sec(to_tf)
    if dst <= src or not candles:
        return list(candles)
    ordered = sorted(candles, key=lambda c: int(c.get("t", 0)))
    buckets: dict[int, dict] = {}
    for candle in ordered:
        timestamp = int(candle.get("t", 0))
        if timestamp <= 0:
            continue
        bucket_time = (timestamp // dst) * dst
        volume = float(candle.get("v") or candle.get("volume") or 0)
        bucket = buckets.get(bucket_time)
        if bucket is None:
            buckets[bucket_time] = {
                "t": bucket_time,
                "o": float(candle["o"]),
                "h": float(candle["h"]),
                "l": float(candle["l"]),
                "c": float(candle["c"]),
                "v": volume,
            }
            continue
        bucket["h"] = max(float(bucket["h"]), float(candle["h"]))
        bucket["l"] = min(float(bucket["l"]), float(candle["l"]))
        bucket["c"] = float(candle["c"])
        bucket["v"] = float(bucket["v"]) + volume
    return [buckets[key] for key in sorted(buckets)]


def _price_in_zone(price: float, top: float, bottom: float, pad: float = 0.0) -> bool:
    lo, hi = min(bottom, top) - pad, max(bottom, top) + pad
    return lo <= price <= hi


def aggregate_specialist_votes(outputs: list[dict]) -> dict[str, Any]:
    """Aggregate exactly one SMC, VSA, and Macro vote without LLM discretion."""
    expected_agents = {"smc", "vsa", "macro"}
    evidence_reference = re.compile(r"^[A-Za-z0-9._:-]{1,160}$")
    votes: list[dict[str, Any]] = []
    for index, raw in enumerate(outputs or []):
        if not isinstance(raw, dict):
            raw = {}
        agent = str(raw.get("agent") or f"unknown_{index}").lower()
        decision = str(raw.get("decision") or "WAIT").upper()
        if decision not in {"BUY", "SELL", "WAIT"}:
            decision = "WAIT"
        try:
            confidence = max(0.0, min(100.0, float(raw.get("confidence") or 0)))
        except (TypeError, ValueError):
            confidence = 0.0
        raw_evidence = raw.get("evidence")
        evidence = (
            [
                item
                for item in raw_evidence[:8]
                if isinstance(item, str) and evidence_reference.fullmatch(item)
            ]
            if isinstance(raw_evidence, list)
            else []
        )
        votes.append({
            "agent": agent,
            "decision": decision,
            "confidence": confidence,
            "reason": str(raw.get("reason") or "")[:500],
            "evidence": evidence,
        })

    complete = len(votes) == 3 and {vote["agent"] for vote in votes} == expected_agents
    counts = {
        direction: sum(1 for vote in votes if vote["decision"] == direction)
        for direction in ("BUY", "SELL", "WAIT")
    }
    max_count = max(counts.values(), default=0)
    leaders = [direction for direction, count in counts.items() if count == max_count]
    leading = leaders[0] if len(leaders) == 1 else "WAIT"
    agreement = round((max_count / 3) * 100, 2) if complete else 0.0
    decision = leading if complete and leading in {"BUY", "SELL"} and agreement >= 75 else "WAIT"
    return {
        "complete": complete,
        "votes": votes,
        "counts": counts,
        "leading_direction": leading,
        "agreement_percent": agreement,
        "decision": decision,
    }


def evaluate_setup_and_veto(
    exec_features: dict[str, Any],
    htf1_features: dict[str, Any] | None = None,
    htf2_features: dict[str, Any] | None = None,
) -> dict[str, Any]:
    """
    Soft vs Hard (setup_ready) + HTF supply/demand veto.
    Deterministic — no RNG.
    """
    price = float(exec_features.get("current_price") or 0)
    atr = float(exec_features.get("atr") or 0) or max(price * 0.001, 1e-6)
    bias = exec_features.get("bias", "NEUTRAL")
    directional = bias in {"BUY", "SELL"}
    pad = atr * 0.35

    zones = list(exec_features.get("order_blocks") or []) + list(exec_features.get("fvgs") or [])
    zone_touched = False
    touch_zone = None
    for z in zones:
        z_bias = z.get("bias")
        want = "bullish" if bias == "BUY" else "bearish"
        if z_bias != want:
            continue
        top, bottom = float(z.get("top", 0)), float(z.get("bottom", 0))
        if _price_in_zone(price, top, bottom, pad=pad):
            zone_touched = True
            touch_zone = z
            break

    confirmation = exec_features.get("confirmation")
    confirmation_type = (
        str(confirmation.get("type", "")).lower()
        if isinstance(confirmation, dict)
        else ""
    )
    raw_confirmation_time = (
        confirmation.get("candle_time", confirmation.get("t"))
        if isinstance(confirmation, dict)
        else None
    )
    confirmation_time = (
        raw_confirmation_time
        if isinstance(raw_confirmation_time, int)
        and not isinstance(raw_confirmation_time, bool)
        and raw_confirmation_time > 0
        else None
    )
    allowed_confirmations = {
        "bullish_pinbar",
        "bearish_pinbar",
        "bullish_engulfing",
        "bearish_engulfing",
        "buying_climax",
        "selling_climax",
    }
    expected_prefix = "bullish" if bias == "BUY" else "bearish"
    confirmation_ready = (
        confirmation_type in allowed_confirmations
        and confirmation_time is not None
        and (
            confirmation_type.startswith(expected_prefix)
            or confirmation_type == ("buying_climax" if bias == "BUY" else "selling_climax")
        )
    )
    confirmation_evidence = (
        {"type": confirmation_type, "candle_time": confirmation_time}
        if confirmation_ready
        else None
    )
    consensus_audit = None
    if "specialist_outputs" in exec_features:
        consensus_audit = aggregate_specialist_votes(exec_features.get("specialist_outputs") or [])
        consensus_percent = float(consensus_audit["agreement_percent"])
        consensus_ready = (
            consensus_audit["complete"]
            and consensus_percent >= 75.0
            and consensus_audit["decision"] == bias
        )
    else:
        try:
            consensus_percent = float(exec_features.get("consensus_percent") or 0)
        except (TypeError, ValueError):
            consensus_percent = 0.0
        consensus_ready = consensus_percent >= 75.0
    supplied_htfs = [htf for htf in (htf1_features, htf2_features) if htf is not None]
    execution_ready = (
        bool(exec_features["history_valid"])
        if "history_valid" in exec_features
        else True
    )
    mtf_ready = execution_ready and (not supplied_htfs or (
        len(supplied_htfs) == 2 and all(bool(htf.get("history_valid")) for htf in supplied_htfs)
    ))
    setup_ready = directional and zone_touched and confirmation_ready and consensus_ready and mtf_ready

    veto = False
    veto_data: dict[str, Any] | None = None
    for label, htf in (("htf1", htf1_features), ("htf2", htf2_features)):
        if not htf or not bool(htf.get("history_valid")):
            continue
        for z in (htf.get("order_blocks") or []):
            z_bias = z.get("bias")
            # Opposing HTF OB that currently contains price → freeze
            opposing = (bias == "BUY" and z_bias == "bearish") or (bias == "SELL" and z_bias == "bullish")
            if not opposing:
                continue
            top, bottom = float(z.get("top", 0)), float(z.get("bottom", 0))
            if _price_in_zone(price, top, bottom, pad=atr * 0.15):
                veto = True
                veto_data = {
                    "source": label,
                    "reason": "htf_opposing_order_block",
                    "htf_tf": htf.get("timeframe"),
                    "conflict_timeframe": htf.get("timeframe"),
                    "zone": z,
                    "danger_zone": {
                        "top": max(top, bottom),
                        "bottom": min(top, bottom),
                        "bias": z_bias,
                    },
                    "bias": bias,
                }
                break
        if veto:
            break

    macro_guard = exec_features.get("macro_risk_guard")
    if not veto and isinstance(macro_guard, dict) and macro_guard.get("veto") is True:
        macro_veto_data = macro_guard.get("veto_data")
        if isinstance(macro_veto_data, dict):
            veto = True
            veto_data = deepcopy(macro_veto_data)

    if veto:
        setup_ready = False

    final_decision = "VETO" if veto else "HARD_SETUP" if setup_ready else "SOFT_ALERT"

    return {
        "setup_ready": setup_ready,
        "veto": veto,
        "veto_data": veto_data,
        "touch_zone": touch_zone,
        "zone_touched": zone_touched,
        "confirmation_ready": confirmation_ready,
        "confirmation_evidence": confirmation_evidence,
        "consensus_ready": consensus_ready,
        "consensus_percent": consensus_percent,
        "consensus_audit": consensus_audit,
        "mtf_ready": mtf_ready,
        "final_decision": final_decision,
    }


def strip_layer4(layers: list) -> list:
    """Remove execution layer for Soft stage / Veto."""
    out = []
    for layer in layers or []:
        if isinstance(layer, dict) and int(layer.get("layer", -1)) == 4:
            continue
        out.append(layer)
    return out


def apply_stage_gates(signal: dict[str, Any], gate: dict[str, Any]) -> dict[str, Any]:
    """Mutate signal for 2-stage + veto (FE must not paint Entry when soft/vetoed)."""
    out = dict(signal)
    veto = bool(gate.get("veto"))
    setup_ready = bool(gate.get("setup_ready")) and not veto
    out["setup_ready"] = setup_ready
    out["veto"] = veto
    out["veto_data"] = gate.get("veto_data")
    if not setup_ready or veto:
        out["layers"] = strip_layer4(out.get("layers") or [])
        # Fail closed: waiting/veto signals must not carry executable prices.
        out["entryPrice"] = None
        out["slPrice"] = None
        out["tpPrices"] = []
        out["suggestedLot"] = None
        out["forecast_text"] = (
            "VETO: HTF opposing supply/demand — entry frozen."
            if veto
            else "SOFT ALERT: waiting for price to tap OB/FVG zone (setup_ready=false)."
        )
    return out


def is_executable_signal(signal: dict[str, Any]) -> bool:
    """Return True only for a complete Hard Setup that is safe to execute/alert."""
    if not bool(signal.get("setup_ready")) or bool(signal.get("veto")):
        return False
    try:
        entry = float(signal.get("entryPrice") or 0)
        stop = float(signal.get("slPrice") or 0)
        targets = [float(value) for value in (signal.get("tpPrices") or [])]
    except (TypeError, ValueError):
        return False
    direction = str(signal.get("type") or "").upper()
    if entry <= 0 or stop <= 0 or len(targets) != 3 or not all(value > 0 for value in targets):
        return False
    if direction == "BUY":
        risk = entry - stop
        reward = targets[0] - entry
    elif direction == "SELL":
        risk = stop - entry
        reward = entry - targets[0]
    else:
        return False
    return risk > 0 and reward / risk >= 2.0


_USER_SPECIFIC_ANALYSIS_KEYS = {
    "account_context",
    "balance",
    "equity",
    "freeMargin",
    "risk_percent",
    "riskPercent",
    "suggestedLot",
    "uid",
    "userId",
}


def market_analysis_features(features: dict[str, Any]) -> dict[str, Any]:
    """Copy only user-neutral inputs that are safe to share under a market cache key."""
    return {
        key: deepcopy(value)
        for key, value in features.items()
        if key not in _USER_SPECIFIC_ANALYSIS_KEYS
    }


def strip_user_specific_analysis(signal: dict[str, Any]) -> dict[str, Any]:
    """Remove user sizing from a market-analysis artifact before caching it."""
    clean = market_analysis_features(signal)
    layers = clean.get("layers")
    if isinstance(layers, list):
        for layer in layers:
            if isinstance(layer, dict):
                layer.pop("suggested_lot", None)
    return clean


def build_mtf_feature_pack(
    symbol: str,
    timeframe: str,
    candles_execution: list[dict],
    current_price: float,
    candles_htf_1: list[dict] | None = None,
    candles_htf_2: list[dict] | None = None,
    now_ts: float | None = None,
    session_profile: str = "utc",
) -> dict[str, Any]:
    """Execution + HTF1/HTF2 features; HTF candles resampled if not provided."""
    htf1_tf, htf2_tf = htf_pair_for_execution(timeframe)
    exec_f = compute_features(symbol, timeframe, candles_execution, current_price, now_ts=now_ts, session_profile=session_profile)

    c1 = candles_htf_1 if candles_htf_1 else aggregate_candles(candles_execution, timeframe, htf1_tf)
    c2 = candles_htf_2 if candles_htf_2 else aggregate_candles(candles_execution, timeframe, htf2_tf)
    htf1_f = compute_features(symbol, htf1_tf, c1, current_price, now_ts=now_ts, session_profile=session_profile) if c1 else None
    htf2_f = compute_features(symbol, htf2_tf, c2, current_price, now_ts=now_ts, session_profile=session_profile) if c2 else None

    exec_validation = validate_candle_history(candles_execution, timeframe, 120, now_ts=now_ts, session_profile=session_profile)
    htf1_validation = validate_candle_history(c1, htf1_tf, 120, now_ts=now_ts, session_profile=session_profile)
    htf2_validation = validate_candle_history(c2, htf2_tf, 150, now_ts=now_ts, session_profile=session_profile)
    exec_f["history_valid"] = exec_validation["valid"]

    if htf1_f is not None:
        htf1_f["history_valid"] = htf1_validation["valid"]
    if htf2_f is not None:
        htf2_f["history_valid"] = htf2_validation["valid"]

    gate = evaluate_setup_and_veto(exec_f, htf1_f, htf2_f)
    pack = dict(exec_f)
    pack["htf1"] = {
        "timeframe": htf1_tf,
        "bias": (htf1_f or {}).get("bias"),
        "structure": (htf1_f or {}).get("structure"),
        "order_blocks": (htf1_f or {}).get("order_blocks"),
        "atr": (htf1_f or {}).get("atr"),
        "history_valid": (htf1_f or {}).get("history_valid", False),
        "last_closed_candle_timestamp": (htf1_f or {}).get("last_closed_candle_timestamp"),
    } if htf1_f else None
    pack["htf2"] = {
        "timeframe": htf2_tf,
        "bias": (htf2_f or {}).get("bias"),
        "structure": (htf2_f or {}).get("structure"),
        "order_blocks": (htf2_f or {}).get("order_blocks"),
        "atr": (htf2_f or {}).get("atr"),
        "history_valid": (htf2_f or {}).get("history_valid", False),
        "last_closed_candle_timestamp": (htf2_f or {}).get("last_closed_candle_timestamp"),
    } if htf2_f else None
    pack["data_quality"] = {
        "execution": exec_validation,
        "htf1": htf1_validation,
        "htf2": htf2_validation,
    }
    pack["analysis_available"] = all(
        result["valid"]
        for result in (exec_validation, htf1_validation, htf2_validation)
    )
    pack.update(gate)
    return pack



def build_unavailable_signal(features: dict[str, Any]) -> dict[str, Any]:
    """Return a labeled non-analysis artifact when trusted MTF input is incomplete."""
    symbol = str(features.get("symbol") or "UNKNOWN")
    timeframe = str(features.get("timeframe") or "UNKNOWN")
    timestamp = int(features.get("last_closed_candle_timestamp") or 0)
    data_quality = deepcopy(features.get("data_quality") or {})
    issue_names = sorted({
        issue
        for result in data_quality.values()
        if isinstance(result, dict)
        for issue in (result.get("issues") or [])
    })
    reason = ", ".join(issue_names) if issue_names else "trusted_mtf_history_missing"
    return {
        "chart_id": f"{symbol}_{timeframe}_{timestamp}",
        "symbol": symbol,
        "type": "NEUTRAL",
        "entryPrice": None,
        "slPrice": None,
        "tpPrices": [],
        "probability": 0,
        "fallback": True,
        "setup_ready": False,
        "veto": False,
        "veto_data": None,
        "forecast_text": f"DATA UNAVAILABLE: {reason}",
        "data_quality": data_quality,
        "layers": [
            {"layer": 1, "type": "structural", "items": []},
            {"layer": 2, "type": "icon_text", "items": []},
            {"layer": 3, "type": "candle_color", "items": []},
            {"layer": 5, "type": "overlay", "items": []},
        ],
    }


def _digits_for_price(price: float) -> int:
    if price >= 100:
        return 2
    if price >= 10:
        return 3
    return 5


def build_signal_from_features(features: dict[str, Any]) -> dict[str, Any]:
    """Deterministic 5-layer signal — no random.*."""
    symbol = features.get("symbol", "XAUUSD")
    raw_bias = str(features.get("bias") or "NEUTRAL").upper()
    bias = raw_bias if raw_bias in {"BUY", "SELL"} else "NEUTRAL"
    is_buy = bias == "BUY"
    price = float(features.get("current_price") or 0)
    atr = float(features.get("atr") or 0) or max(price * 0.001, 0.01)
    interval = int(features.get("candle_interval_sec") or 300)
    t0 = int(features.get("last_closed_candle_timestamp") or 0)
    d = _digits_for_price(price)

    entry = round(price, d)
    touch_zone = features.get("touch_zone")
    setup_ready = (
        bias in {"BUY", "SELL"}
        and bool(features.get("setup_ready", False))
        and isinstance(touch_zone, dict)
    )
    veto = bool(features.get("veto", False))
    boundary = float(touch_zone.get("bottom" if is_buy else "top", entry)) if setup_ready else entry
    sl = round(boundary - 0.1 * atr if is_buy else boundary + 0.1 * atr, d)
    risk = entry - sl if is_buy else sl - entry
    if risk <= 0:
        setup_ready = False
        risk = 0
    tp1 = round(entry + 2.0 * risk if is_buy else entry - 2.0 * risk, d)
    tp2 = round(entry + 3.0 * risk if is_buy else entry - 3.0 * risk, d)
    tp3 = round(entry + 4.0 * risk if is_buy else entry - 4.0 * risk, d)

    structure = features.get("structure") or {}
    try:
        raw_backtest_probability = features.get("backtest_probability")
        prob = (
            max(0, min(100, int(float(raw_backtest_probability))))
            if raw_backtest_probability is not None
            else 0
        )
    except (TypeError, ValueError):
        prob = 0
        raw_backtest_probability = None

    htf1 = features.get("htf1") or {}
    htf2 = features.get("htf2") or {}

    def evidence(source: str, source_id: str, timestamp: int) -> dict[str, Any]:
        return {"source": source, "source_id": source_id, "timestamp": max(1, timestamp)}

    structural_items: list[dict[str, Any]] = []
    for ob in features.get("order_blocks") or []:
        ob_time = int(ob.get("t_start") or t0)
        structural_items.append({
            "kind": "solid_box",
            "label": "OB",
            "color": "#00FF7F" if ob.get("bias") == "bullish" else "#FF4500",
            "price_top": ob["top"],
            "price_bottom": ob["bottom"],
            "time_start": ob_time,
            "time_end": ob.get("t_end", t0),
            "evidence": evidence("candle", f"{features.get('timeframe')}:{ob_time}:OB", ob_time),
        })
    for fvg in features.get("fvgs") or []:
        fvg_time = int(fvg.get("t") or t0)
        structural_items.append({
            "kind": "solid_box",
            "label": "FVG",
            "color": "#BA55D3",
            "price_top": fvg["top"],
            "price_bottom": fvg["bottom"],
            "time_start": fvg_time,
            "time_end": fvg_time + interval,
            "evidence": evidence("candle", f"{features.get('timeframe')}:{fvg_time}:FVG", fvg_time),
        })
    for event in structure.get("events") or []:
        event_start = int(event.get("time_start") or t0)
        event_end = int(event.get("time_end") or t0)
        structural_items.append({
            "kind": "dashed_line",
            "label": str(event.get("type") or "STRUCTURE"),
            "color": "#FFD700",
            "price_start": event.get("price_start"),
            "time_start": event_start,
            "price_end": event.get("price_end"),
            "time_end": event_end,
            "evidence": evidence(
                "candle",
                f"{features.get('timeframe')}:{event_end}:{event.get('type')}",
                event_end,
            ),
        })

    overlay_items: list[dict[str, Any]] = []
    for htf in (htf1, htf2):
        if not bool(htf.get("history_valid")):
            continue
        for ob in htf.get("order_blocks") or []:
            overlay_items.append({
                "type": "ghost_box",
                "kind": "ghost_box",
                "label": f"HTF {htf.get('timeframe')} OB",
                "color": "#00FF7F" if ob.get("bias") == "bullish" else "#FF4500",
                "zone_type": "magnet" if ob.get("bias") == "bullish" else "danger",
                "time_start": int(ob.get("t_start") or t0),
                "time_end": int(ob.get("t_end") or t0),
                "price_top": ob["top"],
                "price_bottom": ob["bottom"],
                "opacity": 0.15,
                "tooltip": (
                    f"{htf.get('timeframe')} "
                    f"{'demand' if ob.get('bias') == 'bullish' else 'supply'} zone"
                ),
                "evidence": evidence(
                    "htf",
                    f"{htf.get('timeframe')}:{ob.get('t_start')}:OB",
                    int(ob.get("t_start") or t0),
                ),
            })
    macro_events = features.get("macro_events")
    if isinstance(macro_events, dict) and macro_events.get("status") == "AVAILABLE":
        for event in macro_events.get("events") or []:
            if (
                isinstance(event, dict)
                and event.get("impact") == "HIGH"
                and isinstance(event.get("provenance"), dict)
            ):
                overlay_items.append({
                    "type": "news_column",
                    "kind": "news_column",
                    "event_id": event.get("event_id"),
                    "text": event.get("title"),
                    "color": "#FF0000",
                    "start_time": int(event.get("event_time")) - MACRO_WINDOW_BEFORE_SEC,
                    "duration_min": (
                        MACRO_WINDOW_BEFORE_SEC + MACRO_WINDOW_AFTER_SEC
                    ) // 60,
                    "currencies": deepcopy(event.get("currencies") or []),
                    "evidence": deepcopy(event["provenance"]),
                })
    wyckoff = features.get("wyckoff_phase")
    if (
        isinstance(wyckoff, dict)
        and isinstance(wyckoff.get("phase"), str)
        and isinstance(wyckoff.get("evidence"), dict)
    ):
        overlay_items.append({
            "type": "wyckoff_phase",
            "kind": "wyckoff_phase",
            "text": wyckoff["phase"],
            "color": "#FFFFFF",
            "evidence": deepcopy(wyckoff["evidence"]),
        })
    trends = [
        htf
        for htf in (htf1, htf2)
        if htf.get("timeframe")
        and htf.get("structure")
        and bool(htf.get("history_valid"))
    ]
    if trends:
        trend_time = int(trends[0].get("last_closed_candle_timestamp") or t0)
        overlay_items.append({
            "type": "htf_trend",
            "kind": "htf_trend",
            "color": "#FFFFFF",
            "htf1_label": str(trends[0].get("timeframe")),
            "htf1_trend": (trends[0].get("structure") or {}).get("trend"),
            "htf2_label": str(trends[1].get("timeframe")) if len(trends) > 1 else None,
            "htf2_trend": (trends[1].get("structure") or {}).get("trend") if len(trends) > 1 else None,
            "evidence": evidence(
                "htf",
                f"{trends[0].get('timeframe')}:{trend_time}:TREND",
                trend_time,
            ),
        })

    signal = {
        "chart_id": f"{symbol}_{features.get('timeframe') or 'UNKNOWN'}_{t0}",
        "symbol": symbol,
        "type": bias,
        "entryPrice": entry,
        "slPrice": sl,
        "tpPrices": [tp1, tp2, tp3],
        "probability": prob,
        "probability_source": (
            "backtest" if raw_backtest_probability is not None else None
        ),
        "fallback": True,
        "setup_ready": setup_ready,
        "veto": veto,
        "veto_data": features.get("veto_data"),
        "forecast_text": "HARD SETUP: confirmed structural execution levels.",
        "layers": [
            {
                "layer": 1,
                "type": "box",
                "items": structural_items,
            },
            {
                "layer": 2,
                "type": "icon_text",
                "items": list(features.get("liquidity_markers") or []),
            },
            {
                "layer": 3,
                "type": "candle_color",
                "items": list(features.get("candle_overrides") or []),
            },
            {
                "layer": 4,
                "type": "execution",
                "entry_line": {"price": entry, "color": "#0000FF"},
                "sl_line": {"price": sl, "color": "#FF0000"},
                "tp_lines": [
                    {"price": tp1, "label": "TP1", "color": "#00FF00"},
                    {"price": tp2, "label": "TP2", "color": "#00FF00"},
                    {"price": tp3, "label": "TP3", "color": "#00FF00"},
                ],
                "curves": [
                    {
                        "id": "SIG_1",
                        "type": "bezier_dashed",
                        "color": "#00F0FF",
                        "points": [
                            {"x_time": t0, "y_price": entry},
                            {"x_time": t0 + interval * 3, "y_price": round((entry + tp1) / 2, d)},
                            {"x_time": t0 + interval * 6, "y_price": tp3},
                        ],
                    },
                    {
                        "id": "SIG_2",
                        "type": "bezier_dashed",
                        "color": "#1E90FF",
                        "points": [
                            {"x_time": t0, "y_price": entry},
                            {"x_time": t0 + interval * 2, "y_price": round(entry + (-0.3 * atr if is_buy else 0.3 * atr), d)},
                            {"x_time": t0 + interval * 5, "y_price": round((entry + tp1) / 2, d)},
                            {"x_time": t0 + interval * 8, "y_price": tp3},
                        ],
                    },
                ],
            },
            {
                "layer": 5,
                "type": "overlay",
                "items": overlay_items,
            },
        ],
    }
    return apply_stage_gates(signal, {
        "setup_ready": setup_ready,
        "veto": veto,
        "veto_data": features.get("veto_data"),
    })
