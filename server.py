import json
import math
import time
import random
import string
import re
import asyncio
import os
import hashlib
from datetime import datetime, timezone
from urllib.parse import urljoin
from fastapi import FastAPI, WebSocket, WebSocketDisconnect, Request, Header, HTTPException
from fastapi.responses import Response
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel, StrictFloat
import websockets
import httpx
from metaapi_cloud_sdk import MetaApi
import firebase_admin
from firebase_admin import auth, credentials, firestore, messaging
from google.api_core.exceptions import Conflict
from google.cloud import firestore as cloud_firestore
from google.auth.credentials import AnonymousCredentials
from openai import OpenAI
from dotenv import load_dotenv

from analysis_cache import (
    analysis_cache,
    analysis_cache_key,
    ttl_for_timeframe,
)
from analysis_contract import validate_client_analysis_request
from admin_controls import (
    BackendOperation,
    MasterPromptCache,
    ensure_backend_operation_allowed,
)
from feature_engine import (
    apply_stage_gates,
    build_mtf_feature_pack,
    build_signal_from_features,
    build_unavailable_signal,
    candle_interval_sec,
    features_prompt_block,
    is_executable_signal,
    market_analysis_features,
    strip_user_specific_analysis,
)
from observability import (
    FailureCode,
    Operation,
    OperationMetric,
    OperationOutcome,
    OperationRecorder,
)
from trade_gate import (
    AuthDenied, TradeDenied, trade_document_id, validate_trade_intent,
    verify_user_identity,
)
from daily_loss_guard import DailyLossPolicyError, evaluate_daily_loss
from cutoff_state import cutoff_active, utc_session
from http_boundary import UnsafeExternalUrl, validate_public_https_url, web_allowed_origins
from market_history import (
    TrustedMtfHistory, symbol_bound_chat_context, symbol_bound_price,
)
from oanda_history import fetch_oanda_mtf_history
from tradingview_history import fetch_tradingview_mtf_history
from push_preferences import push_recipient_opted_in
from analysis_pipeline import run_market_pipeline
from specialist_analysis import SpecialistProviderError
from entitlements import Capability, EntitlementDenied, QuotaEnforcer, VerifiedQuotaIdentity
from quota_store import FirestoreQuotaStore
from backtest_api import backtest_creation, same_backtest_creation
from official_news import APPROVED_NEWS_FEEDS, MAX_BYTES as NEWS_MAX_BYTES, parse_official_feed

LOCAL_QA_MODE = os.environ.get("PROTRADING_LOCAL_QA", "") == "1"
if LOCAL_QA_MODE:
    if (
        os.environ.get("FIRESTORE_EMULATOR_HOST") != "127.0.0.1:8080"
        or os.environ.get("FIREBASE_AUTH_EMULATOR_HOST") != "127.0.0.1:9099"
        or not os.environ.get("GCLOUD_PROJECT")
    ):
        raise RuntimeError("Local QA requires loopback Firebase Emulators and a project ID")
else:
    load_dotenv()


def _emit_operation_metric(metric: OperationMetric) -> None:
    print(json.dumps({
        "metric": "backend_operation",
        "operation": metric.operation.value,
        "outcome": metric.outcome.value,
        "latency_ms": metric.latency_ms,
        "fallback": metric.fallback,
        "error_code": metric.error_code.value if metric.error_code else None,
    }, sort_keys=True))


operation_recorder = OperationRecorder(sink=_emit_operation_metric)

# Initialize Firebase Admin
if not firebase_admin._apps:
    if LOCAL_QA_MODE:
        firebase_admin.initialize_app(options={"projectId": os.environ["GCLOUD_PROJECT"]})
    else:
        try:
            cred = credentials.Certificate("firebase-adminsdk.json")
            firebase_admin.initialize_app(cred)
        except Exception:
            print("Firebase local credential unavailable; trying Application Default Credentials")
            try:
                cred = credentials.ApplicationDefault()
                firebase_admin.initialize_app(cred)
            except Exception:
                print("Firebase initialization failed")

db = (
    cloud_firestore.Client(
        project=os.environ["GCLOUD_PROJECT"], credentials=AnonymousCredentials()
    )
    if LOCAL_QA_MODE
    else firestore.client()
)

DEEPSEEK_API_KEY = "" if LOCAL_QA_MODE else os.environ.get("DEEPSEEK_API_KEY", "")
if not DEEPSEEK_API_KEY:
    print("⚠️ DEEPSEEK_API_KEY not set — AI calls will use rule-based fallback")
ai_client = OpenAI(api_key=DEEPSEEK_API_KEY or "sk-missing", base_url="https://api.deepseek.com")
DEEPSEEK_MODEL = os.environ.get('DEEPSEEK_MODEL', 'deepseek-flash')

# ─── Per-symbol price book & PnL helpers (V2.1 P0#1) ───
YAHOO_TICKER_MAP = {
    "XAUUSD": "GC=F",
    "XAGUSD": "SI=F",
    "BTCUSD": "BTC-USD",
    "ETHUSD": "ETH-USD",
    "EURUSD": "EURUSD=X",
    "GBPUSD": "GBPUSD=X",
    "USDJPY": "USDJPY=X",
    "USDCHF": "USDCHF=X",
    "AUDUSD": "AUDUSD=X",
    "USDCAD": "USDCAD=X",
    "NZDUSD": "NZDUSD=X",
    "US100": "NQ=F",
    "USOIL": "CL=F",
}

# Approx USD value per 1.0 pip move per 1.0 lot (aligned with Flutter SymbolMeta)
PIP_META = {
    "XAUUSD": (0.1, 10.0),
    "XAGUSD": (0.01, 50.0),
    "BTCUSD": (1.0, 1.0),
    "ETHUSD": (1.0, 1.0),
    "EURUSD": (0.0001, 10.0),
    "GBPUSD": (0.0001, 10.0),
    "USDJPY": (0.01, 9.0),
    "USDCHF": (0.0001, 10.0),
    "AUDUSD": (0.0001, 10.0),
    "USDCAD": (0.0001, 10.0),
    "US100": (1.0, 1.0),
    "USOIL": (0.01, 10.0),
}


def normalize_symbol(symbol: str) -> str:
    if not symbol:
        return "XAUUSD"
    # Strip broker prefix e.g. OANDA:XAUUSD
    if ":" in symbol:
        symbol = symbol.split(":")[-1]
    return re.sub(r"[^A-Za-z0-9]", "", symbol).upper()


def calc_pnl(symbol: str, trade_type: str, open_price: float, mark_price: float, lot_size: float) -> float:
    sym = normalize_symbol(symbol)
    pip_size, pip_value = PIP_META.get(sym, (0.0001, 10.0))
    if pip_size <= 0:
        return 0.0
    direction = -1.0 if str(trade_type).upper() == "SELL" else 1.0
    pips = ((mark_price - open_price) * direction) / pip_size
    return round(pips * pip_value * float(lot_size), 2)

# ─── Master Prompt Cache (tránh Firestore read mỗi request) ───
_MASTER_PROMPT_CACHE_TTL = int(MasterPromptCache.TTL_SECONDS)


def _load_chat_master_prompt() -> str:
    config_doc = db.collection("AdminSettings").document("ai_config").get()
    if not config_doc.exists:
        raise RuntimeError("AI master prompt is unavailable")
    data = config_doc.to_dict()
    if not isinstance(data, dict):
        raise RuntimeError("AI master prompt is unavailable")
    return data.get("ai_master_prompt", "")


_master_prompt_cache = MasterPromptCache(loader=_load_chat_master_prompt)


def _load_trading_enabled() -> bool:
    config_doc = db.collection("admin").document("system_config").get()
    if not config_doc.exists:
        raise RuntimeError("Global operation state is unavailable")
    data = config_doc.to_dict()
    if not isinstance(data, dict):
        raise RuntimeError("Global operation state is unavailable")
    return data.get("tradingEnabled")


async def require_backend_operation(operation: BackendOperation) -> None:
    trading_enabled = await asyncio.to_thread(_load_trading_enabled)
    ensure_backend_operation_allowed(
        trading_enabled=trading_enabled,
        operation=operation,
    )

async def get_chat_master_prompt() -> str:
    """Load the authoritative Admin prompt without blocking the event loop."""

    return await asyncio.to_thread(_master_prompt_cache.get)


app = FastAPI()
app.add_middleware(
    CORSMiddleware,
    allow_origins=list(web_allowed_origins()),
    allow_credentials=True,
    allow_methods=["GET", "POST"],
    allow_headers=["Authorization", "Content-Type", "Idempotency-Key"],
)

TV_WS_URL = "wss://data.tradingview.com/socket.io/websocket"
TV_SYMBOL = "OANDA:XAUUSD"
META_API_TOKEN = "" if LOCAL_QA_MODE else os.environ.get("META_API_TOKEN", "YOUR_META_API_TOKEN")

class LinkAccountRequest(BaseModel):
    userId: str
    platform: str
    server: str
    login: str
    password: str

class TradeRequest(BaseModel):
    userId: str = ""
    signalId: str
    signalChartId: str
    action: str  # BUY or SELL
    symbol: str = "XAUUSD"
    volume: float = 0.1
    entryPrice: float = 0.0
    slPrice: float = 0.0
    tpPrices: list = []
    tradingMode: str = "scalping"

class AIChatRequest(BaseModel):
    userId: str = ""
    message: str
    symbol: str = "XAUUSD"
    timeframe: str = "5"

class BacktestCreateRequest(BaseModel):
    userId: str = ""
    requestId: str
    symbol: str
    startTime: str
    endTime: str
    balance: StrictFloat

class CloseTradeRequest(BaseModel):
    userId: str = ""
    tradeId: str

class RiskConfigRequest(BaseModel):
    userId: str
    balance: float
    riskPerTrade: float
    maxDailyLoss: float


class CutoffOwnerRequest(BaseModel):
    userId: str


class CommunityLikeRequest(BaseModel):
    postId: str
    userId: str = ""


async def verified_user_id(
    authorization: str | None,
    claimed_uid: str = "",
    *,
    required_role: str | None = None,
) -> str:
    """Resolve a private-operation owner from a verified Firebase ID token."""
    try:
        return await verify_user_identity(
            authorization, claimed_uid, auth.verify_id_token,
            invalid_errors=(auth.InvalidIdTokenError, auth.ExpiredIdTokenError, ValueError),
            required_role=required_role,
        )
    except AuthDenied as error:
        raise HTTPException(status_code=error.status_code, detail=str(error)) from None

