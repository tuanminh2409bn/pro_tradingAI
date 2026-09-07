"""
Day 3 FeatureEngine — pure Python SMC/ATR precompute.
Only a compact feature summary is sent to the LLM (no raw OHLCV dump).
"""
from __future__ import annotations

from typing import Any


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
    if t in ("D", "1D", "d"):
        return "1440"
    return t


def candle_interval_sec(timeframe: str) -> int:
    return TF_INTERVAL_SEC.get(normalize_timeframe(timeframe), 300)


def last_closed_candle_timestamp(
    candles: list[dict],
    timeframe: str,
    now_ts: float | None = None,
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
    if last_t + interval <= now + 1:
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
) -> dict[str, Any]:
    """Deterministic BOS/CHOCH from successive swing breaks."""
    events: list[dict] = []
    trend = "Neutral"
    last_bos = None
    last_choch = None

    sh = swing_highs[-4:]
    sl = swing_lows[-4:]
    if len(sh) >= 2 and sh[-1]["price"] > sh[-2]["price"]:
        last_bos = "bullish"
        events.append({"type": "BOS", "bias": "bullish", "price": sh[-1]["price"], "t": sh[-1]["t"]})
        trend = "Bullish"
    elif len(sh) >= 2 and sh[-1]["price"] < sh[-2]["price"] and len(sl) >= 2 and sl[-1]["price"] < sl[-2]["price"]:
        last_bos = "bearish"
        events.append({"type": "BOS", "bias": "bearish", "price": sl[-1]["price"], "t": sl[-1]["t"]})
        trend = "Bearish"

    if len(sh) >= 2 and len(sl) >= 2:
        # CHOCH: break opposite to prior trend
        if trend == "Bullish" and sl[-1]["price"] < sl[-2]["price"]:
            last_choch = "bearish"
            events.append({"type": "CHOCH", "bias": "bearish", "price": sl[-1]["price"], "t": sl[-1]["t"]})
            trend = "Bearish"
        elif trend == "Bearish" and sh[-1]["price"] > sh[-2]["price"]:
            last_choch = "bullish"
            events.append({"type": "CHOCH", "bias": "bullish", "price": sh[-1]["price"], "t": sh[-1]["t"]})
            trend = "Bullish"

    return {
        "trend": trend,
        "last_bos": last_bos,
        "last_choch": last_choch,
        "events": events[-4:],
    }


