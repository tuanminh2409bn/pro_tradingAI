"""Verify public feed accuracy and, explicitly, isolated production QA requests.

Run inside the backend container. --qa-writes creates a temporary non-admin Auth
user, saves only its paper risk settings and submits requests through Firestore
Rules. No orders or messages are sent. The account is disabled and tokens revoked
after verification; test documents are retained as audit evidence.
"""

import argparse
import json
import sys
import time
import uuid
from datetime import datetime, timezone
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import httpx
from tradingview_history import fetch_tv_series


def compare_bitstamp(client):
    results = []
    for market in ("BTCUSD", "ETHUSD", "XRPUSD"):
        series = fetch_tv_series("BITSTAMP:" + market, "5", 21)
        response = client.get("https://www.bitstamp.net/api/v2/ohlc/" + market.lower() + "/",
                              params={"step": 300, "limit": 21, "exclude_current_candle": "true"})
        response.raise_for_status()
        direct = {int(bar["timestamp"]): bar for bar in response.json()["data"]["ohlc"]}
        now = int(time.time())
        differences, volume_errors = [], []
        timestamps = []
        for bar in series.candles:
            timestamp = int(bar["time"])
            if timestamp + 300 > now or timestamp not in direct:
                continue
            timestamps.append(timestamp)
            expected = direct[timestamp]
            differences.extend(abs(bar[key] - float(expected[key])) for key in ("open", "high", "low", "close"))
            volume_errors.append(abs(bar["volume"] - float(expected["volume"])))
        tick = 1 / float(series.metadata.get("pricescale") or 1)
        row = {"symbol": market, "tradingview_error": series.error or None,
               "matched_closed_candles": len(timestamps), "declared_price_tick": tick,
               "max_ohlc_absolute_error": max(differences) if differences else None,
               "max_volume_absolute_error": max(volume_errors) if volume_errors else None,
               "ohlc_within_one_tick": bool(differences) and max(differences) <= tick + 1e-9}
        results.append(row)
        print(json.dumps(row), flush=True)
    return results