class TradingViewStreamer:
    def __init__(self, shared_last_prices: dict | None = None,
                 shared_price_observed_at: dict | None = None):
        self.candle_map = {}
        self.last_price = 0.0
        # Independent mark prices per clean symbol — NEVER reuse chart price for other symbols' PnL
        self.last_prices: dict = shared_last_prices if shared_last_prices is not None else {}
        self.price_observed_at = shared_price_observed_at if shared_price_observed_at is not None else {}
        self.account_info = {
            "balance": 0.0,
            "equity": 0.0,
            "margin": 0.0,
            "leverage": 0,
            "status": "UNAVAILABLE",
            "source": "unavailable",
        }
        self.connections = set()
        self.is_running = False
        self.interval = "5"
        self.symbol = "OANDA:XAUUSD"
        self.ws_task = None
        self._heartbeat_task = None
        # ─── Rate limiting & Delta tracking ───
        self._last_broadcast_time = 0.0   # monotonic timestamp of last tick broadcast
        self._pending_delta: dict = {}     # candles changed since last broadcast

    def chart_symbol_clean(self) -> str:
        return normalize_symbol(self.symbol)

    def set_last_price(self, symbol: str, price: float):
        """Bind a mark price to a specific symbol only."""
        if (isinstance(price, bool) or not isinstance(price, (int, float))
                or not math.isfinite(price) or price <= 0):
            return
        clean = normalize_symbol(symbol)
        self.last_prices[clean] = float(price)
        self.price_observed_at[clean] = time.monotonic()
        if clean == self.chart_symbol_clean():
            self.last_price = float(price)

    def get_cached_price(self, symbol: str) -> float | None:
        return self.last_prices.get(normalize_symbol(symbol))

    async def get_price(self, symbol: str) -> float:
        """Return mark price for [symbol], never another chart's price."""
        clean = normalize_symbol(symbol)
        cached = self.last_prices.get(clean)
        if cached and cached > 0:
            return cached
        # Fallback: Yahoo last close for symbols not currently streamed
        yahoo = YAHOO_TICKER_MAP.get(clean)
        if yahoo and not LOCAL_QA_MODE:
            try:
                url = f"https://query1.finance.yahoo.com/v8/finance/chart/{yahoo}?range=1d&interval=1m"
                async with httpx.AsyncClient(timeout=10) as client:
                    resp = await client.get(url, headers={"User-Agent": "Mozilla/5.0 ProTradingAI/2.1"})
                    if resp.status_code == 200:
                        result = resp.json().get("chart", {}).get("result", [])
                        if result:
                            meta = result[0].get("meta", {})
                            price = meta.get("regularMarketPrice") or meta.get("previousClose")
                            if price:
                                self.set_last_price(clean, float(price))
                                return float(price)
            except Exception:
                print(f"[PRICE] Yahoo fallback failed for {clean}")
        # Last resort: only if this IS the active chart symbol
        if clean == self.chart_symbol_clean() and self.last_price > 0:
            return self.last_price
        print(f"[PRICE] No mark price for {clean} — returning 0 (PnL will not use foreign chart)")
        return 0.0

    def _pack(self, msg):
        return f"~m~{len(msg)}~m~{msg}"

    def _generate_session(self):
        return "cs_" + "".join(random.choice(string.ascii_lowercase) for _ in range(12))

    async def start(self):
        if self.ws_task and not self.ws_task.done():
            self.ws_task.cancel()
            await asyncio.gather(self.ws_task, return_exceptions=True)
        self.is_running = True
        self.ws_task = asyncio.create_task(self.stream_data())
        if self._heartbeat_task is None or self._heartbeat_task.done():
            self._heartbeat_task = asyncio.create_task(self.heartbeat())

    async def stop(self):
        """Release the upstream stream and heartbeat owned by this session."""
        self.is_running = False
        tasks = [task for task in (self.ws_task, self._heartbeat_task) if task]
        for task in tasks:
            if not task.done():
                task.cancel()
        if tasks:
            await asyncio.gather(*tasks, return_exceptions=True)
        self.ws_task = None
        self._heartbeat_task = None
        self.connections.clear()

    async def heartbeat(self):
        while True:
            await self.broadcast_update("heartbeat")
            await asyncio.sleep(10)

    async def stream_data(self):
        self.is_running = True
        print(f"SERVER: Starting Streamer for {self.symbol}")
        while self.is_running:
            try:
                headers = {
                    "Origin": "https://data.tradingview.com",
                    "User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36"
                }
                async with websockets.connect(TV_WS_URL, additional_headers=headers) as ws:
                    chart_session = self._generate_session()
                    print(f"SERVER: Connected to TradingView. Session: {chart_session}")
                    
                    await ws.send(self._pack(json.dumps({"m": "set_auth_token", "p": ["unauthorized_user_token"]})))
                    await ws.send(self._pack(json.dumps({"m": "chart_create_session", "p": [chart_session, ""]})))
                    await ws.send(self._pack(json.dumps({"m": "switch_timezone", "p": [chart_session, "Etc/UTC"]})))
                    await ws.send(self._pack(json.dumps({"m": "resolve_symbol", "p": [chart_session, "sds_sym_1", f'={{"symbol":"{self.symbol}","adjustment":"splits","session":"regular"}}']})))
                    # Fetch 3000 candles for rich historical data
                    await ws.send(self._pack(json.dumps({"m": "create_series", "p": [chart_session, "sds_1", "s1", "sds_sym_1", self.interval, 3000, ""]})))

                    async for message in ws:
                        if "~h~" in message:
                            await ws.send(message)
                            continue
                        
                        packets = self._parse_packets(message)
                        for packet in packets:
                            try:
                                data = json.loads(packet)
                                if not isinstance(data, dict): continue
                                
                                if data.get("m") in ["timescale_update", "du"]:
                                    new_candles = self._extract_candles(data.get("p", []))
                                    if new_candles:
                                        for c in new_candles:
                                            self.candle_map[c["t"]] = c
                                            self._pending_delta[c["t"]] = c  # accumulate delta

                                        sorted_times = sorted(self.candle_map.keys())
                                        if len(sorted_times) > 3000:
                                            for t in sorted_times[:-3000]:
                                                del self.candle_map[t]
                                                self._pending_delta.pop(t, None)

                                        self.set_last_price(self.chart_symbol_clean(), self.candle_map[sorted(self.candle_map.keys())[-1]]["c"])
                                        await self.broadcast_delta()  # rate-limited delta only
                                elif data.get("m") == "series_completed":
                                    print(f"SERVER: Series completed for {self.symbol}. {len(self.candle_map)} candles loaded.")
                                    self._pending_delta = {}  # clear pending — full init coming
                                    await self.broadcast_update("init")
                            except Exception:
                                print("[TradingView] Packet parse failed")
                                continue
            except Exception:
                print("[TradingView] Stream failed; retrying")
                await asyncio.sleep(5)

    def _parse_packets(self, raw):
        results = []
        pattern = re.compile(r"~m~(\d+)~m~")
        pos = 0
        while pos < len(raw):
            m = pattern.match(raw, pos)
            if not m: break
            length = int(m.group(1))
            start = m.end()
            results.append(raw[start:start + length])
            pos = start + length
        return results

    def _extract_candles(self, params):
        extracted = []
        for p in params:
            if not isinstance(p, dict): continue
            for k, v in p.items():
                bars = v.get("s") if isinstance(v, dict) else v if isinstance(v, list) else None
                if bars:
                    for bar in bars:
                        if isinstance(bar, dict) and "v" in bar:
                            v_data = bar["v"]
                            extracted.append({
                                "t": int(v_data[0]), 
                                "o": float(v_data[1]), 
                                "h": float(v_data[2]), 
                                "l": float(v_data[3]), 
                                "c": float(v_data[4]),
                                "v": float(v_data[5]) if len(v_data) > 5 and v_data[5] is not None else 0.0,
                            })
        return extracted

    async def broadcast_delta(self):
        """Rate-limited delta broadcast — max 5x/second, sends only changed candles."""
        if not self.connections:
            self._pending_delta = {}
            return

        now = time.monotonic()
        if now - self._last_broadcast_time < 0.2:
            return  # Too soon — skip, next tick will carry accumulated delta

        if not self._pending_delta:
            return  # Nothing changed

        self._last_broadcast_time = now
        delta = list(self._pending_delta.values())
        self._pending_delta = {}  # reset after broadcast

        print(f"SERVER: Broadcasting tick to {len(self.connections)} clients. Delta: {len(delta)} candle(s), price: {self.last_price}")
        msg = json.dumps({
            "type": "tick",
            "symbol": self.chart_symbol_clean(),
            "interval": self.interval,
            "price": self.last_price,
            "prices": self.last_prices,
            "delta": delta,  # Only changed candles (1–5 typically)
        })
        disconnected = set()
        for ws in self.connections:
            try: await ws.send_text(msg)
            except: disconnected.add(ws)
        self.connections -= disconnected

    async def broadcast_update(self, msg_type):
        """Full candle list broadcast — used for init and heartbeat only."""
        if not self.connections: return
        candles_list = [self.candle_map[t] for t in sorted(self.candle_map.keys())]
        print(f"SERVER: Broadcasting {msg_type} to {len(self.connections)} clients. Candles: {len(candles_list)}")
        msg = json.dumps({
            "type": msg_type,
            "symbol": self.chart_symbol_clean(),
            "interval": self.interval,
            "price": self.last_price,
            "prices": self.last_prices,
            "candles": candles_list,
            "account": self.account_info,
        })
        disconnected = set()
        for ws in self.connections:
            try: await ws.send_text(msg)
            except: disconnected.add(ws)
        self.connections -= disconnected

streamer = TradingViewStreamer()
main_loop = None