def compute_features(
    symbol: str,
    timeframe: str,
    candles: list[dict],
    current_price: float,
    now_ts: float | None = None,
) -> dict[str, Any]:
    """Build compact technical summary for LLM / rule-based fallback."""
    ordered = sorted(candles, key=lambda c: int(c.get("t", 0))) if candles else []
    # Prefer closed candles for structure (drop forming bar when present)
    interval = candle_interval_sec(timeframe)
    import time as _time
    now = float(now_ts if now_ts is not None else _time.time())
    closed = [c for c in ordered if int(c.get("t", 0)) + interval <= now + 1]
    if len(closed) < 5:
        closed = ordered

    atr = round(_atr(closed, 14), 5)
    swing_highs, swing_lows = _swing_points(closed)
    fvgs = _detect_fvgs(closed)
    order_blocks = _detect_order_blocks(closed, atr if atr > 0 else 1.0)
    structure = _structure_events(swing_highs, swing_lows)

    bias = "BUY" if structure["trend"] == "Bullish" else "SELL" if structure["trend"] == "Bearish" else "BUY"
    if structure.get("last_choch") == "bullish":
        bias = "BUY"
    elif structure.get("last_choch") == "bearish":
        bias = "SELL"

    last_closed_ts = last_closed_candle_timestamp(ordered, timeframe, now_ts=now)
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
    """OHLC resample by integer multiple of intervals (deterministic)."""
    src = candle_interval_sec(from_tf)
    dst = candle_interval_sec(to_tf)
    if dst <= src or not candles:
        return list(candles)
    factor = max(1, dst // src)
    ordered = sorted(candles, key=lambda c: int(c.get("t", 0)))
    out: list[dict] = []
    for i in range(0, len(ordered), factor):
        chunk = ordered[i : i + factor]
        if not chunk:
            continue
        out.append({
            "t": int(chunk[0]["t"]),
            "o": float(chunk[0]["o"]),
            "h": max(float(c["h"]) for c in chunk),
            "l": min(float(c["l"]) for c in chunk),
            "c": float(chunk[-1]["c"]),
        })
    return out


def _price_in_zone(price: float, top: float, bottom: float, pad: float = 0.0) -> bool:
    lo, hi = min(bottom, top) - pad, max(bottom, top) + pad
    return lo <= price <= hi


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
    bias = exec_features.get("bias", "BUY")
    pad = atr * 0.35

    zones = list(exec_features.get("order_blocks") or []) + list(exec_features.get("fvgs") or [])
    setup_ready = False
    touch_zone = None
    for z in zones:
        z_bias = z.get("bias")
        want = "bullish" if bias == "BUY" else "bearish"
        if z_bias != want:
            continue
        top, bottom = float(z.get("top", 0)), float(z.get("bottom", 0))
        if _price_in_zone(price, top, bottom, pad=pad):
            setup_ready = True
            touch_zone = z
            break

    veto = False
    veto_data: dict[str, Any] | None = None
    for label, htf in (("htf1", htf1_features), ("htf2", htf2_features)):
        if not htf:
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
                    "zone": z,
                    "bias": bias,
                }
                break
        if veto:
            break

    if veto:
        setup_ready = False

    return {
        "setup_ready": setup_ready,
        "veto": veto,
        "veto_data": veto_data,
        "touch_zone": touch_zone,
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
    setup_ready = bool(gate.get("setup_ready"))
    veto = bool(gate.get("veto"))
    out["setup_ready"] = setup_ready
    out["veto"] = veto
    out["veto_data"] = gate.get("veto_data")
    if not setup_ready or veto:
        out["layers"] = strip_layer4(out.get("layers") or [])
        # Keep numeric fields for journaling but mark soft
        out["forecast_text"] = (
            "VETO: HTF opposing supply/demand — entry frozen."
            if veto
            else "SOFT ALERT: waiting for price to tap OB/FVG zone (setup_ready=false)."
        )
    return out


def build_mtf_feature_pack(
    symbol: str,
    timeframe: str,
    candles_execution: list[dict],
    current_price: float,
    candles_htf_1: list[dict] | None = None,
    candles_htf_2: list[dict] | None = None,
    now_ts: float | None = None,
) -> dict[str, Any]:
    """Execution + HTF1/HTF2 features; HTF candles resampled if not provided."""
    htf1_tf, htf2_tf = htf_pair_for_execution(timeframe)
    exec_f = compute_features(symbol, timeframe, candles_execution, current_price, now_ts=now_ts)

    c1 = candles_htf_1 if candles_htf_1 else aggregate_candles(candles_execution, timeframe, htf1_tf)
    c2 = candles_htf_2 if candles_htf_2 else aggregate_candles(candles_execution, timeframe, htf2_tf)
    htf1_f = compute_features(symbol, htf1_tf, c1, current_price, now_ts=now_ts) if c1 else None
    htf2_f = compute_features(symbol, htf2_tf, c2, current_price, now_ts=now_ts) if c2 else None

    gate = evaluate_setup_and_veto(exec_f, htf1_f, htf2_f)
    pack = dict(exec_f)
    pack["htf1"] = {
        "timeframe": htf1_tf,
        "bias": (htf1_f or {}).get("bias"),
        "structure": (htf1_f or {}).get("structure"),
        "order_blocks": (htf1_f or {}).get("order_blocks"),
        "atr": (htf1_f or {}).get("atr"),
    } if htf1_f else None
    pack["htf2"] = {
        "timeframe": htf2_tf,
        "bias": (htf2_f or {}).get("bias"),
        "structure": (htf2_f or {}).get("structure"),
        "order_blocks": (htf2_f or {}).get("order_blocks"),
        "atr": (htf2_f or {}).get("atr"),
    } if htf2_f else None
    pack.update(gate)
    return pack



def _digits_for_price(price: float) -> int:
    if price >= 100:
        return 2
    if price >= 10:
        return 3
    return 5


def build_signal_from_features(features: dict[str, Any]) -> dict[str, Any]:
    """Deterministic 5-layer signal — no random.*."""
    symbol = features.get("symbol", "XAUUSD")
    bias = features.get("bias", "BUY")
    is_buy = bias == "BUY"
    price = float(features.get("current_price") or 0)
    atr = float(features.get("atr") or 0) or max(price * 0.001, 0.01)
    interval = int(features.get("candle_interval_sec") or 300)
    t0 = int(features.get("last_closed_candle_timestamp") or 0)
    d = _digits_for_price(price)

    entry = round(price, d)
    sl = round(entry - 1.2 * atr if is_buy else entry + 1.2 * atr, d)
    tp1 = round(entry + 1.5 * atr if is_buy else entry - 1.5 * atr, d)
    tp2 = round(entry + 2.5 * atr if is_buy else entry - 2.5 * atr, d)
    tp3 = round(entry + 4.0 * atr if is_buy else entry - 4.0 * atr, d)

    obs = features.get("order_blocks") or []
    if obs:
        ob = obs[-1]
        ob_top, ob_bottom = ob["top"], ob["bottom"]
        ob_ts, ob_te = ob.get("t_start", t0 - interval * 8), ob.get("t_end", t0 - interval * 3)
    else:
        ob_top = round(entry + (0.4 * atr if is_buy else 0.2 * atr), d)
        ob_bottom = round(entry - (0.2 * atr if is_buy else 0.4 * atr), d)
        ob_ts, ob_te = t0 - interval * 8, t0 - interval * 3

    swings_h = features.get("swing_highs") or []
    swings_l = features.get("swing_lows") or []
    bos_price = (swings_h[-1]["price"] if is_buy and swings_h else
                 swings_l[-1]["price"] if (not is_buy) and swings_l else
                 round(entry + (0.5 * atr if is_buy else -0.5 * atr), d))
    bos_t = (swings_h[-1]["t"] if is_buy and swings_h else
             swings_l[-1]["t"] if (not is_buy) and swings_l else t0 - interval * 5)

    structure = features.get("structure") or {}
    trend = structure.get("trend") or ("Bullish" if is_buy else "Bearish")
    # Stable probability from ATR/price ratio (no RNG)
    prob = 72 + min(18, int((atr / max(price, 1e-9)) * 10000) % 19)

    htf1 = features.get("htf1") or {}
    htf2 = features.get("htf2") or {}
    setup_ready = bool(features.get("setup_ready", False))
    veto = bool(features.get("veto", False))

    signal = {
        "symbol": symbol,
        "type": bias,
        "entryPrice": entry,
        "slPrice": sl,
        "tpPrices": [tp1, tp2, tp3],
        "probability": prob,
        "fallback": True,
        "setup_ready": setup_ready,
        "veto": veto,
        "veto_data": features.get("veto_data"),
        "layers": [
            {
                "layer": 1,
                "type": "box",
                "items": [
                    {
                        "label": f"OB ({'Bullish' if is_buy else 'Bearish'})",
                        "color": "green_opacity" if is_buy else "red_opacity",
                        "price_top": ob_top,
                        "price_bottom": ob_bottom,
                        "time_start": ob_ts,
                        "time_end": ob_te,
                    },
                    {
                        "label": "BOS",
                        "color": "cyan",
                        "price_y": bos_price,
                        "time_x": bos_t,
                    },
                ],
            },
            {
                "layer": 2,
                "type": "icon_text",
                "items": [
                    {
                        "icon": "dollar",
                        "text": "$$$ LIQUIDITY",
                        "color": "yellow",
                        "time_x": t0 - interval * 6,
                        "price_y": round(sl + (0.2 * atr if is_buy else -0.2 * atr), d),
                    },
                    {
                        "icon": "arrow",
                        "text": "BSL Sweep" if is_buy else "SSL Sweep",
                        "color": "red",
                        "time_x": t0 - interval * 4,
                        "price_y": round(sl + (0.1 * atr if is_buy else -0.1 * atr), d),
                    },
                ],
            },
            {
                "layer": 3,
                "type": "candle_color",
                "items": [
                    {"candle_time": t0 - interval * 7, "fill_color": "purple", "label_bottom": "STOP"},
                    {"candle_time": t0 - interval * 3, "fill_color": "white", "label_bottom": "Nd"},
                ],
            },
            {
                "layer": 4,
                "type": "execution",
                "entry_line": {"price": entry, "color": "cyan"},
                "sl_line": {"price": sl, "color": "red"},
                "tp_lines": [
                    {"price": tp1, "label": "TP1"},
                    {"price": tp2, "label": "TP2"},
                    {"price": tp3, "label": "TP3"},
                ],
                "suggested_lot": 0.5,
                "curves": [
                    {
                        "id": "SIG_1",
                        "type": "bezier_dashed",
                        "color": "#00FFFF",
                        "points": [
                            {"x_time": t0, "y_price": entry},
                            {"x_time": t0 + interval * 3, "y_price": round((entry + tp1) / 2, d)},
                            {"x_time": t0 + interval * 6, "y_price": tp1},
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
                            {"x_time": t0 + interval * 8, "y_price": tp1},
                        ],
                    },
                ],
            },
            {
                "layer": 5,
                "type": "overlay",
                "items": [
                    {
                        "type": "ghost_box",
                        "label": f"HTF {htf1.get('timeframe') or 'H4'} OB",
                        "zone_type": "magnet" if is_buy else "danger",
                        "price_top": round(entry + 3 * atr, d),
                        "price_bottom": round(entry - 3 * atr, d),
                    },
                    {"type": "wyckoff_phase", "text": "PHASE C -> D" if is_buy else "PHASE B -> C"},
                    {
                        "type": "htf_trend",
                        "htf1_label": str(htf1.get("timeframe") or "H4"),
                        "htf1_trend": (htf1.get("structure") or {}).get("trend") or trend,
                        "htf2_label": str(htf2.get("timeframe") or "D1"),
                        "htf2_trend": (htf2.get("structure") or {}).get("trend") or trend,
                    },
                ],
            },
        ],
    }
    return apply_stage_gates(signal, {
        "setup_ready": setup_ready,
        "veto": veto,
        "veto_data": features.get("veto_data"),
    })