def qa_requests(client, base_url, api_key, report):
    import server
    from firebase_admin import auth

    uid = "qa-tv-20261003-" + uuid.uuid4().hex[:12]
    auth.create_user(uid=uid, display_name="QA TradingView provider verification")
    report.update(uid=uid, non_admin=True, requests=[])
    try:
        auth.set_custom_user_claims(uid, {"role": "standard"})
        custom_token = auth.create_custom_token(uid).decode()
        signed_in = client.post("https://identitytoolkit.googleapis.com/v1/accounts:signInWithCustomToken",
                                params={"key": api_key}, json={"token": custom_token, "returnSecureToken": True})
        signed_in.raise_for_status()
        token = signed_in.json()["idToken"]
        # Newly issued tokens may precede the verifier's clock by a second.
        for attempt in range(4):
            try:
                auth.verify_id_token(token)
                break
            except auth.InvalidIdTokenError as error:
                report["verification_error_type"] = type(error).__name__
                if attempt == 3:
                    raise RuntimeError("QA ID token verification failed: " + type(error).__name__) from None
                time.sleep(1)
        headers = {"Authorization": "Bearer " + token}
        risk = client.post(base_url + "/api/risk-config", headers=headers,
                           json={"userId": uid, "balance": 10000, "riskPerTrade": 1, "maxDailyLoss": 5})
        risk.raise_for_status()
        if risk.json().get("status") != "success":
            raise RuntimeError("QA risk configuration rejected")
        report["risk_config_http"] = risk.status_code
        isolation = client.get(base_url + "/api/risk-config/not-this-qa-user", headers=headers)
        report["foreign_uid_http"] = isolation.status_code
        if isolation.status_code != 403:
            raise RuntimeError("User isolation did not reject foreign UID")
        project = server.firebase_admin.get_app().project_id
        document_root = "projects/" + project + "/databases/(default)/documents/"
        firestore_url = "https://firestore.googleapis.com/v1/" + document_root
        cases = [("BTCUSD", "5", "scalping"), ("BTCUSD", "5", "scalping"),
                 ("BTCUSD", "15", "day_trading"), ("BTCUSD", "60", "swing"),
                 ("XAUUSD", "5", "scalping"), ("XAUUSD", "15", "day_trading"),
                 ("XAUUSD", "60", "swing"), ("EURUSD", "60", "swing"),
                 ("BNBUSD", "5", "scalping"), ("US100", "5", "scalping")]
        for symbol, timeframe, mode in cases:
            request_id = uid + "-" + uuid.uuid4().hex[:8]
            fields = {key: {"stringValue": value} for key, value in {
                "symbol": symbol, "timeframe": timeframe, "execution_tf": timeframe,
                "trading_mode": mode, "userId": uid, "status": "PENDING",
            }.items()}
            committed = client.post(firestore_url + ":commit", headers=headers, json={"writes": [{
                "update": {"name": document_root + "analysis_requests/" + request_id, "fields": fields},
                "updateTransforms": [{"fieldPath": "requestedAt", "setToServerValue": "REQUEST_TIME"}],
                "currentDocument": {"exists": False},
            }]})
            committed.raise_for_status()
            started, deadline = time.monotonic(), time.monotonic() + 120
            signal, request = None, {}
            while time.monotonic() < deadline:
                request = server.db.collection("analysis_requests").document(request_id).get().to_dict() or {}
                if request.get("status") == "ERROR":
                    break
                if request.get("status") == "COMPLETED":
                    own = list(server.db.collection("signals").where("userId", "==", uid).where("symbol", "==", symbol).get())
                    candidates = [doc.to_dict() for doc in own if doc.to_dict().get("status") == "ACTIVE" and doc.to_dict().get("cache_key") == request.get("cache_key")]
                    if candidates:
                        signal = max(candidates, key=lambda value: value.get("createdAt"))
                        break
                time.sleep(.5)
            row = {"symbol": symbol, "timeframe": timeframe, "request_id": request_id,
                   "firestore_write_http": committed.status_code, "status": request.get("status"),
                   "elapsed_seconds": round(time.monotonic() - started, 2),
                   "cache_hit": request.get("cache_hit"), "cache_key": request.get("cache_key"),
                   "market_source": (signal or {}).get("market_source"),
                   "market_closed_at": (signal or {}).get("market_closed_at"),
                   "setup_ready": (signal or {}).get("setup_ready"), "veto": (signal or {}).get("veto"),
                   "fallback": (signal or {}).get("fallback"),
                   "forecast_text": (signal or {}).get("forecast_text"),
                   "signal_received": signal is not None, "owner_matches": (signal or {}).get("userId") == uid}
            report["requests"].append(row)
            print(json.dumps(row), flush=True)
            if request.get("status") != "COMPLETED" or signal is None or signal.get("userId") != uid or not str(signal.get("market_source", "")).startswith("tradingview:"):
                raise RuntimeError("QA analysis request did not complete with owner-bound TradingView signal")
    finally:
        auth.update_user(uid, disabled=True)
        auth.revoke_refresh_tokens(uid)
        report["qa_account_disabled"] = True
        report["refresh_tokens_revoked"] = True
    return report


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--base-url", default="https://103-69-189-243.sslip.io")
    parser.add_argument("--qa-writes", action="store_true")
    parser.add_argument("--firebase-client-api-key")
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    if args.qa_writes and not args.firebase_client_api_key:
        parser.error("Firebase public client API key required for authenticated QA")
    report = {"tested_at": datetime.now(timezone.utc).isoformat()}
    try:
        with httpx.Client(timeout=20) as client:
            report["independent_crypto_comparison"] = compare_bitstamp(client)
            if args.qa_writes:
                report["production_qa"] = {}
                qa_requests(client, args.base_url.rstrip("/"), args.firebase_client_api_key, report["production_qa"])
    finally:
        args.output.write_text(json.dumps(report, indent=2) + "\n")


if __name__ == "__main__":
    main()