def send_signal_push_to_owner(user_id: str, symbol: str, signal_type: str, entry: float, sl: float, tp: list, probability: int):
    try:
        if not user_id:
            return
        # A signal is owner-scoped; never broadcast its prices to other users.
        token_docs = db.collection('fcm_tokens').where('userId', '==', user_id).get()
        if not token_docs:
            print("[PUSH] No registered FCM tokens found.")
            return

        target_tokens = []
        for doc in token_docs:
            data = doc.to_dict()
            token = data.get('token')
            if token and data.get('userId') == user_id:
                target_tokens.append(token)

        if not target_tokens:
            print("[PUSH] No owner tokens found.")
            return

        user_doc = db.collection('users').document(user_id).get()
        if not user_doc.exists or not push_recipient_opted_in(user_doc.to_dict()):
            print("[PUSH] Notification preference disabled; skipping recipient")
            return

        # 3. Create the payload
        tp_str = ", ".join([str(t) for t in tp]) if tp else "N/A"
        title = f"🆕 TÍN HIỆU {signal_type} MỚI - {symbol}"
        body = f"AI đề xuất lệnh {signal_type} tại vùng giá {entry}. Cắt lỗ tại {sl}. Chốt lời tại {tp_str}. Độ tin cậy {probability}%."

        print(f"[PUSH] Sending notification to {len(target_tokens)} tokens...")
        
        # 4. Construct Multicast message
        message = messaging.MulticastMessage(
            tokens=target_tokens,
            notification=messaging.Notification(
                title=title,
                body=body,
            ),
            data={
                "click_action": "FLUTTER_NOTIFICATION_CLICK",
                "symbol": symbol,
                "type": signal_type,
                "entry": str(entry),
                "sl": str(sl),
                "tp": tp_str,
                "probability": str(probability)
            },
            webpush=messaging.WebpushConfig(
                notification=messaging.WebpushNotification(
                    icon="/favicon.png"
                )
            )
        )

        # 5. Send Multicast
        response = messaging.send_each_for_multicast(message)
        print(f"✅ [PUSH] Sent successfully. Success count: {response.success_count}, Failure count: {response.failure_count}")
        if response.failure_count > 0:
            for idx, resp in enumerate(response.responses):
                if not resp.success:
                    failed_token = target_tokens[idx]
                    print("[PUSH] Invalid token will be retired")
                    try:
                        db.collection('fcm_tokens').document(failed_token).delete()
                    except Exception:
                        print("[PUSH] Failed to retire invalid token")

    except Exception:
        print("❌ [PUSH] Notification delivery failed")

def _create_seeded_analysis_completion(create_kwargs: dict):
    try:
        return ai_client.chat.completions.create(**create_kwargs, seed=42)
    except TypeError:
        return ai_client.chat.completions.create(**create_kwargs)


def _bounded_llm_request(model: str, messages: list, *, analysis: bool) -> dict:
    """Bound paid inputs without silently removing trading evidence."""
    if not isinstance(messages, list) or not messages:
        raise ValueError('Invalid AI messages')
    size = 0
    for message in messages:
        if (
            not isinstance(message, dict)
            or set(message) != {'role', 'content'}
            or message['role'] not in {'system', 'user', 'assistant'}
            or not isinstance(message['content'], str)
        ):
            raise ValueError('Invalid AI message')
        size += len(message['content'].encode('utf-8'))
    if size > 24000:
        raise ValueError('AI input exceeds budget')
    payload = dict(
        model=model, messages=messages, temperature=0.0,
        max_tokens=1500 if analysis else 600, thinking={'type': 'disabled'},
    )
    if analysis:
        payload['response_format'] = {'type': 'json_object'}
    return payload


def _record_llm_usage(call: str, usage) -> None:
    """Log counts only; never provider payloads, prompts or user identifiers."""
    usage = usage if isinstance(usage, dict) else {}
    details = usage.get('completion_tokens_details')
    details = details if isinstance(details, dict) else {}
    record = {'call': call if call in {'smc', 'vsa', 'macro', 'aggregator', 'chat'} else 'unknown'}
    for key in ('prompt_tokens', 'completion_tokens', 'total_tokens',
                'prompt_cache_hit_tokens', 'prompt_cache_miss_tokens', 'reasoning_tokens'):
        value = details.get(key) if key == 'reasoning_tokens' else usage.get(key)
        record[key] = value if type(value) is int and value >= 0 else None
    print('[DeepSeek Usage] ' + json.dumps(record, sort_keys=True))


async def _run_analysis_pipeline(symbol: str, timeframe: str, features: dict) -> dict:
    """LLM (temp=0) or deterministic FeatureEngine fallback. No random.*."""
    if not bool(features.get("analysis_available")):
        return build_unavailable_signal(features)

    try:
        master_prompt = await get_chat_master_prompt()
    except Exception:
        print("AI master prompt unavailable; using deterministic fallback")
        return build_signal_from_features(features)

    async def provider(**kwargs):
        payload = _bounded_llm_request(kwargs['model'], kwargs['messages'], analysis=True)
        async with httpx.AsyncClient(timeout=20) as client:
            response = await client.post(
                'https://api.deepseek.com/chat/completions', json=payload,
                headers={'Authorization': 'Bearer ' + DEEPSEEK_API_KEY},
            )
        if response.status_code != 200:
            code = {402: 'payment_required', 429: 'rate_limited'}.get(response.status_code, 'unavailable')
            raise SpecialistProviderError(code)
        envelope = response.json()
        _record_llm_usage(kwargs.get('agent'), envelope.get('usage'))
        return json.loads(envelope['choices'][0]['message']['content'])

    if DEEPSEEK_API_KEY:
        correlation = hashlib.sha256(analysis_cache_key(symbol, timeframe, int(features.get('last_closed_candle_timestamp') or 0)).encode()).hexdigest()[:24]
        return await run_market_pipeline(
            features, provider=provider, master_prompt=master_prompt,
            model=DEEPSEEK_MODEL, correlation_id=correlation,
        )

    print("[AI Engine] No DEEPSEEK_API_KEY — rule-based fallback")
    return build_signal_from_features(features)


async def process_ai_analysis(doc_id, symbol, timeframe, user_id='', req_payload: dict | None = None):
    """
    Day 3+4:
      cache_key = analysis:{symbol}:{tf}:{last_closed_candle_timestamp}
      MTF FeatureEngine → setup_ready / veto → LLM(temp=0) → cache
    """
    metric_timer = operation_recorder.start(Operation.ANALYSIS)
    try:
        await require_backend_operation(BackendOperation.ANALYSIS)
        await require_daily_loss_capacity(user_id)
        print(f"⏳ [AI Engine] Processing {symbol} ({timeframe})...")
        doc_ref = db.collection('analysis_requests').document(doc_id)
        await asyncio.to_thread(doc_ref.update, {'status': 'PROCESSING'})
        clean_symbol = normalize_symbol(symbol)
        oanda_account = "" if LOCAL_QA_MODE else os.environ.get("OANDA_PRACTICE_ACCOUNT_ID", "").strip()
        oanda_token = "" if LOCAL_QA_MODE else os.environ.get("OANDA_PRACTICE_TOKEN", "").strip()
        market_provider = os.environ.get("MARKET_HISTORY_PROVIDER", "oanda_practice").strip()
        if market_provider == "tradingview" and not LOCAL_QA_MODE:
            trusted_history = await fetch_tradingview_mtf_history(
                symbol=clean_symbol, execution_timeframe=timeframe,
                now_ts=int(time.time()),
            )
        elif market_provider == "oanda_practice" and oanda_account and oanda_token:
            async with httpx.AsyncClient() as provider_client:
                trusted_history = await fetch_oanda_mtf_history(
                    symbol=clean_symbol,
                    execution_timeframe=timeframe,
                    account_id=oanda_account,
                    token=oanda_token,
                    client=provider_client,
                    now_ts=int(time.time()),
                )
        else:
            trusted_history = TrustedMtfHistory(
                False, "oanda_practice_not_configured" if market_provider == "oanda_practice" else "unsupported_market_history_provider",
                source="oanda_practice_tick_volume" if market_provider == "oanda_practice" else market_provider,
            )
        candles_exec = list(trusted_history.execution)
        candles_htf1 = list(trusted_history.htf1)
        candles_htf2 = list(trusted_history.htf2)

        current_price = symbol_bound_price(
            clean_symbol, {}, candles_exec
        )

        features = build_mtf_feature_pack(
            symbol=clean_symbol,
            timeframe=timeframe,
            candles_execution=candles_exec,
            current_price=float(current_price or 0),
            candles_htf_1=candles_htf1 or None,
            candles_htf_2=candles_htf2 or None,
            session_profile=trusted_history.session_profile,
        )
        if not trusted_history.available:
            features.setdefault("data_quality", {})["provider"] = {
                "valid": False, "issues": [trusted_history.reason],
            }
        features["history_source"] = trusted_history.source
        features["history_unavailable_reason"] = trusted_history.reason or None
        features = market_analysis_features(features)

        last_closed_ts = int(features["last_closed_candle_timestamp"])
        cache_key = analysis_cache_key(clean_symbol, timeframe, last_closed_ts)
        if not trusted_history.available or not features.get("analysis_available"):
            # A provider outage must be rechecked on the next request, even
            # when the closed-candle key has not changed.
            ai_result = build_unavailable_signal(features)
            cache_hit = False
        else:
            await consume_analysis_quota(user_id, doc_id)
            ttl = ttl_for_timeframe(timeframe)

            async def produce_market_artifact() -> dict:
                result = await _run_analysis_pipeline(clean_symbol, timeframe, features)
                return strip_user_specific_analysis(result)

            ai_result, cache_hit = await analysis_cache.get_or_compute(
                cache_key,
                ttl,
                produce_market_artifact,
                timeout_factory=lambda: strip_user_specific_analysis(
                    build_signal_from_features(features)
                ),
            )
            print(
                f"[AI Cache] {'HIT' if cache_hit else 'SET'} {cache_key} "
                f"backend={analysis_cache.backend}"
            )

        ai_result = strip_user_specific_analysis(ai_result)
        ai_result["symbol"] = clean_symbol
        ai_result["market_source"] = trusted_history.source
        ai_result["market_closed_at"] = (
            int(candles_exec[-1]["t"]) if candles_exec else None
        )
        ai_result["cache_hit"] = cache_hit
        ai_result["cache_key"] = cache_key
        ai_result["status"] = "ACTIVE"
        ai_result["createdAt"] = firestore.SERVER_TIMESTAMP
        ai_result["userId"] = user_id

        old_signals_query = db.collection("signals").where("symbol", "==", clean_symbol)
        if user_id:
            old_signals_query = old_signals_query.where("userId", "==", user_id)
        old_signals = await asyncio.to_thread(old_signals_query.get)
        for doc in old_signals:
            old_signal_ref = db.collection("signals").document(doc.id)
            await asyncio.to_thread(
                old_signal_ref.update,
                {"status": "CLOSED"},
            )

        signals_ref = db.collection("signals")
        await asyncio.to_thread(signals_ref.add, ai_result)
        await asyncio.to_thread(
            doc_ref.update,
            {
                "status": "COMPLETED",
                "cache_hit": cache_hit,
                "cache_key": cache_key,
                "setup_ready": bool(ai_result.get("setup_ready")),
                "veto": bool(ai_result.get("veto")),
            },
        )
        print(
            f"✅ AI Signal for {clean_symbol} (cache_hit={cache_hit}, "
            f"setup_ready={ai_result.get('setup_ready')}, veto={ai_result.get('veto')}) → Firebase"
        )

        if is_executable_signal(ai_result):
            try:
                await asyncio.to_thread(
                    send_signal_push_to_owner,
                    user_id=user_id,
                    symbol=clean_symbol,
                    signal_type=ai_result.get("type", "BUY"),
                    entry=float(ai_result["entryPrice"]),
                    sl=float(ai_result["slPrice"]),
                    tp=ai_result["tpPrices"],
                    probability=int(ai_result.get("probability", 0)),
                )
            except Exception:
                print("FCM multicast trigger failed")
        if ai_result.get("fallback") is True:
            metric_timer.finish(
                outcome=OperationOutcome.FALLBACK,
                fallback=True,
                error_code=FailureCode.PROVIDER_UNAVAILABLE,
            )
        else:
            metric_timer.finish(
                outcome=OperationOutcome.SUCCESS,
                fallback=False,
            )
    except HTTPException as error:
        metric_timer.finish(outcome=OperationOutcome.FAILURE, fallback=False,
                            error_code=FailureCode.INTERNAL_ERROR)
        await asyncio.to_thread(db.collection('analysis_requests').document(doc_id).update,
                                {'status': 'ERROR', 'error': error.detail})
    except Exception:
        metric_timer.finish(
            outcome=OperationOutcome.FAILURE,
            fallback=False,
            error_code=FailureCode.INTERNAL_ERROR,
        )
        print("AI analysis process failed")
        try:
            failed_request_ref = db.collection("analysis_requests").document(doc_id)
            await asyncio.to_thread(
                failed_request_ref.update,
                {"status": "ERROR", "error": "analysis_failed"},
            )
        except Exception:
            pass


