"""Trusted server-owned MTF history selection for V2.1 analysis."""

from __future__ import annotations

from dataclasses import dataclass
from math import isfinite

from feature_engine import (
    aggregate_candles,
    candle_interval_sec,
    required_mtf_datasets,
    validate_candle_history,
)


_MODE_BY_EXECUTION_TF = {"5": "scalping", "15": "day_trading", "60": "swing"}


def symbol_bound_price(symbol: str, prices: dict, execution: list[dict]) -> float:
    """Choose a mark only from this symbol or its validated execution bars."""
    for candidate in (
        prices.get(symbol),
        execution[-1].get("c") if execution else None,
    ):
        try:
            value = float(candidate)
        except (TypeError, ValueError):
            continue
        if isfinite(value) and value > 0:
            return value
    return 0.0


def symbol_bound_chat_context(
    *, requested_symbol: str, requested_timeframe: str,
    chart_symbol: str, chart_timeframe: str, chart_price: float,
) -> str:
    """Label a display-stream price only when its market identity matches."""
    if (
        requested_symbol != chart_symbol
        or _wire_timeframe(requested_timeframe) != _wire_timeframe(chart_timeframe)
    ):
        return "Live market context unavailable for this symbol and timeframe."
    try:
        price = float(chart_price)
    except (TypeError, ValueError):
        price = 0.0
    if not isfinite(price) or price <= 0:
        return "Live market context unavailable for this symbol and timeframe."
    return (
        f"Display stream price for {requested_symbol} "
        f"({_wire_timeframe(requested_timeframe)} minutes): {price}. "
        "This is display data, not verified execution history."
    )


@dataclass(frozen=True)
class TrustedMtfHistory:
    available: bool
    reason: str
    execution: tuple[dict, ...] = ()
    htf1: tuple[dict, ...] = ()
    htf2: tuple[dict, ...] = ()
    source: str = "server_market_stream"
    session_profile: str = "utc"


def _wire_timeframe(value: str) -> str:
    return {
        "M5": "5",
        "M15": "15",
        "H1": "60",
        "H4": "240",
        "D1": "1440",
        "D": "1440",
        "1D": "1440",
    }.get(str(value).strip().upper(), str(value).strip())


def _closed(candles: list[dict], timeframe: str, now_ts: int) -> list[dict]:
    interval = candle_interval_sec(timeframe)
    return [
        dict(candle)
        for candle in candles
        if int(candle.get("t", 0) or 0) > 0
        and int(candle.get("t", 0)) + interval <= now_ts
    ]


def _complete_aggregates(
    candles: list[dict], source_timeframe: str, target_timeframe: str, now_ts: int
) -> list[dict]:
    """Discard a target bar unless every closed source bar is present."""
    source_interval = candle_interval_sec(source_timeframe)
    target_interval = candle_interval_sec(target_timeframe)
    needed = target_interval // source_interval
    buckets: dict[int, list[dict]] = {}
    for candle in candles:
        try:
            timestamp = int(candle.get("t", 0))
        except (AttributeError, TypeError, ValueError):
            continue
        if timestamp <= 0 or timestamp + source_interval > now_ts:
            continue
        bucket_start = timestamp // target_interval * target_interval
        buckets.setdefault(bucket_start, []).append(candle)

    complete: list[dict] = []
    for start, members in sorted(buckets.items()):
        if start + target_interval > now_ts or len(members) != needed:
            continue
        ordered = sorted(members, key=lambda item: int(item["t"]))
        if [int(item["t"]) for item in ordered] != [
            start + offset * source_interval for offset in range(needed)
        ]:
            continue
        if not validate_candle_history(
            ordered, source_timeframe, needed, now_ts=now_ts
        )["valid"]:
            continue
        complete.extend(aggregate_candles(ordered, source_timeframe, target_timeframe))
    return complete


def build_trusted_mtf_history(
    *,
    requested_symbol: str,
    execution_timeframe: str,
    provider_symbol: str,
    provider_timeframe: str,
    provider_candles: list[dict],
    now_ts: int,
) -> TrustedMtfHistory:
    """Build exact histories only from the matching server market stream."""
    requested = requested_symbol.strip().upper().replace("/", "")
    provided = provider_symbol.strip().upper().replace("/", "")
    execution_tf = _wire_timeframe(execution_timeframe)
    provider_tf = _wire_timeframe(provider_timeframe)
    mode = _MODE_BY_EXECUTION_TF.get(execution_tf)
    if not mode:
        return TrustedMtfHistory(False, "unsupported_execution_timeframe")
    if not requested or requested != provided:
        return TrustedMtfHistory(False, "server_symbol_mismatch")
    if not provider_candles:
        return TrustedMtfHistory(False, "server_history_unavailable")

    provider_interval = candle_interval_sec(provider_tf)
    if provider_interval > candle_interval_sec(execution_tf):
        return TrustedMtfHistory(False, "provider_timeframe_too_coarse")

    histories: list[tuple[dict, ...]] = []
    for target_tf, count in required_mtf_datasets(mode):
        target_wire = _wire_timeframe(target_tf)
        target_interval = candle_interval_sec(target_wire)
        if target_interval < provider_interval or target_interval % provider_interval:
            return TrustedMtfHistory(False, "provider_timeframe_incompatible")
        if target_wire == provider_tf:
            candidates = _closed(provider_candles, target_wire, now_ts)
        else:
            candidates = _complete_aggregates(
                provider_candles, provider_tf, target_wire, now_ts
            )
        selected = candidates[-count:]
        validation = validate_candle_history(
            selected,
            target_wire,
            count,
            now_ts=now_ts,
        )
        if not validation["valid"]:
            issues = ",".join(validation["issues"])
            return TrustedMtfHistory(False, f"invalid_{target_tf.lower()}:{issues}")
        histories.append(tuple(selected))

    return TrustedMtfHistory(
        True,
        "",
        execution=histories[0],
        htf1=histories[1],
        htf2=histories[2],
    )
