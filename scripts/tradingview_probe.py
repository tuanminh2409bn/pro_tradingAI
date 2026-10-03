"""TradingView diagnostic using the same series reader as the Web backend.

Run: python scripts/tradingview_probe.py --symbol OANDA:XAUUSD --check-backend
Use --catalog to check all existing Web symbols (at most 4 parallel connections).
Anonymous access does not establish commercial data rights.
"""

import argparse
import json
import math
import os
import sys
import time
from concurrent.futures import ThreadPoolExecutor
from datetime import datetime, timezone
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from tradingview_history import (
    TF_SECONDS, TV_SYMBOL_MAP, _connect, _extract_candles, _finite,
    _pack, _parse_packets, fetch_tv_series, validate_tv_series,
)
from feature_engine import validate_candle_history

TV_SYMBOL = "OANDA:XAUUSD"
APISED_URL = "https://gold.g.apised.com/v1/latest?metals=XAU&base_currency=USD&currencies=USD&weight_unit=TOZ"


def fetch_tv_history(symbol=TV_SYMBOL, interval="5", n_bars=151, timeout=15):
    result = fetch_tv_series(symbol, interval, n_bars, timeout, connector=_connect)
    return (None, result.error) if result.error else (list(result.candles), None)


def summarize_history(candles, interval, required=150, *, now_ts=None):
    now_ts = time.time() if now_ts is None else now_ts
    closed = [bar for bar in candles if _finite(bar["time"]) and bar["time"] + TF_SECONDS[interval] <= now_ts]
    invalid, missing_volume = 0, 0
    for bar in closed:
        prices = [bar[key] for key in ("open", "high", "low", "close")]
        valid_prices = all(_finite(price) and price > 0 for price in prices)
        if not valid_prices or not bar["low"] <= min(bar["open"], bar["close"]) <= max(bar["open"], bar["close"]) <= bar["high"]:
            invalid += 1
        if not _finite(bar["volume"]) or bar["volume"] < 0:
            missing_volume += 1
    zero_volume = bool(closed) and all(bar["volume"] == 0 for bar in closed)
    return {
        "received": len(candles), "closed": len(closed), "required": required,
        "invalid_ohlc": invalid, "missing_volume": missing_volume,
        "first_timestamp": closed[0]["time"] if closed else None,
        "last_timestamp": closed[-1]["time"] if closed else None,
        "last_close": closed[-1]["close"] if closed and _finite(closed[-1]["close"]) else None,
        "volume_unavailable": zero_volume,
        "ohlcv_complete": len(closed) >= required and not invalid and not missing_volume and not zero_volume,
    }


def check_backend_history(candles, interval, required, *, now_ts=None):
    """Default UTC gate retained for offline regression checks."""
    now_ts = time.time() if now_ts is None else now_ts
    closed = [bar for bar in candles if _finite(bar["time"]) and bar["time"] + TF_SECONDS[interval] <= now_ts]
    selected = [dict(zip(
        ("t", "o", "h", "l", "c", "v"),
        (bar["time"], bar["open"], bar["high"], bar["low"], bar["close"], bar["volume"]),
    )) for bar in closed[-required:]]
    return validate_candle_history(selected, interval, required, now_ts=now_ts)


def test_apised(n_ticks=5, interval=1.0):
    key = os.environ.get("APISED_KEY", "").strip()
    if not key:
        print("APISed: missing_APISED_KEY")
        return False
    import httpx
    successes = 0
    with httpx.Client(timeout=5) as client:
        for index in range(n_ticks):
            try:
                response = client.get(APISED_URL, headers={"x-api-key": key})
                response.raise_for_status()
                data = response.json()
                price = float(data["data"]["metal_prices"]["XAU"]["price"])
                if data.get("status") == "success" and math.isfinite(price) and price > 0:
                    successes += 1
            except (httpx.HTTPError, ValueError, KeyError, TypeError):
                pass
            if index + 1 < n_ticks:
                time.sleep(interval)
    print(f"APISed: {successes}/{n_ticks} ticks received")
    return successes == n_ticks


def probe_market(symbol, timeframes, required, timeout, check_backend):
    rows = []
    for interval in timeframes:
        started = time.monotonic()
        series = fetch_tv_series(symbol, interval, required + 1, timeout)
        row = {"symbol": symbol, "timeframe": interval, "error": series.error or None,
               "elapsed_seconds": round(time.monotonic() - started, 3), "metadata": series.metadata}
        if not series.error:
            row.update(summarize_history(series.candles, interval, required))
            if check_backend:
                _, check, profile = validate_tv_series(series, interval, required, int(time.time()))
                row.update(backend_validation=check, session_profile=profile)
        rows.append(row)
        print(json.dumps(row, allow_nan=False), flush=True)
    return rows


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--symbol", default=TV_SYMBOL)
    parser.add_argument("--timeframes", nargs="+", choices=TF_SECONDS, default=["5", "15", "60", "240", "1D"])
    parser.add_argument("--required", type=int, default=150)
    parser.add_argument("--timeout", type=float, default=12)
    parser.add_argument("--apised", action="store_true")
    parser.add_argument("--check-backend", action="store_true")
    parser.add_argument("--catalog", action="store_true")
    parser.add_argument("--output", type=Path)
    args = parser.parse_args()
    if not 1 <= args.required <= 1499 or not 0 < args.timeout <= 60:
        parser.error("required must be 1..1499; timeout must be >0 and <=60")
    report = {"tested_at": datetime.now(timezone.utc).isoformat(), "diagnostic_only": True, "results": []}
    apised_ok = not args.apised or test_apised()
    symbols = list(TV_SYMBOL_MAP.values()) if args.catalog else [args.symbol]
    with ThreadPoolExecutor(max_workers=4) as pool:
        batches = pool.map(lambda symbol: probe_market(symbol, args.timeframes, args.required, args.timeout, args.check_backend), symbols)
        for rows in batches:
            report["results"].extend(rows)
    if args.output:
        args.output.write_text(json.dumps(report, indent=2, allow_nan=False) + "\n")
    passed = apised_ok and all(not row["error"] and row.get("ohlcv_complete") and (not args.check_backend or row.get("backend_validation", {}).get("valid")) for row in report["results"])
    return 0 if passed else 1


if __name__ == "__main__":
    raise SystemExit(main())