async def consume_analysis_quota(user_id, request_id):
    return await consume_operation_quota(user_id, request_id, Capability.ANALYSIS)


async def consume_operation_quota(user_id, request_id, capability, *, session_ref=None, session_data=None):
    user = await asyncio.to_thread(auth.get_user, user_id)
    if user.disabled:
        raise HTTPException(status_code=403, detail='account_disabled')
    try:
        identity = VerifiedQuotaIdentity.from_decoded_token({**(user.custom_claims or {}), 'uid': user.uid})
    except EntitlementDenied:
        raise HTTPException(status_code=403, detail='account_role_required') from None
    decision = await asyncio.to_thread(
        QuotaEnforcer(store=FirestoreQuotaStore(db, operation_id=request_id,
                      session_ref=session_ref, session_data=session_data), timezone_name='UTC').consume,
        identity=identity, capability=capability, now=datetime.now(timezone.utc),
    )
    if not decision.allowed:
        raise HTTPException(status_code=429 if decision.reason == 'quota_exhausted' else 403, detail=decision.reason)
    return decision


@app.post('/api/backtest/sessions')
async def create_backtest_session(req: BacktestCreateRequest, authorization: str | None = Header(default=None)):
    user_id = await verified_user_id(authorization, req.userId)
    try:
        session_id, data = backtest_creation(user_id, req.model_dump(), allowed_symbols=TV_SYMBOL_MAP,
                                            now=datetime.now(timezone.utc))
    except ValueError:
        raise HTTPException(status_code=422, detail='invalid_backtest_request') from None
    reference = db.collection('backtest_sessions').document(session_id)
    try:
        existing = await asyncio.to_thread(reference.get)
        if existing.exists:
            saved = existing.to_dict() or {}
            if not same_backtest_creation(saved, data):
                raise HTTPException(status_code=409, detail='backtest_request_conflict')
            # Retrying creation or restoring an old allocation never charges twice.
            return {'status': 'success', 'sessionId': session_id}
        await consume_operation_quota(user_id, 'backtest:' + req.requestId, Capability.BACKTEST,
                                      session_ref=reference, session_data=data)
        return {'status': 'success', 'sessionId': session_id}
    except HTTPException:
        raise
    except ValueError:
        raise HTTPException(status_code=409, detail='backtest_request_conflict') from None
    except Exception:
        raise HTTPException(status_code=503, detail='backtest_unavailable') from None

def on_analysis_request_snapshot(col_snapshot, changes, read_time):
    for change in changes:
        if change.type.name == 'ADDED':
            req_data = change.document.to_dict()
            if isinstance(req_data, dict) and req_data.get('status') == 'PENDING':
                if validate_client_analysis_request(req_data):
                    db.collection('analysis_requests').document(change.document.id).update({
                        'status': 'ERROR', 'error': 'invalid_request',
                    })
                    continue
                symbol = req_data.get('symbol', 'UNKNOWN')
                timeframe = req_data.get('timeframe', 'UNKNOWN')
                doc_id = change.document.id
                user_id = req_data.get('userId', '')
                
                print(f"🔔 [NEW EVENT] Analysis request: {symbol} ({timeframe})")
                
                if main_loop and not main_loop.is_closed():
                    asyncio.run_coroutine_threadsafe(
                        process_ai_analysis(doc_id, symbol, timeframe, user_id, req_data), main_loop
                    )

@app.on_event("startup")
async def startup_event():
    global main_loop
    main_loop = asyncio.get_running_loop()
    print("SERVER: Data Engine Starting Up...")
    await analysis_cache.connect()
    if os.environ.get("PROTRADING_BACKGROUND_WORKERS", "1") == "0":
        print("SERVER: Candidate verification; background workers disabled")
        return
    if not LOCAL_QA_MODE:
        await streamer.start()
    else:
        print("SERVER: Local QA mode; external market stream disabled")
    analysis_requests_ref = db.collection('analysis_requests')
    await asyncio.to_thread(
        analysis_requests_ref.on_snapshot,
        on_analysis_request_snapshot,
    )
    print("SERVER: Listening to Firebase analysis_requests...")
    # Start background loops
    if APPROVED_NEWS_FEEDS and not LOCAL_QA_MODE:
        asyncio.create_task(news_crawler_loop())
        print("SERVER: Approved news crawler started.")
    else:
        print("SERVER: News provider unavailable; crawler disabled.")
    print("SERVER: Radar worker unavailable until approved provider/Redis adapters are configured.")
    asyncio.create_task(admin_stats_loop())
    print("SERVER: Admin stats loop started.")
    asyncio.create_task(service_status_loop())
    print("SERVER: Service status loop started.")


# ─────────────────────────────────────────────────────────────
# ADMIN STATS LOOP
# Cập nhật thống kê hệ thống vào Firestore mỗi 5 phút
# Ghi vào Firestore: admin/stats
# ─────────────────────────────────────────────────────────────

async def admin_stats_loop():
    """Cập nhật Admin Stats mỗi 5 phút từ Firestore counters thật."""
    while True:
        try:
            await _update_admin_stats()
        except Exception:
            print("[ADMIN STATS] Background cycle failed")
        await asyncio.sleep(300)  # 5 phút

def _update_admin_stats_sync():
    """Đếm users, trades từ Firestore và cập nhật admin/stats."""
    try:
        # Đếm tổng users
        users_ref = db.collection("users")
        users_count = users_ref.count().get()[0][0].value

        # Đếm tổng trades hôm nay
        from datetime import date
        today_start = datetime.combine(date.today(), datetime.min.time()).replace(tzinfo=timezone.utc)
        trades_today_ref = db.collection("trades").where("createdAt", ">=", today_start)
        trades_today = trades_today_ref.count().get()[0][0].value

        # Đếm signals đang active
        active_signals_ref = db.collection("signals").where("status", "==", "ACTIVE")
        active_signals = active_signals_ref.count().get()[0][0].value

        # Đếm pending requests
        pending_ref = db.collection("admin").document("requests").collection("pending")
        pending = pending_ref.count().get()[0][0].value

        # Ước tính DAU (users đăng nhập trong 24h qua dựa trên lastSeen)
        from datetime import timedelta
        day_ago = datetime.now(timezone.utc) - timedelta(hours=24)
        dau_ref = db.collection("users").where("lastSeen", ">=", day_ago)
        dau = dau_ref.count().get()[0][0].value

        stats = {
            "dau": max(dau, users_count if users_count < 100 else dau),
            "mau": users_count,
            "growth": round((users_count / max(users_count - trades_today, 1)) * 100 - 100, 1),
            "pendingAlerts": pending + active_signals,
            "totalTrades": trades_today,
            "activeSignals": active_signals,
            "updatedAt": firestore.SERVER_TIMESTAMP,
        }
        db.collection("admin").document("stats").set(stats, merge=True)

        # Ghi vào daily_stats cho analytics chart
        today_key = date.today().strftime("%Y-%m-%d")
        db.collection("admin").document("daily_stats").collection("days").document(today_key).set({
            "dau": max(dau, users_count if users_count < 100 else dau),
            "mau": users_count,
            "trades": trades_today,
            "date": today_key,
        }, merge=True)

        print(f"[ADMIN STATS] Updated: {users_count} users, {trades_today} trades today, {active_signals} signals.")
    except Exception:
        print("[ADMIN STATS] Update failed")


async def _update_admin_stats():
    await asyncio.to_thread(_update_admin_stats_sync)


# ─────────────────────────────────────────────────────────────
# SERVICE STATUS LOOP
# Ping các dịch vụ backend mỗi 60s, ghi vào admin/service_status
# ─────────────────────────────────────────────────────────────

async def service_status_loop():
    """Kiểm tra trạng thái các services mỗi 60 giây."""
    while True:
        try:
            await _check_service_status()
        except Exception:
            print("[SERVICE STATUS] Background cycle failed")
        await asyncio.sleep(60)

async def _check_service_status():
    """Record verified readiness; HTTP reachability alone is not readiness."""
    import time as time_mod
    results = {"ai_online": False, "ai_latency": 0,
               "mt4_online": False, "mt4_latency": 0}

    if DEEPSEEK_API_KEY:
        try:
            t0 = time_mod.monotonic()
            async with httpx.AsyncClient(timeout=5, follow_redirects=False) as client:
                response = await client.get("https://api.deepseek.com/user/balance",
                    headers={"Authorization": "Bearer " + DEEPSEEK_API_KEY})
            results["ai_latency"] = int((time_mod.monotonic() - t0) * 1000)
            if response.status_code == 200:
                balance = response.json()
                results["ai_online"] = isinstance(balance, dict) and balance.get("is_available") is True
        except (httpx.HTTPError, ValueError):
            pass

    # The current MetaApi integration links accounts only; it has no live bridge
    # session to verify. A public root endpoint's 401/404 cannot prove one.
    now = time.monotonic()
    results["data_online"] = any(
        isinstance(price, (int, float)) and not isinstance(price, bool)
        and math.isfinite(price) and price > 0
        and 0 <= now - streamer.price_observed_at.get(symbol, -math.inf) <= 180
        for symbol, price in streamer.last_prices.items()
    )

    # Day 6 — Admin verify analysis cache backend (Redis / memory)
    try:
        results["redis_online"] = analysis_cache.backend == "redis"
        results["redis_backend"] = analysis_cache.backend
        results["master_prompt_cache_ttl_sec"] = _MASTER_PROMPT_CACHE_TTL
    except Exception:
        results["redis_online"] = False
        results["redis_backend"] = "unknown"

    results["updatedAt"] = firestore.SERVER_TIMESTAMP
    service_status_ref = db.collection("admin").document("service_status")
    await asyncio.to_thread(service_status_ref.set, results, merge=True)
    print(
        f"[SERVICE STATUS] AI: {'✅' if results.get('ai_online') else '❌'}, "
        f"MT4: {'✅' if results.get('mt4_online') else '❌'}, "
        f"Data: {'✅' if results.get('data_online') else '❌'}, "
        f"Cache: {results.get('redis_backend')}"
    )




# ─────────────────────────────────────────────────────────────
# NEWS CRAWLER — RSS Feed + Sentiment Engine
# Chạy mỗi 15 phút, push vào Firestore news + analytics/sentiment
# ─────────────────────────────────────────────────────────────

# The approved registry and text-only rights are recorded in official_news.py.

BULLISH_KEYWORDS = [
    'rally', 'surge', 'gain', 'rise', 'bullish', 'breakout', 'higher', 'upside',
    'buy', 'long', 'support', 'recovery', 'strong', 'boost', 'record', 'jump',
    'tăng', 'mua', 'tích cực', 'lạc quan', 'phục hồi', 'vượt'
]
BEARISH_KEYWORDS = [
    'fall', 'drop', 'decline', 'bearish', 'breakdown', 'lower', 'downside',
    'sell', 'short', 'resistance', 'crash', 'weak', 'selloff', 'concern', 'slump',
    'giảm', 'bán', 'tiêu cực', 'bi quan', 'lo ngại', 'áp lực'
]

HIGH_IMPACT_KEYWORDS = [
    'fed', 'fomc', 'nfp', 'non-farm', 'nonfarm', 'payroll', 'cpi', 'ppi',
    'interest rate', 'rate decision', 'ecb', 'boe', 'boj', 'powell',
    'inflation', 'gdp', 'jackson hole', 'qe ', 'tightening', 'hawkish', 'dovish',
]

def _compute_impact(title: str, summary: str) -> str:
    """Day 6 — simple calendar-style impact from headline keywords."""
    text = f"{title} {summary}".lower()
    if any(k in text for k in HIGH_IMPACT_KEYWORDS):
        return "HIGH"
    if any(k in text for k in ('gold', 'xau', 'forex', 'usd', 'oil', 'yield')):
        return "MEDIUM"
    return "LOW"

def _compute_sentiment(title: str, summary: str) -> str:
    text = (title + " " + summary).lower()
    bull = sum(1 for w in BULLISH_KEYWORDS if w in text)
    bear = sum(1 for w in BEARISH_KEYWORDS if w in text)
    if bull > bear:
        return "bullish"
    elif bear > bull:
        return "bearish"
    return "neutral"

def _parse_rss_xml(xml_text: str, source: str, category: str) -> list:
    items = []
    item_matches = re.findall(r'<item>(.*?)</item>', xml_text, re.DOTALL)
    for item_xml in item_matches[:6]:
        title = re.search(r'<title>(?:<!\[CDATA\[)?(.*?)(?:\]\]>)?</title>', item_xml, re.DOTALL)
        link = re.search(r'<link>(.*?)</link>', item_xml, re.DOTALL)
        desc = re.search(r'<description>(?:<!\[CDATA\[)?(.*?)(?:\]\]>)?</description>', item_xml, re.DOTALL)
        pub_date = re.search(r'<pubDate>(.*?)</pubDate>', item_xml, re.DOTALL)

        title_str = re.sub(r'<[^>]+>', '', title.group(1).strip()) if title else ""
        link_str = link.group(1).strip() if link else ""
        desc_str = re.sub(r'<[^>]+>', '', desc.group(1).strip())[:350] if desc else ""
        pub_str = pub_date.group(1).strip() if pub_date else ""

        if len(title_str) < 8:
            continue

        # Extract image URL from enclosure, media:content, or img src tags
        image_url = ""
        enclosure = re.search(r'<enclosure[^>]+url=["\'](.*?)["\']', item_xml, re.IGNORECASE)
        if enclosure:
            image_url = enclosure.group(1)
        else:
            media = re.search(r'<media:content[^>]+url=["\'](.*?)["\']', item_xml, re.IGNORECASE)
            if media:
                image_url = media.group(1)
            else:
                img_src = re.search(r'<img[^>]+src=["\'](.*?)["\']', item_xml, re.IGNORECASE)
                if img_src:
                    image_url = img_src.group(1)

        sentiment = _compute_sentiment(title_str, desc_str)
        impact = _compute_impact(title_str, desc_str)
        sentiment_score = 70 if sentiment == "bullish" else (30 if sentiment == "bearish" else 50)
        if impact == "HIGH":
            sentiment_score = 85 if sentiment == "bullish" else (15 if sentiment == "bearish" else 50)
        article_id = hashlib.md5((title_str + link_str).encode()).hexdigest()
        items.append({
            "id": article_id,
            "title": title_str,
            "summary": desc_str,
            "url": link_str,
            "source": source,
            "category": category,
            "sentiment": sentiment,
            "sentimentScore": sentiment_score,
            "impact": impact,
            "type": "FOREXFACTORY" if impact == "HIGH" else "ALERT",
            "imageUrl": image_url,
            "publishedAt": pub_str,
            "timestamp": firestore.SERVER_TIMESTAMP,
        })
    return items

async def _fetch_og_image(url: str, client: httpx.AsyncClient) -> str:
    """Fetch the og:image meta tag from an article's HTML page."""
    if not url:
        return ""
    try:
        headers = {
            "User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 "
                           "(KHTML, like Gecko) Chrome/124.0 Safari/537.36"
        }
        resp = await client.get(url, headers=headers, timeout=10, follow_redirects=True)
        if resp.status_code != 200:
            return ""
        html_text = resp.text[:50000]  # only read first 50KB — head tags are always near the top
        # og:image
        og = re.search(r'<meta[^>]+property=["\']og:image["\'][^>]+content=["\']([^"\']+)["\']', html_text, re.IGNORECASE)
        if og:
            return og.group(1).strip()
        # twitter:image as fallback
        tw = re.search(r'<meta[^>]+name=["\']twitter:image["\'][^>]+content=["\']([^"\']+)["\']', html_text, re.IGNORECASE)
        if tw:
            return tw.group(1).strip()
        # content= before property= variant
        og2 = re.search(r'<meta[^>]+content=["\']([^"\']+)["\'][^>]+property=["\']og:image["\']', html_text, re.IGNORECASE)
        if og2:
            return og2.group(1).strip()
    except Exception:
        pass
    return ""

async def enrich_articles_with_og_images(articles: list) -> list:
    """For articles that have no image from RSS, fetch og:image from the article URL in parallel."""
    missing = [a for a in articles if not a.get("imageUrl")]
    if not missing:
        return articles
    print(f"🖼️  [News] Fetching og:image for {len(missing)} articles...")
    async with httpx.AsyncClient(timeout=12, follow_redirects=True) as client:
        tasks = [_fetch_og_image(a["url"], client) for a in missing]
        results = await asyncio.gather(*tasks, return_exceptions=True)
    for article, result in zip(missing, results):
        if isinstance(result, str) and result:
            article["imageUrl"] = result
            print(f"   ✅ Got image for: {article['title'][:50]}")
    return articles

async def fetch_rss_feed(feed: dict) -> list:
    if (
        feed not in APPROVED_NEWS_FEEDS
        or feed.get("license_status") != "approved"
        or not str(feed.get("license_ref", "")).strip()
    ):
        return []
    try:
        async with httpx.AsyncClient(timeout=12, follow_redirects=False) as client:
            async with client.stream('GET', feed['url'], headers={'User-Agent': 'ProTradingAI/2.1', 'Accept-Encoding': 'identity'}) as response:
                if response.status_code != 200:
                    return []
                body = bytearray()
                async for chunk in response.aiter_bytes(chunk_size=16384):
                    body.extend(chunk)
                    if len(body) > NEWS_MAX_BYTES:
                        return []
            items = parse_official_feed(body.decode('utf-8-sig'), feed_url=feed['url'],
                                        now_epoch_seconds=int(time.time()))
            print(f"📰 [News] {feed['source']}: {len(items)} official releases")
            return items
    except (httpx.HTTPError, UnicodeDecodeError):
        print(f"⚠️ [News] {feed['source']} fetch failed")
    return []

async def push_news_to_firestore(articles: list):
    if not articles:
        return
    news_col = db.collection('news')
    pushed = 0
    updated = 0
    for article in articles:
        doc_id = article.get('id')
        if not doc_id:
            continue
        try:
            doc_ref = news_col.document(doc_id)
            existing = await asyncio.to_thread(doc_ref.get)
            if not existing.exists:
                await asyncio.to_thread(doc_ref.set, {key: value for key, value in article.items() if key != 'id'})
                pushed += 1
            else:
                # If the existing doc has no imageUrl but we now have one, update it
                existing_data = existing.to_dict() or {}
                if not existing_data.get('imageUrl') and article.get('imageUrl'):
                    await asyncio.to_thread(
                        doc_ref.update,
                        {'imageUrl': article['imageUrl']},
                    )
                    updated += 1
        except Exception:
            print("⚠️ [News] Firestore write failed")
    print(f"✅ [News] Pushed {pushed} new + updated {updated} images in Firestore")

async def update_sentiment_pulse(articles: list):
    if not articles:
        return
    counts = {"bullish": 0, "bearish": 0, "neutral": 0}
    for a in articles:
        s = a.get("sentiment", "neutral")
        counts[s] = counts.get(s, 0) + 1
    total = sum(counts.values()) or 1
    bull_pct = round(counts["bullish"] / total * 100)
    bear_pct = round(counts["bearish"] / total * 100)
    neutral_pct = 100 - bull_pct - bear_pct

    greed_index = bull_pct
    if greed_index >= 60:
        mood = "GREED"
        mood_label = "Bullish"
    elif greed_index <= 35:
        mood = "FEAR"
        mood_label = "Bearish"
    else:
        mood = "NEUTRAL"
        mood_label = "Neutral"

    sentiment_ref = db.collection('analytics').document('sentiment')
    await asyncio.to_thread(sentiment_ref.set, {
        "bullish": bull_pct,
        "bearish": bear_pct,
        "neutral": neutral_pct,
        "fearGreedIndex": greed_index,
        "mood": mood,
        "moodLabel": mood_label,
        "updatedAt": firestore.SERVER_TIMESTAMP,
        "articleCount": len(articles)
    })
    print(f"📊 [Sentiment] Bullish:{bull_pct}% Bearish:{bear_pct}% Neutral:{neutral_pct}% → {mood}")

async def news_crawler_loop():
    """Background task: crawl news mỗi 15 phút."""
    print("🚀 [News Crawler] Starting...")
    # Crawl ngay lần đầu khi khởi động
    await asyncio.sleep(5)
    while True:
        try:
            print("🔄 [News Crawler] Fetching RSS feeds...")
            all_articles = []
            tasks = [asyncio.wait_for(fetch_rss_feed(feed), timeout=15) for feed in APPROVED_NEWS_FEEDS]
            results = await asyncio.gather(*tasks, return_exceptions=True)
            for r in results:
                if isinstance(r, list):
                    all_articles.extend(r)

            if all_articles:
                all_articles = list({article['id']: article for article in all_articles}.values())
                await push_news_to_firestore(all_articles)
                # Official releases supply no social mentions or broker impact rating.
            else:
                print("⚠️ [News Crawler] No articles fetched.")
        except Exception:
            print("❌ [News Crawler] Update cycle failed")

        await asyncio.sleep(900)  # 15 phút


@app.get("/")
async def root():
    return {
        "status": "online",
        "service": "ProTrading AI Data Engine",
        "version": "2.1",
        "sprint": "v21-day7",
        "websocket_endpoint": "/ws/trading",
    }

@app.get("/health")
async def health():
    return {
        "status": "ok",
        "version": "2.1",
        "sprint": "v21-day7",
        "analysis_cache": analysis_cache.backend,
        "redis_url_set": bool(os.environ.get("REDIS_URL", "").strip()),
        "deepseek_configured": bool(DEEPSEEK_API_KEY),
        "master_prompt_cache_ttl_sec": _MASTER_PROMPT_CACHE_TTL,
    }

@app.get("/api/image-proxy")
async def image_proxy(url: str):
    """
    Proxy external images to bypass CORS restrictions on Flutter Web.
    Usage: /api/image-proxy?url=https://example.com/image.jpg
    """
    if LOCAL_QA_MODE or not url:
        return Response(status_code=400)
    try:
        headers = {
            "User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36",
            "Accept": "image/webp,image/apng,image/*,*/*;q=0.8",
        }
        current_url = url
        content = b""
        content_type = ""
        async with httpx.AsyncClient(timeout=15, follow_redirects=False) as client:
            for _ in range(4):
                current_url = await validate_public_https_url(current_url)
                async with client.stream("GET", current_url, headers=headers) as resp:
                    if 300 <= resp.status_code < 400:
                        location = resp.headers.get("location", "")
                        if not location:
                            return Response(status_code=404)
                        current_url = urljoin(current_url, location)
                        continue
                    if resp.status_code != 200:
                        return Response(status_code=404)
                    content_type = resp.headers.get("content-type", "").split(";", 1)[0].strip().lower()
                    if not content_type.startswith("image/"):
                        return Response(status_code=415)
                    declared_size = int(resp.headers.get("content-length", "0") or 0)
                    if declared_size > 5 * 1024 * 1024:
                        return Response(status_code=413)
                    chunks = []
                    total = 0
                    async for chunk in resp.aiter_bytes():
                        total += len(chunk)
                        if total > 5 * 1024 * 1024:
                            return Response(status_code=413)
                        chunks.append(chunk)
                    content = b"".join(chunks)
                    break
            else:
                return Response(status_code=404)
        return Response(
            content=content,
            media_type=content_type,
            headers={
                "Cache-Control": "public, max-age=86400",
            },
        )
    except UnsafeExternalUrl:
        return Response(status_code=400)
    except Exception:
        print("[ImageProxy] Fetch failed")
        return Response(status_code=502)

@cloud_firestore.transactional
def commit_community_like(transaction, post_ref, user_id: str) -> dict:
    """Count one like per verified UID, including concurrent/retried requests."""
    post = post_ref.get(transaction=transaction)
    if not post.exists:
        raise HTTPException(status_code=404, detail="Community post unavailable")
    post_data = post.to_dict() or {}
    count = post_data.get("likes", 0)
    if not isinstance(count, int) or isinstance(count, bool) or count < 0:
        raise HTTPException(status_code=409, detail="Community post unavailable")
    marker_ref = post_ref.collection("likes").document(user_id)
    marker = marker_ref.get(transaction=transaction)
    if marker.exists:
        return {"liked": True, "alreadyLiked": True, "likes": count}
    transaction.create(marker_ref, {
        "userId": user_id,
        "createdAt": firestore.SERVER_TIMESTAMP,
    })
    transaction.update(post_ref, {"likes": count + 1})
    return {"liked": True, "alreadyLiked": False, "likes": count + 1}


@app.post("/api/community/like")
async def like_community_post(
    req: CommunityLikeRequest,
    authorization: str | None = Header(default=None),
):
    user_id = await verified_user_id(authorization, req.userId)
    if not re.fullmatch(r"[A-Za-z0-9_-]{1,128}", req.postId):
        raise HTTPException(status_code=422, detail="Invalid community post ID")
    post_ref = db.collection("community").document(req.postId)
    return await asyncio.to_thread(
        commit_community_like, db.transaction(), post_ref, user_id
    )


@app.post("/api/account/link")
async def link_account(
    req: LinkAccountRequest,
    authorization: str | None = Header(default=None),
):
    """Link a broker account for the verified Firebase user only."""
    user_id = await verified_user_id(
        authorization, req.userId, required_role="verified_partner",
    )
    if LOCAL_QA_MODE:
        raise HTTPException(status_code=503, detail="Broker linking is unavailable in local QA")
    print("SERVER: Linking broker account")
    try:
        api = MetaApi(META_API_TOKEN)
        # Create MetaApi account
        account = await api.metatrader_account_api.create_account({
            'name': f"User_{user_id[-6:]}",
            'type': 'cloud',
            'login': req.login,
            'password': req.password,
            'server': req.server,
            'platform': req.platform,
            'magic': 202604  # ProTrading Magic Number
        })
        
        account_id = account['id']
        print("SERVER: MetaApi account created")

        # Save to Firestore
        broker_account_ref = db.collection('users').document(user_id).collection('broker_accounts').document(account_id)
        await asyncio.to_thread(broker_account_ref.set, {
            'platform': req.platform,
            'server': req.server,
            'login': req.login,
            'status': 'PENDING',
            'createdAt': firestore.SERVER_TIMESTAMP
        })

        return {"status": "success", "accountId": account_id}
    except Exception:
        print("SERVER: Broker account link failed")
        return {"status": "error", "message": "Unable to link broker account. Please try again."}

@cloud_firestore.transactional
def create_current_paper_trade(
    transaction, trade_ref, signal_ref, cutoff_ref, user_id: str,
    request_data: dict, request_hash: str, trade_id: str,
):
    """Atomically prove the signal is still current and create one paper order."""
    previous = trade_ref.get(transaction=transaction)
    if previous.exists:
        old = previous.to_dict() or {}
        if old.get('_requestHash') != request_hash:
            raise HTTPException(status_code=409, detail="Idempotency key reused")
        return False, old
    cutoff_snapshot = cutoff_ref.get(transaction=transaction)
    if cutoff_active(
        cutoff_snapshot.to_dict() if cutoff_snapshot.exists else None,
        datetime.now(timezone.utc),
    ):
        raise HTTPException(status_code=403, detail="Daily loss cutoff active")
    current = signal_ref.get(transaction=transaction)
    sym = validate_trade_intent(
        user_id, request_data, current.to_dict() if current.exists else None,
        now=time.time(),
    )
    targets = request_data['tpPrices']
    entry_price = request_data['entryPrice']
    trade_data = {
        'id': trade_id,
        'symbol': sym,
        'type': request_data['action'],
        'lotSize': request_data['volume'],
        'openPrice': entry_price,
        'currentPrice': entry_price,
        'sl': request_data['slPrice'],
        'tp': targets[0],
        'tpLevels': targets,
        'profit': 0.0,
        'status': 'OPEN',
        'tradingMode': request_data['tradingMode'],
        'signalId': request_data['signalId'],
        'signalChartId': request_data['signalChartId'],
        '_requestHash': request_hash,
        'openTime': firestore.SERVER_TIMESTAMP,
    }
    transaction.create(trade_ref, trade_data)
    return True, trade_data


def _cutoff_ref(user_id: str):
    return db.collection('users').document(user_id).collection('risk_state').document('daily_cutoff')


async def require_cutoff_unlocked(user_id: str) -> None:
    if not user_id:
        raise HTTPException(status_code=403, detail="User identity required")
    snapshot = await asyncio.to_thread(_cutoff_ref(user_id).get)
    if cutoff_active(
        snapshot.to_dict() if snapshot.exists else None,
        datetime.now(timezone.utc),
    ):
        raise HTTPException(status_code=403, detail="Daily loss cutoff active")


def _cutoff_public_state(state: dict | None) -> dict:
    if not state or state.get('active') is not True:
        return {'active': False}
    now = datetime.now(timezone.utc)
    return {
        'active': cutoff_active(state, now),
        'sessionDate': state.get('sessionDate'),
        'realizedPnl': state.get('realizedPnl'),
        'floatingPnl': state.get('floatingPnl'),
        'totalPnl': state.get('totalPnl'),
        'lossLimit': state.get('lossLimit'),
        'reviewed': bool(state.get('reviewedAt')),
        'acknowledged': bool(state.get('acknowledgedAt')),
    }


@cloud_firestore.transactional
def record_cutoff_review(transaction, cutoff_ref):
    snapshot = cutoff_ref.get(transaction=transaction)
    state = snapshot.to_dict() if snapshot.exists else None
    if not state or state.get('active') is not True:
        raise HTTPException(status_code=404, detail="Cutoff review unavailable")
    if not state.get('reviewedAt'):
        transaction.update(cutoff_ref, {'reviewedAt': firestore.SERVER_TIMESTAMP})
        state = {**state, 'reviewedAt': True}
    return _cutoff_public_state(state)


@cloud_firestore.transactional
def record_cutoff_acknowledgement(transaction, cutoff_ref):
    snapshot = cutoff_ref.get(transaction=transaction)
    state = snapshot.to_dict() if snapshot.exists else None
    if not state or not state.get('reviewedAt'):
        raise HTTPException(status_code=409, detail="Cutoff review required")
    if not state.get('acknowledgedAt'):
        transaction.update(cutoff_ref, {'acknowledgedAt': firestore.SERVER_TIMESTAMP})
        state = {**state, 'acknowledgedAt': True}
    return _cutoff_public_state(state)


@app.get("/api/risk/cutoff/{user_id}")
async def get_cutoff_state(
    user_id: str, authorization: str | None = Header(default=None),
):
    owner = await verified_user_id(authorization, user_id)
    try:
        await require_daily_loss_capacity(owner)
    except HTTPException as error:
        if error.detail != "Daily loss cutoff active":
            raise
    snapshot = await asyncio.to_thread(_cutoff_ref(owner).get)
    return _cutoff_public_state(snapshot.to_dict() if snapshot.exists else None)


@app.post("/api/risk/cutoff/review")
async def review_cutoff(
    req: CutoffOwnerRequest, authorization: str | None = Header(default=None),
):
    owner = await verified_user_id(authorization, req.userId)
    return await asyncio.to_thread(
        record_cutoff_review, db.transaction(), _cutoff_ref(owner)
    )


@app.post("/api/risk/cutoff/ack")
async def acknowledge_cutoff(
    req: CutoffOwnerRequest, authorization: str | None = Header(default=None),
):
    owner = await verified_user_id(authorization, req.userId)
    return await asyncio.to_thread(
        record_cutoff_acknowledgement, db.transaction(), _cutoff_ref(owner)
    )


@cloud_firestore.transactional
def persist_daily_loss_cutoff(transaction, cutoff_ref, decision, now: datetime):
    existing = cutoff_ref.get(transaction=transaction)
    state = existing.to_dict() if existing.exists else None
    if cutoff_active(state, now):
        return
    transaction.set(cutoff_ref, {
        'active': True,
        'sessionDate': utc_session(now),
        'realizedPnl': decision.realized_pnl,
        'floatingPnl': decision.floating_pnl,
        'totalPnl': decision.total_pnl,
        'lossLimit': decision.loss_limit,
        'reviewedAt': None,
        'acknowledgedAt': None,
        'trippedAt': firestore.SERVER_TIMESTAMP,
    })


async def require_daily_loss_capacity(user_id: str, *, now: float | None = None) -> None:
    """Fail closed when authoritative paper-trade loss reaches the user's limit."""
    await require_cutoff_unlocked(user_id)
    risk_ref = (
        db.collection('users').document(user_id)
        .collection('settings').document('risk_config')
    )
    risk_snapshot = await asyncio.to_thread(risk_ref.get)
    if not risk_snapshot.exists:
        raise HTTPException(status_code=403, detail="Risk configuration required")
    risk = risk_snapshot.to_dict() or {}

    trades_ref = db.collection('users').document(user_id).collection('trades')
    trades = await asyncio.to_thread(trades_ref.get)
    utc_today = datetime.fromtimestamp(now or time.time(), timezone.utc).date()
    realized = 0.0
    floating = 0.0
    for trade in trades:
        data = trade.to_dict() or {}
        status = str(data.get('status', '')).upper()
        if status == 'CLOSED':
            closed_at = data.get('closeTime')
            if not isinstance(closed_at, datetime) or closed_at.astimezone(timezone.utc).date() != utc_today:
                continue
            realized += float(data.get('netProfit', data.get('profit', 0)) or 0)
            continue
        if status != 'OPEN':
            continue
        symbol = normalize_symbol(data.get('symbol', ''))
        mark = await streamer.get_price(symbol)
        if mark <= 0:
            raise HTTPException(status_code=503, detail="Risk state unavailable")
        floating += calc_pnl(
            symbol,
            data.get('type', 'BUY'),
            float(data.get('openPrice', 0) or 0),
            mark,
            float(data.get('lotSize', 0) or 0),
        )

    try:
        decision = evaluate_daily_loss(
            balance=float(risk.get('balance', 0) or 0),
            max_daily_loss_percent=float(risk.get('maxDailyLoss', 0) or 0),
            realized_pnl=realized,
            floating_pnl=floating,
        )
    except (DailyLossPolicyError, TypeError, ValueError):
        raise HTTPException(status_code=403, detail="Valid risk configuration required") from None
    if decision.blocked:
        await asyncio.to_thread(
            persist_daily_loss_cutoff,
            db.transaction(), _cutoff_ref(user_id), decision,
            datetime.fromtimestamp(now if now is not None else time.time(), timezone.utc),
        )
        raise HTTPException(status_code=403, detail="Daily loss cutoff active")


@app.post("/api/trade")
async def execute_trade(
    req: TradeRequest,
    authorization: str | None = Header(default=None),
    idempotency_key: str | None = Header(default=None, alias="Idempotency-Key"),
):
    """Create one authenticated, signal-authorized paper trade per intent."""
    metric_timer = operation_recorder.start(Operation.PAPER_EXECUTION)
    try:
        user_id = await verified_user_id(authorization, req.userId)
        try:
            trade_id = trade_document_id(user_id, idempotency_key)
        except TradeDenied:
            raise HTTPException(status_code=422, detail="Invalid idempotency key") from None
        if not re.fullmatch(r"[A-Za-z0-9_-]{1,128}", req.signalId):
            raise HTTPException(status_code=422, detail="Invalid signal ID")
        request_hash = hashlib.sha256(
            json.dumps(req.model_dump(exclude={"userId"}), sort_keys=True, separators=(",", ":")).encode()
        ).hexdigest()
        trade_ref = db.collection('users').document(user_id).collection('trades').document(trade_id)
        existing = await asyncio.to_thread(trade_ref.get)
        if existing.exists:
            old = existing.to_dict() or {}
            if old.get('_requestHash') != request_hash:
                raise HTTPException(status_code=409, detail="Idempotency key reused")
            return {"status": "success", "tradeId": trade_id, "entryPrice": old['openPrice'], "symbol": old['symbol']}
        await require_backend_operation(BackendOperation.EXECUTION)
        await require_daily_loss_capacity(user_id)
        signal_ref = db.collection('signals').document(req.signalId)
        try:
            created, saved = await asyncio.to_thread(
                create_current_paper_trade, db.transaction(), trade_ref, signal_ref,
                _cutoff_ref(user_id),
                user_id, req.model_dump(), request_hash, trade_id,
            )
        except TradeDenied:
            raise HTTPException(status_code=403, detail="No current Hard Setup for this order") from None
        except Conflict:
            existing = await asyncio.to_thread(trade_ref.get)
            old = existing.to_dict() if existing.exists else {}
            if old.get('_requestHash') != request_hash:
                raise HTTPException(status_code=409, detail="Idempotency key reused") from None
            return {"status": "success", "tradeId": trade_id, "entryPrice": old['openPrice'], "symbol": old['symbol']}
        if created:
            print(f"✅ Paper trade executed for {saved['symbol']}")
        metric_timer.finish(
            outcome=OperationOutcome.SUCCESS,
            fallback=False,
        )
        return {"status": "success", "tradeId": trade_id, "entryPrice": saved['openPrice'], "symbol": saved['symbol']}
    except HTTPException:
        metric_timer.finish(
            outcome=OperationOutcome.FAILURE,
            fallback=False,
            error_code=FailureCode.INTERNAL_ERROR,
        )
        raise
    except Exception:
        metric_timer.finish(
            outcome=OperationOutcome.FAILURE,
            fallback=False,
            error_code=FailureCode.INTERNAL_ERROR,
        )
        print("❌ Paper trade execution failed")
        return {"status": "error", "message": "Trade execution failed. Please retry."}

@app.post("/api/trade/close")
async def close_trade(
    req: CloseTradeRequest,
    authorization: str | None = Header(default=None),
):
    """Close an open trade using that trade's own symbol mark price."""
    user_id = await verified_user_id(authorization, req.userId)
    if not re.fullmatch(r"trade_[A-Za-z0-9_-]{1,128}", req.tradeId):
        raise HTTPException(status_code=422, detail="Invalid trade ID")
    try:
        trade_ref = db.collection('users').document(user_id).collection('trades').document(req.tradeId)
        trade_doc = await asyncio.to_thread(trade_ref.get)
        
        if not trade_doc.exists:
            return {"status": "error", "message": "Trade not found"}
        
        trade_data = trade_doc.to_dict()
        if trade_data.get('status') != 'OPEN':
            return {"status": "error", "message": "Trade is not open"}
        trade_symbol = normalize_symbol(trade_data.get('symbol', 'XAUUSD'))
        close_price = await streamer.get_price(trade_symbol)
        if close_price <= 0:
            return {"status": "error", "message": f"No mark price available for {trade_symbol}"}

        profit = calc_pnl(
            trade_symbol,
            trade_data.get('type', 'BUY'),
            float(trade_data.get('openPrice', 0)),
            close_price,
            float(trade_data.get('lotSize', 0)),
        )

        trade_type = str(trade_data.get('type', 'BUY')).upper()
        journal_action = 'LONG' if trade_type in ('BUY', 'LONG') else 'SHORT'
        entry_price = float(trade_data.get('openPrice', trade_data.get('entryPrice', 0)) or 0)

        # Day 6 — dual-write journal schema alongside execution fields
        await asyncio.to_thread(trade_ref.update, {
            'status': 'CLOSED',
            'closePrice': close_price,
            'currentPrice': close_price,
            'profit': profit,
            'closeTime': firestore.SERVER_TIMESTAMP,
            'action': journal_action,
            'entryPrice': entry_price,
            'exitPrice': close_price,
            'netProfit': profit,
            'swap': float(trade_data.get('swap', 0) or 0),
            'slippage': float(trade_data.get('slippage', 0) or 0),
        })
        
        print(f"✅ Paper trade closed for {trade_symbol}")
        return {"status": "success", "closePrice": close_price, "profit": profit, "symbol": trade_symbol}
    except Exception:
        print("❌ Paper trade close failed")
        return {"status": "error", "message": "Unable to close trade. Please retry."}

@app.post("/api/ai/chat")
async def ai_chat(
    req: AIChatRequest,
    authorization: str | None = Header(default=None),
):
    """Real AI chat using DeepSeek - inject Master Prompt từ Admin config"""
    await verified_user_id(authorization, req.userId)
    if (
        not isinstance(req.message, str)
        or not 1 <= len(req.message.strip()) <= 2000
        or not isinstance(req.symbol, str)
        or re.fullmatch(r"[A-Z0-9._-]{2,20}", req.symbol) is None
        or req.timeframe not in {"5", "15", "60", "240", "1440"}
    ):
        raise HTTPException(status_code=422, detail="Invalid chat request")
    friendly = (
        "Hệ thống AI đang thực hiện phân tích kỹ thuật tạm thời. "
        "Vui lòng thử lại sau vài giây — tín hiệu rule-based vẫn khả dụng trên Trading Room."
    )
    metric_timer = operation_recorder.start(Operation.AI_CHAT)
    try:
        await require_backend_operation(BackendOperation.ANALYSIS)
        if not DEEPSEEK_API_KEY:
            metric_timer.finish(
                outcome=OperationOutcome.FALLBACK,
                fallback=True,
                error_code=FailureCode.PROVIDER_UNAVAILABLE,
            )
            return {
                "status": "error",
                "response": friendly,
                "fallback": True,
                "message": friendly,
            }

        market_context = symbol_bound_chat_context(
            requested_symbol=req.symbol,
            requested_timeframe=req.timeframe,
            chart_symbol=streamer.chart_symbol_clean(),
            chart_timeframe=streamer.interval,
            chart_price=streamer.last_price,
        )

        # ── Lấy Master Prompt từ Admin config (có cache) ──
        master_prompt = await get_chat_master_prompt()

        # ── Ghép context thị trường vào system message ──
        system_prompt = (
            f"{master_prompt}\n\n"
            f"--- DỮ LIỆU THỜI GIAN THỰC ---\n"
            f"Cặp tiền: {req.symbol} | Khung giờ: {req.timeframe}min\n"
            f"{market_context}\n"
            "If live market context is unavailable, do not assert a current price, "
            "candle pattern, or actionable trading level."
        )

        payload = _bounded_llm_request(
            DEEPSEEK_MODEL, [
                {"role": "system", "content": system_prompt},
                {"role": "user", "content": req.message}
            ],
            analysis=False,
        )
        thinking = payload.pop('thinking')
        client = ai_client.with_options(max_retries=0, timeout=20)
        response = await asyncio.to_thread(
            client.chat.completions.create, **payload,
            extra_body={'thinking': thinking},
        )
        usage = getattr(response, 'usage', None)
        _record_llm_usage('chat', usage.model_dump() if usage is not None else None)

        ai_response = response.choices[0].message.content
        metric_timer.finish(
            outcome=OperationOutcome.SUCCESS,
            fallback=False,
        )
        print(f"✅ AI chat completed for {normalize_symbol(req.symbol)}")
        return {"status": "success", "response": ai_response, "fallback": False}
    except Exception:
        metric_timer.finish(
            outcome=OperationOutcome.FAILURE,
            fallback=False,
            error_code=FailureCode.INTERNAL_ERROR,
        )
        print("❌ AI chat request failed")
        # Day 5/7 — never leak stack/exception to clients
        return {
            "status": "error",
            "response": friendly,
            "fallback": True,
            "message": friendly,
        }

@app.post("/api/risk-config")
async def save_risk_config(
    req: RiskConfigRequest,
    authorization: str | None = Header(default=None),
):
    """Save user's risk configuration"""
    user_id = await verified_user_id(authorization, req.userId)
    try:
        config_data = {
            'balance': req.balance,
            'riskPerTrade': req.riskPerTrade,
            'maxDailyLoss': req.maxDailyLoss,
            'updatedAt': firestore.SERVER_TIMESTAMP,
        }
        risk_config_ref = db.collection('users').document(user_id).collection('settings').document('risk_config')
        await asyncio.to_thread(risk_config_ref.set, config_data)
        
        return {"status": "success"}
    except Exception:
        return {"status": "error", "message": "Unable to save risk configuration."}

@app.get("/api/risk-config/{user_id}")
async def get_risk_config(
    user_id: str,
    authorization: str | None = Header(default=None),
):
    """Get user's risk configuration"""
    user_id = await verified_user_id(authorization, user_id)
    try:
        risk_config_ref = db.collection('users').document(user_id).collection('settings').document('risk_config')
        doc = await asyncio.to_thread(risk_config_ref.get)
        if doc.exists:
            return {"status": "success", "config": doc.to_dict()}
        return {"status": "success", "config": None}
    except Exception:
        return {"status": "error", "message": "Unable to load risk configuration."}

@app.get("/api/trades/{user_id}")
async def get_open_trades(
    user_id: str,
    authorization: str | None = Header(default=None),
):
    """Get user's open trades — each position marked with its OWN symbol price."""
    user_id = await verified_user_id(authorization, user_id)
    try:
        trades_query = db.collection('users').document(user_id).collection('trades').where('status', '==', 'OPEN')
        trades = await asyncio.to_thread(trades_query.get)
        trade_list = []
        for trade in trades:
            td = trade.to_dict()
            sym = normalize_symbol(td.get('symbol', 'XAUUSD'))
            mark = await streamer.get_price(sym)
            td['symbol'] = sym
            if mark > 0:
                td['currentPrice'] = mark
                td['profit'] = calc_pnl(
                    sym,
                    td.get('type', 'BUY'),
                    float(td.get('openPrice', 0)),
                    mark,
                    float(td.get('lotSize', 0)),
                )
            else:
                # Keep stored values — never borrow active chart price
                td['currentPrice'] = td.get('currentPrice', td.get('openPrice', 0))
                td['profit'] = td.get('profit', 0.0)
            trade_list.append(td)
        return {"status": "success", "trades": trade_list}
    except Exception:
        return {"status": "error", "message": "Unable to load open trades."}

@app.websocket("/ws/trading")
async def websocket_endpoint(websocket: WebSocket):
    await websocket.accept()
    print("Client Connected")
    # Each browser owns its chart state. Only symbol-bound mark prices are
    # shared, so one connection cannot change another connection's candles.
    session = TradingViewStreamer(shared_last_prices=streamer.last_prices,
                                  shared_price_observed_at=streamer.price_observed_at)
    session.connections.add(websocket)
    # Gửi ngay dữ liệu hiện có
    candles_list = [session.candle_map[t] for t in sorted(session.candle_map.keys())]
    await websocket.send_text(json.dumps({
        "type": "init",
        "symbol": session.chart_symbol_clean(),
        "interval": session.interval,
        "price": session.last_price,
        "prices": session.last_prices,
        "candles": candles_list,
        "account": session.account_info,
    }))
    if not LOCAL_QA_MODE:
        await session.start()
    try:
        while True:
            data = await websocket.receive_text()
            msg = json.loads(data)
            if msg.get("action") == "set_interval":
                interval = str(msg.get("interval", ""))
                if interval not in ALLOWED_TV_INTERVALS:
                    await websocket.send_text(json.dumps({
                        "type": "error", "message": "Unsupported interval",
                    }))
                    continue
                if session.interval == interval:
                    continue
                session.interval = interval
                session.candle_map = {}
                session._pending_delta = {}
                if not LOCAL_QA_MODE:
                    await session.start()
            elif msg.get("action") == "set_symbol":
                sym = normalize_symbol(str(msg.get("symbol", "")))
                tv_symbol = TV_SYMBOL_MAP.get(sym)
                if tv_symbol is None:
                    await websocket.send_text(json.dumps({
                        "type": "error", "message": "Unsupported symbol",
                    }))
                    continue
                if session.symbol == tv_symbol:
                    continue
                session.symbol = tv_symbol
                session.candle_map = {}
                session._pending_delta = {}
                if not LOCAL_QA_MODE:
                    await session.start()
    except WebSocketDisconnect:
        pass
    except (json.JSONDecodeError, TypeError, ValueError):
        print("[WebSocket] Invalid client message")
    finally:
        session.connections.discard(websocket)
        await session.stop()

# ─── Symbol → TradingView mapping (expanded) ───
TV_SYMBOL_MAP = {
    "XAUUSD":  "OANDA:XAUUSD",
    "XAGUSD":  "OANDA:XAGUSD",
    "EURUSD":  "OANDA:EURUSD",
    "GBPUSD":  "OANDA:GBPUSD",
    "USDJPY":  "OANDA:USDJPY",
    "USDCHF":  "OANDA:USDCHF",
    "AUDUSD":  "OANDA:AUDUSD",
    "USDCAD":  "OANDA:USDCAD",
    "NZDUSD":  "OANDA:NZDUSD",
    "EURGBP":  "OANDA:EURGBP",
    "EURJPY":  "OANDA:EURJPY",
    "GBPJPY":  "OANDA:GBPJPY",
    "EURAUD":  "OANDA:EURAUD",
    "GBPAUD":  "OANDA:GBPAUD",
    "AUDNZD":  "OANDA:AUDNZD",
    "CADCHF":  "OANDA:CADCHF",
    "AUDCAD":  "OANDA:AUDCAD",
    "NZDJPY":  "OANDA:NZDJPY",
    "BTCUSD":  "BITSTAMP:BTCUSD",
    "ETHUSD":  "BITSTAMP:ETHUSD",
    "BNBUSD":  "BINANCE:BNBUSDT",
    "SOLUSD":  "BINANCE:SOLUSDT",
    "XRPUSD":  "BITSTAMP:XRPUSD",
    "ADAUSD":  "BINANCE:ADAUSDT",
    "US30":    "FOREXCOM:DJI",
    "US500":   "FOREXCOM:SPX500",
    "US100":   "FOREXCOM:NAS100",
    "UK100":   "FOREXCOM:UK100",
    "DE40":    "FOREXCOM:DE40",
    "JP225":   "FOREXCOM:JPN225",
    "USOIL":   "NYMEX:CL1!",
    "UKOIL":   "ICEEUR:B1!",
    "NGAS":    "NYMEX:NG1!",
    "XPTUSD":  "OANDA:XPTUSD",
}

ALLOWED_TV_INTERVALS = frozenset({"5", "15", "60", "240", "1440"})

if __name__ == "__main__":
    import uvicorn
    port = int(os.environ.get("PORT", 8000))
    uvicorn.run(app, host="0.0.0.0", port=port)
