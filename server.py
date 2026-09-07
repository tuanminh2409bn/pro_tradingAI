import json
import time
import random
import string
import re
import asyncio
import os
import hashlib
from datetime import datetime, timezone
from fastapi import FastAPI, WebSocket, WebSocketDisconnect, Request
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel
import websockets
import httpx
from metaapi_cloud_sdk import MetaApi
import firebase_admin
from firebase_admin import credentials, firestore, messaging
from openai import OpenAI
from dotenv import load_dotenv

from analysis_cache import (
    analysis_cache,
    analysis_cache_key,
    ttl_for_timeframe,
)
from feature_engine import (
    apply_stage_gates,
    build_mtf_feature_pack,
    build_signal_from_features,
    candle_interval_sec,
    features_prompt_block,
)

load_dotenv()

# Initialize Firebase Admin
if not firebase_admin._apps:
    try:
        cred = credentials.Certificate("firebase-adminsdk.json")
        firebase_admin.initialize_app(cred)
    except Exception as e:
        print(f"Firebase Local Init Warning: {e}. Trying ApplicationDefault for Cloud Run.")
        try:
            cred = credentials.ApplicationDefault()
            firebase_admin.initialize_app(cred)
        except Exception as e2:
            print(f"Could not init Firebase: {e2}")

db = firestore.client()

DEEPSEEK_API_KEY = os.environ.get("DEEPSEEK_API_KEY", "")
if not DEEPSEEK_API_KEY:
    print("⚠️ DEEPSEEK_API_KEY not set — AI calls will use rule-based fallback")
ai_client = OpenAI(api_key=DEEPSEEK_API_KEY or "sk-missing", base_url="https://api.deepseek.com")

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
_master_prompt_cache: dict = {"prompt": None, "fetched_at": 0}
_MASTER_PROMPT_CACHE_TTL = 300  # 5 phút

async def get_chat_master_prompt() -> str:
    """Lấy master prompt từ Firestore (có cache 5 phút).
    Admin config path: AdminSettings/ai_config → field: ai_master_prompt
    """
    global _master_prompt_cache
    now = time.time()
    # Dùng cache nếu còn hạn
    if _master_prompt_cache["prompt"] and (now - _master_prompt_cache["fetched_at"]) < _MASTER_PROMPT_CACHE_TTL:
        return _master_prompt_cache["prompt"]
    # Fetch từ Firestore
    try:
        config_doc = db.collection('AdminSettings').document('ai_config').get()
        if config_doc.exists:
            data = config_doc.to_dict()
            custom_prompt = data.get('ai_master_prompt', '').strip()
            if len(custom_prompt) > 50:
                _master_prompt_cache["prompt"] = custom_prompt
                _master_prompt_cache["fetched_at"] = now
                print(f"✅ [Master Prompt] Đã load từ Firestore ({len(custom_prompt)} ký tự)")
                return custom_prompt
    except Exception as e:
        print(f"⚠️ [Master Prompt] Lỗi đọc Firestore: {e}")
    # Fallback: prompt mặc định chuyên nghiệp
    default_prompt = (
        "Bạn là ProTrading AI Assistant V3.2 - chuyên gia phân tích kỹ thuật hàng đầu, "
        "thành thạo Smart Money Concepts (SMC), Wyckoff Method, Volume Spread Analysis (VSA). "
        "Phân tích dữ liệu thị trường và đưa ra lời khuyên giao dịch ngắn gọn, thực tế, có cơ sở kỹ thuật. "
        "Trả lời bằng tiếng Việt, dùng bullet points, tối đa 200 từ."
    )
    _master_prompt_cache["prompt"] = default_prompt
    _master_prompt_cache["fetched_at"] = now
    return default_prompt


app = FastAPI()
app.add_middleware(CORSMiddleware, allow_origins=["*"], allow_credentials=True, allow_methods=["*"], allow_headers=["*"])

TV_WS_URL = "wss://data.tradingview.com/socket.io/websocket"
TV_SYMBOL = "OANDA:XAUUSD"
META_API_TOKEN = os.environ.get("META_API_TOKEN", "YOUR_META_API_TOKEN")

class LinkAccountRequest(BaseModel):
    userId: str
    platform: str
    server: str
    login: str
    password: str

class TradeRequest(BaseModel):
    userId: str = ""
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

class CloseTradeRequest(BaseModel):
    userId: str = ""
    tradeId: str

class RiskConfigRequest(BaseModel):
    userId: str
    balance: float
    riskPerTrade: float
    maxDailyLoss: float

class TradingViewStreamer:
    def __init__(self):
        self.candle_map = {}
        self.last_price = 4800.0
        # Independent mark prices per clean symbol — NEVER reuse chart price for other symbols' PnL
        self.last_prices: dict = {"XAUUSD": 4800.0}
        self.account_info = {"balance": 0.0, "equity": 0.0, "margin": 0.0, "leverage": 500}
        self.connections = set()
        self.is_running = False
        self.interval = "5"
        self.symbol = "OANDA:XAUUSD"
        self.ws_task = None
        # ─── Rate limiting & Delta tracking ───
        self._last_broadcast_time = 0.0   # monotonic timestamp of last tick broadcast
        self._pending_delta: dict = {}     # candles changed since last broadcast

    def chart_symbol_clean(self) -> str:
        return normalize_symbol(self.symbol)

    def set_last_price(self, symbol: str, price: float):
        """Bind a mark price to a specific symbol only."""
        if price is None or price <= 0:
            return
        clean = normalize_symbol(symbol)
        self.last_prices[clean] = float(price)
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
        if yahoo:
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
            except Exception as e:
                print(f"[PRICE] Yahoo fallback failed for {clean}: {e}")
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
        if self.ws_task: self.ws_task.cancel()
        self.ws_task = asyncio.create_task(self.stream_data())
        if not hasattr(self, '_heartbeat_task'):
            self._heartbeat_task = asyncio.create_task(self.heartbeat())

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
                            except Exception as e:
                                print(f"Packet Parse Error: {e}")
                                continue
            except Exception as e:
                print(f"Stream Error: {e}")
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
                                "c": float(v_data[4])
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

def send_push_notification_to_all(symbol: str, signal_type: str, entry: float, sl: float, tp: list, probability: int):
    try:
        # 1. Fetch all FCM tokens
        token_docs = db.collection('fcm_tokens').get()
        if not token_docs:
            print("[PUSH] No registered FCM tokens found.")
            return

        tokens_by_user = {}
        for doc in token_docs:
            data = doc.to_dict()
            token = data.get('token')
            user_id = data.get('userId')
            if token and user_id:
                if user_id not in tokens_by_user:
                    tokens_by_user[user_id] = []
                tokens_by_user[user_id].append(token)

        if not tokens_by_user:
            print("[PUSH] No valid token groupings found.")
            return

        # 2. Get user preferences to filter out opt-outs
        target_tokens = []
        for user_id, tokens in tokens_by_user.items():
            user_doc = db.collection('users').document(user_id).get()
            if user_doc.exists:
                user_data = user_doc.to_dict()
                push_enabled = user_data.get('pushNotificationsEnabled', True)
                if not push_enabled:
                    print(f"[PUSH] User {user_id} has push notifications disabled. Skipping.")
                    continue
            target_tokens.extend(tokens)

        if not target_tokens:
            print("[PUSH] No users with push notifications enabled.")
            return

        # 3. Create the payload
        tp_str = ", ".join([str(t) for t in tp]) if tp else "N/A"
        title = f"🆕 TÍN HIỆU {signal_type} MỚI - {symbol}"
        body = f"AI đề xuất lệnh {signal_type} tại vùng giá {entry}. Cắt lỗ tại {sl}. Chốt lời tại {tp_str}. Độ tin cậy {probability}%."

        print(f"[PUSH] Sending notification to {len(target_tokens)} tokens...")
        
        # 4. Construct Multicast message
        message = messaging.MulticastMessage(
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
                    print(f"[PUSH] Failed token (will delete): {failed_token} - Error: {resp.exception}")
                    try:
                        db.collection('fcm_tokens').document(failed_token).delete()
                    except Exception as e:
                        print(f"[PUSH] Error deleting failed token: {e}")

    except Exception as e:
        print(f"❌ [PUSH] Error sending notifications: {e}")

DEFAULT_MASTER_PROMPT = """You are an AI trading Aggregator coordinating Execution / HTF1 / HTF2 agents (SMC, Wyckoff, VSA).

You receive PRECOMPUTED multi-timeframe feature summaries only. Do NOT invent OHLC series.

Return JSON with EXACT keys:
{
  "symbol": "XAUUSD",
  "type": "BUY" or "SELL",
  "entryPrice": number,
  "slPrice": number,
  "tpPrices": [TP1, TP2, TP3],
  "probability": 0-100,
  "setup_ready": boolean,
  "veto": boolean,
  "veto_data": object|null,
  "fallback": false,
  "forecast_text": string,
  "layers": [ /* layers 1-5 */ ]
}

RULES:
- Respect SETUP_READY and VETO from features: if setup_ready=false OR veto=true, OMIT layer 4 (no Entry/SL/TP/SIG curves).
- If veto=true, type may still reflect bias but forecast_text must explain HTF freeze.
- Prices must align with CURRENT_PRICE and feature levels
- Layer 4 only when setup_ready=true and veto=false
- Timestamps are Unix seconds; SIG_1=3 points, SIG_2=4 points
- Prefer BIAS from execution features; keep output deterministic
"""


def _normalize_candle_list(raw) -> list:
    out = []
    if not isinstance(raw, list):
        return out
    for c in raw:
        if not isinstance(c, dict):
            continue
        try:
            out.append({
                "t": int(c.get("t") or c.get("time") or 0),
                "o": float(c.get("o") if c.get("o") is not None else c.get("open")),
                "h": float(c.get("h") if c.get("h") is not None else c.get("high")),
                "l": float(c.get("l") if c.get("l") is not None else c.get("low")),
                "c": float(c.get("c") if c.get("c") is not None else c.get("close")),
            })
        except (TypeError, ValueError):
            continue
    return [x for x in out if x["t"] > 0]


def _streamer_candles_list() -> list:
    return [streamer.candle_map[t] for t in sorted(streamer.candle_map.keys())]


async def _run_analysis_pipeline(symbol: str, timeframe: str, features: dict) -> dict:
    """LLM (temp=0) or deterministic FeatureEngine fallback. No random.*."""
    config_record = db.collection('AdminSettings').document('ai_config').get()
    master_prompt = DEFAULT_MASTER_PROMPT
    if config_record.exists and 'ai_master_prompt' in config_record.to_dict():
        custom_prompt = config_record.to_dict()['ai_master_prompt']
        if custom_prompt and len(custom_prompt.strip()) > 50:
            master_prompt = custom_prompt

    gate = {
        "setup_ready": bool(features.get("setup_ready")),
        "veto": bool(features.get("veto")),
        "veto_data": features.get("veto_data"),
    }

    if not DEEPSEEK_API_KEY:
        print("[AI Engine] No DEEPSEEK_API_KEY — rule-based fallback")
        return build_signal_from_features(features)

    interval = int(features.get("candle_interval_sec") or candle_interval_sec(timeframe))
    prompt_content = f"""Multi-Agent Aggregator — use ONLY this feature pack:

{features_prompt_block(features)}

CANDLE INTERVAL: {interval} seconds
ACCOUNT_CONTEXT: {features.get('account_context')}

Generate COMPLETE analysis JSON.
- If SETUP_READY is false OR VETO is true: do NOT include layer 4.
- entryPrice near {features.get('current_price')} when hard setup
- Map Layer 1 to ORDER_BLOCKS / structure; Layer 5 HTF from HTF1/HTF2 summaries
"""
    try:
        print("Calling DeepSeek API (temperature=0, MTF feature summary)...")
        create_kwargs = dict(
            model="deepseek-chat",
            messages=[
                {"role": "system", "content": master_prompt},
                {"role": "user", "content": prompt_content},
            ],
            response_format={"type": "json_object"},
            temperature=0.0,
        )
        try:
            response = ai_client.chat.completions.create(**create_kwargs, seed=42)
        except TypeError:
            response = ai_client.chat.completions.create(**create_kwargs)
        ai_result = json.loads(response.choices[0].message.content)
        ai_result["fallback"] = False
        ai_result = apply_stage_gates(ai_result, gate)
        print(
            f"✅ DeepSeek analysis layers={len(ai_result.get('layers', []))} "
            f"setup_ready={ai_result.get('setup_ready')} veto={ai_result.get('veto')}"
        )
        return ai_result
    except Exception as e:
        print(f"DeepSeek API Error: {e}. Using deterministic FeatureEngine fallback.")
        return build_signal_from_features(features)


async def process_ai_analysis(doc_id, symbol, timeframe, user_id='', req_payload: dict | None = None):
    """
    Day 3+4:
      cache_key = analysis:{symbol}:{tf}:{last_closed_candle_timestamp}
      MTF FeatureEngine → setup_ready / veto → LLM(temp=0) → cache
    """
    try:
        print(f"⏳ [AI Engine] Processing {symbol} ({timeframe})...")
        doc_ref = db.collection('analysis_requests').document(doc_id)
        doc_ref.update({'status': 'PROCESSING'})
        payload = req_payload or {}

        clean_symbol = normalize_symbol(symbol)
        candles_exec = _normalize_candle_list(payload.get("candles_execution"))
        if not candles_exec:
            candles_exec = _streamer_candles_list()
        candles_htf1 = _normalize_candle_list(payload.get("candles_htf_1"))
        candles_htf2 = _normalize_candle_list(payload.get("candles_htf_2"))

        current_price = streamer.get_cached_price(clean_symbol) or streamer.last_price
        if current_price <= 0 and candles_exec:
            current_price = float(candles_exec[-1].get("c") or 0)

        features = build_mtf_feature_pack(
            symbol=clean_symbol,
            timeframe=timeframe,
            candles_execution=candles_exec,
            current_price=float(current_price or 0),
            candles_htf_1=candles_htf1 or None,
            candles_htf_2=candles_htf2 or None,
        )
        features["account_context"] = payload.get("account_context") or {}

        last_closed_ts = int(features["last_closed_candle_timestamp"])
        cache_key = analysis_cache_key(clean_symbol, timeframe, last_closed_ts)
        ttl = ttl_for_timeframe(timeframe)
        cache_hit = False

        ai_result = await analysis_cache.get(cache_key)
        if ai_result is not None:
            cache_hit = True
            print(f"⚡ [AI Cache HIT] {cache_key} backend={analysis_cache.backend}")
        else:
            got_lock = await analysis_cache.acquire_lock(cache_key, ttl=90)
            if not got_lock:
                print(f"⏳ [AI Stampede] waiting on {cache_key}")
                ai_result = await analysis_cache.wait_for(cache_key, timeout_sec=60)
                if ai_result is None:
                    print(f"⚠️ [AI Stampede] timeout — computing fallback for {cache_key}")
                    ai_result = build_signal_from_features(features)
                    await analysis_cache.set(cache_key, ai_result, ttl)
                else:
                    cache_hit = True
                    print(f"⚡ [AI Cache HIT after wait] {cache_key}")
            else:
                try:
                    ai_result = await analysis_cache.get(cache_key)
                    if ai_result is not None:
                        cache_hit = True
                        print(f"⚡ [AI Cache HIT after lock] {cache_key}")
                    else:
                        ai_result = await _run_analysis_pipeline(clean_symbol, timeframe, features)
                        await analysis_cache.set(cache_key, ai_result, ttl)
                        print(
                            f"💾 [AI Cache SET] {cache_key} ttl={ttl}s "
                            f"fallback={ai_result.get('fallback')} setup_ready={ai_result.get('setup_ready')}"
                        )
                finally:
                    await analysis_cache.release_lock(cache_key)

        ai_result = dict(ai_result)
        ai_result["symbol"] = clean_symbol
        ai_result["cache_hit"] = cache_hit
        ai_result["cache_key"] = cache_key
        ai_result["status"] = "ACTIVE"
        ai_result["createdAt"] = firestore.SERVER_TIMESTAMP
        ai_result["userId"] = user_id

        doc_ref.update({
            "status": "COMPLETED",
            "cache_hit": cache_hit,
            "cache_key": cache_key,
            "setup_ready": bool(ai_result.get("setup_ready")),
            "veto": bool(ai_result.get("veto")),
        })

        old_signals_query = db.collection("signals").where("symbol", "==", clean_symbol)
        if user_id:
            old_signals_query = old_signals_query.where("userId", "==", user_id)
        for doc in old_signals_query.get():
            db.collection("signals").document(doc.id).update({"status": "CLOSED"})

        db.collection("signals").add(ai_result)
        print(
            f"✅ AI Signal for {clean_symbol} (user={user_id}, cache_hit={cache_hit}, "
            f"setup_ready={ai_result.get('setup_ready')}, veto={ai_result.get('veto')}) → Firebase"
        )

        try:
            send_push_notification_to_all(
                symbol=clean_symbol,
                signal_type=ai_result.get("type", "BUY"),
                entry=float(ai_result.get("entryPrice", 0.0)),
                sl=float(ai_result.get("slPrice", 0.0)),
                tp=ai_result.get("tpPrices", []),
                probability=int(ai_result.get("probability", 0)),
            )
        except Exception as push_err:
            print(f"FCM Multicast triggering failed: {push_err}")
    except Exception as e:
        print(f"AI Process Error: {e}")
        try:
            db.collection("analysis_requests").document(doc_id).update({"status": "ERROR", "error": str(e)})
        except Exception:
            pass

def on_analysis_request_snapshot(col_snapshot, changes, read_time):
    for change in changes:
        if change.type.name == 'ADDED':
            req_data = change.document.to_dict()
            if req_data.get('status') == 'PENDING':
                symbol = req_data.get('symbol', 'UNKNOWN')
                timeframe = req_data.get('timeframe', 'UNKNOWN')
                doc_id = change.document.id
                user_id = req_data.get('userId', '')
                
                print(f"🔔 [NEW EVENT] Analysis Request: {symbol} ({timeframe}) | User: {user_id} | ID: {doc_id}")
                
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
    await streamer.start()
    db.collection('analysis_requests').on_snapshot(on_analysis_request_snapshot)
    print("SERVER: Listening to Firebase analysis_requests...")
    # Start background loops
    asyncio.create_task(news_crawler_loop())
    print("SERVER: News crawler started.")
    asyncio.create_task(radar_update_loop())
    print("SERVER: Radar update loop started.")
    asyncio.create_task(admin_stats_loop())
    print("SERVER: Admin stats loop started.")
    asyncio.create_task(service_status_loop())
    print("SERVER: Service status loop started.")


# ─────────────────────────────────────────────────────────────
# RADAR UPDATE LOOP
# Cập nhật giá và tín hiệu realtime cho màn hình Radar mỗi 60s
# Ghi vào Firestore collection: radar/{symbol}
# ─────────────────────────────────────────────────────────────

# Danh sách symbols cần theo dõi trên Radar
RADAR_SYMBOLS = [
    {"symbol": "XAUUSD",  "fullName": "Gold / USD",       "tv": "OANDA:XAUUSD"},
    {"symbol": "BTCUSD",  "fullName": "Bitcoin / USD",    "tv": "BITSTAMP:BTCUSD"},
    {"symbol": "EURUSD",  "fullName": "EUR / USD",        "tv": "OANDA:EURUSD"},
    {"symbol": "GBPUSD",  "fullName": "GBP / USD",        "tv": "OANDA:GBPUSD"},
    {"symbol": "USDJPY",  "fullName": "USD / JPY",        "tv": "OANDA:USDJPY"},
    {"symbol": "ETHUSD",  "fullName": "Ethereum / USD",   "tv": "BITSTAMP:ETHUSD"},
    {"symbol": "US100",   "fullName": "Nasdaq 100",       "tv": "FOREXCOM:NAS100"},
    {"symbol": "USOIL",   "fullName": "WTI Crude Oil",    "tv": "NYMEX:CL1!"},
]

# Cache giá trước đó để tính changePercent
_radar_prev_prices: dict = {}

async def radar_update_loop():
    """Cập nhật bảng Radar mỗi 60 giây từ dữ liệu streamer + Yahoo Finance API."""
    await asyncio.sleep(15)  # chờ streamer init xong
    while True:
        try:
            await _update_radar_prices()
        except Exception as e:
            print(f"[RADAR] Error: {e}")
        await asyncio.sleep(60)

async def _update_radar_prices():
    """Fetch giá từ Yahoo Finance cho tất cả Radar symbols và ghi vào Firestore."""
    # Map symbol sang Yahoo Finance ticker
    yahoo_map = {
        "XAUUSD": "GC=F",
        "BTCUSD": "BTC-USD",
        "EURUSD": "EURUSD=X",
        "GBPUSD": "GBPUSD=X",
        "USDJPY": "USDJPY=X",
        "ETHUSD": "ETH-USD",
        "US100":  "NQ=F",
        "USOIL":  "CL=F",
    }
    batch = db.batch()
    updated = 0
    async with httpx.AsyncClient(timeout=15) as client:
        for asset in RADAR_SYMBOLS:
            sym = asset["symbol"]
            yahoo_ticker = yahoo_map.get(sym)
            if not yahoo_ticker:
                continue
            try:
                url = f"https://query1.finance.yahoo.com/v8/finance/chart/{yahoo_ticker}?range=2d&interval=1d"
                resp = await client.get(url, headers={"User-Agent": "Mozilla/5.0 ProTradingAI/2.0"})
                if resp.status_code != 200:
                    continue
                data = resp.json()
                result = data.get("chart", {}).get("result", [])
                if not result:
                    continue
                closes = result[0].get("indicators", {}).get("quote", [{}])[0].get("close", [])
                closes = [c for c in closes if c is not None]
                if len(closes) < 2:
                    continue
                prev_close = closes[-2]
                current_price = closes[-1]
                # Keep independent mark book warm for open-position PnL (P0#1)
                streamer.set_last_price(sym, float(current_price))
                change_pct = ((current_price - prev_close) / prev_close) * 100 if prev_close else 0

                # Tính volatility
                highs = result[0].get("indicators", {}).get("quote", [{}])[0].get("high", [])
                lows = result[0].get("indicators", {}).get("quote", [{}])[0].get("low", [])
                vol_status = "STABLE"
                if highs and lows and len(highs) > 0:
                    day_range = (highs[-1] or 0) - (lows[-1] or 0)
                    vol_pct = (day_range / current_price * 100) if current_price else 0
                    if vol_pct > 1.5:
                        vol_status = "HIGH"
                    elif vol_pct < 0.3:
                        vol_status = "LOW"

                # AI signal dựa trên momentum đơn giản
                if change_pct > 0.5:
                    ai_signal = "BUY"
                    has_ai = True
                elif change_pct < -0.5:
                    ai_signal = "SELL"
                    has_ai = True
                else:
                    ai_signal = "NEUTRAL"
                    has_ai = False

                # Sparkline: lấy 6 giá trị close gần nhất (normalize 0-10)
                raw_spark = closes[-6:] if len(closes) >= 6 else closes
                mn, mx = min(raw_spark), max(raw_spark)
                rng = mx - mn if mx != mn else 1
                sparkline = [round((v - mn) / rng * 10, 1) for v in raw_spark]

                doc_ref = db.collection("radar").document(sym)
                batch.set(doc_ref, {
                    "symbol": sym,
                    "fullName": asset["fullName"],
                    "price": round(current_price, 2 if current_price > 10 else 5),
                    "changePercent": round(change_pct, 2),
                    "volatilityStatus": vol_status,
                    "hasAiConfirmation": has_ai,
                    "aiSignal": ai_signal,
                    "sparklineData": sparkline,
                    "updatedAt": firestore.SERVER_TIMESTAMP,
                }, merge=True)
                updated += 1
            except Exception as e:
                print(f"[RADAR] {sym} fetch error: {e}")
    batch.commit()
    print(f"[RADAR] Updated {updated}/{len(RADAR_SYMBOLS)} symbols in Firestore.")


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
        except Exception as e:
            print(f"[ADMIN STATS] Error: {e}")
        await asyncio.sleep(300)  # 5 phút

async def _update_admin_stats():
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
            "latency": 18,  # ms - Cloud Run latency
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
    except Exception as e:
        print(f"[ADMIN STATS] Update failed: {e}")


# ─────────────────────────────────────────────────────────────
# SERVICE STATUS LOOP
# Ping các dịch vụ backend mỗi 60s, ghi vào admin/service_status
# ─────────────────────────────────────────────────────────────

async def service_status_loop():
    """Kiểm tra trạng thái các services mỗi 60 giây."""
    while True:
        try:
            await _check_service_status()
        except Exception as e:
            print(f"[SERVICE STATUS] Error: {e}")
        await asyncio.sleep(60)

async def _check_service_status():
    """Ping check các services và ghi kết quả vào Firestore."""
    import time as time_mod
    results = {}

    async with httpx.AsyncClient(timeout=10) as client:
        # Check AI Analyzer (DeepSeek API)
        try:
            t0 = time_mod.time()
            resp = await client.get("https://api.deepseek.com/", timeout=5)
            ai_latency = int((time_mod.time() - t0) * 1000)
            results["ai_online"] = True
            results["ai_latency"] = ai_latency
        except Exception:
            results["ai_online"] = False
            results["ai_latency"] = 0

        # Check Data Feeder (self — TradingView WebSocket is running)
        results["data_online"] = len(streamer.connections) >= 0 and streamer.last_price > 0
        results["data_latency"] = 12  # internal latency estimate

        # MT4 Bridge: check if MetaApi endpoint is reachable
        try:
            t0 = time_mod.time()
            resp = await client.get("https://mt-client-api-v1.new-york.agiliumtrade.ai/", timeout=5)
            mt4_latency = int((time_mod.time() - t0) * 1000)
            results["mt4_online"] = resp.status_code < 500
            results["mt4_latency"] = mt4_latency
        except Exception:
            results["mt4_online"] = False
            results["mt4_latency"] = 0

    # Day 6 — Admin verify analysis cache backend (Redis / memory)
    try:
        results["redis_online"] = analysis_cache.backend == "redis"
        results["redis_backend"] = analysis_cache.backend
        results["redis_latency"] = 1 if analysis_cache.backend == "redis" else 0
        results["master_prompt_cache_ttl_sec"] = _MASTER_PROMPT_CACHE_TTL
    except Exception:
        results["redis_online"] = False
        results["redis_backend"] = "unknown"
        results["redis_latency"] = 0

    results["updatedAt"] = firestore.SERVER_TIMESTAMP
    db.collection("admin").document("service_status").set(results, merge=True)
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

RSS_FEEDS = [
    {"url": "https://feeds.finance.yahoo.com/rss/2.0/headline?s=XAUUSD=X&region=US&lang=en-US", "source": "Yahoo Finance", "category": "Market"},
    {"url": "https://www.forexlive.com/feed/news", "source": "ForexLive", "category": "Forex"},
    {"url": "https://www.dailyfx.com/feeds/market-news", "source": "DailyFX", "category": "Analysis"},
    {"url": "https://rss.investing.com/rss/news_25.rss", "source": "Investing.com", "category": "Forex"},
    {"url": "https://www.fxstreet.com/rss/news", "source": "FXStreet", "category": "Forex"},
]

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
    except Exception as e:
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
    try:
        async with httpx.AsyncClient(timeout=12, follow_redirects=True) as client:
            headers = {"User-Agent": "Mozilla/5.0 ProTradingAI/2.0"}
            resp = await client.get(feed["url"], headers=headers)
            if resp.status_code == 200:
                items = _parse_rss_xml(resp.text, feed["source"], feed["category"])
                print(f"📰 [News] {feed['source']}: {len(items)} articles")
                return items
    except Exception as e:
        print(f"⚠️ [News] {feed['source']} error: {e}")
    return []

async def push_news_to_firestore(articles: list):
    if not articles:
        return
    news_col = db.collection('news')
    pushed = 0
    updated = 0
    for article in articles:
        doc_id = article.pop('id', None)
        if not doc_id:
            continue
        try:
            doc_ref = news_col.document(doc_id)
            existing = doc_ref.get()
            if not existing.exists:
                doc_ref.set(article)
                pushed += 1
            else:
                # If the existing doc has no imageUrl but we now have one, update it
                existing_data = existing.to_dict() or {}
                if not existing_data.get('imageUrl') and article.get('imageUrl'):
                    doc_ref.update({'imageUrl': article['imageUrl']})
                    updated += 1
        except Exception as e:
            print(f"⚠️ Firestore write error: {e}")
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

    db.collection('analytics').document('sentiment').set({
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
            tasks = [fetch_rss_feed(feed) for feed in RSS_FEEDS]
            results = await asyncio.gather(*tasks, return_exceptions=True)
            for r in results:
                if isinstance(r, list):
                    all_articles.extend(r)

            if all_articles:
                all_articles = await enrich_articles_with_og_images(all_articles)
                await push_news_to_firestore(all_articles)
                await update_sentiment_pulse(all_articles)
            else:
                print("⚠️ [News Crawler] No articles fetched.")
        except Exception as e:
            print(f"❌ [News Crawler] Error: {e}")

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
    if not url:
        return Response(status_code=400)
    try:
        from fastapi.responses import Response as FastResponse
        headers = {
            "User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36",
            "Accept": "image/webp,image/apng,image/*,*/*;q=0.8",
        }
        async with httpx.AsyncClient(timeout=15, follow_redirects=True) as client:
            resp = await client.get(url, headers=headers)
        if resp.status_code != 200:
            return FastResponse(status_code=404)
        content_type = resp.headers.get("content-type", "image/jpeg")
        return FastResponse(
            content=resp.content,
            media_type=content_type,
            headers={
                "Access-Control-Allow-Origin": "*",
                "Cache-Control": "public, max-age=86400",
            },
        )
    except Exception as e:
        print(f"[ImageProxy] Error fetching {url}: {e}")
        return Response(status_code=502)

@app.post("/api/account/link")
async def link_account(req: LinkAccountRequest):
    print(f"SERVER: Linking account for user {req.userId}")
    try:
        api = MetaApi(META_API_TOKEN)
        # Create MetaApi account
        account = await api.metatrader_account_api.create_account({
            'name': f"User_{req.userId[-6:]}",
            'type': 'cloud',
            'login': req.login,
            'password': req.password,
            'server': req.server,
            'platform': req.platform,
            'magic': 202604  # ProTrading Magic Number
        })
        
        account_id = account['id']
        print(f"SERVER: MetaApi Account Created: {account_id}")

        # Save to Firestore
        db.collection('users').document(req.userId).collection('broker_accounts').document(account_id).set({
            'platform': req.platform,
            'server': req.server,
            'login': req.login,
            'status': 'PENDING',
            'createdAt': firestore.SERVER_TIMESTAMP
        })

        return {"status": "success", "accountId": account_id}
    except Exception as e:
        print(f"SERVER: Link Account Error: {e}")
        return {"status": "error", "message": "Unable to link broker account. Please try again."}

@app.post("/api/trade")
async def execute_trade(req: TradeRequest):
    """Execute a trade and save to Firestore"""
    try:
        trade_id = f"trade_{int(asyncio.get_event_loop().time() * 1000)}"
        sym = normalize_symbol(req.symbol)
        if req.entryPrice > 0:
            entry_price = req.entryPrice
        else:
            entry_price = await streamer.get_price(sym)
        
        trade_data = {
            'id': trade_id,
            'symbol': sym,
            'type': req.action,
            'lotSize': req.volume,
            'openPrice': entry_price,
            'currentPrice': entry_price,
            'sl': req.slPrice,
            'tp': req.tpPrices[0] if req.tpPrices else 0.0,
            'tpLevels': req.tpPrices,
            'profit': 0.0,
            'status': 'OPEN',
            'tradingMode': req.tradingMode,
            'openTime': firestore.SERVER_TIMESTAMP,
        }
        
        # Save to Firestore
        user_id = req.userId if req.userId else 'default'
        db.collection('users').document(user_id).collection('trades').document(trade_id).set(trade_data)
        
        print(f"✅ Trade executed: {req.action} {sym} {req.volume} lots @ {entry_price}")
        return {"status": "success", "tradeId": trade_id, "entryPrice": entry_price, "symbol": sym}
    except Exception as e:
        print(f"❌ Trade Error: {e}")
        return {"status": "error", "message": "Trade execution failed. Please retry."}

@app.post("/api/trade/close")
async def close_trade(req: CloseTradeRequest):
    """Close an open trade using that trade's own symbol mark price."""
    try:
        user_id = req.userId if req.userId else 'default'
        trade_ref = db.collection('users').document(user_id).collection('trades').document(req.tradeId)
        trade_doc = trade_ref.get()
        
        if not trade_doc.exists:
            return {"status": "error", "message": "Trade not found"}
        
        trade_data = trade_doc.to_dict()
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
        trade_ref.update({
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
        
        print(f"✅ Trade closed: {req.tradeId} {trade_symbol} @ {close_price}, Profit: {profit:.2f}")
        return {"status": "success", "closePrice": close_price, "profit": profit, "symbol": trade_symbol}
    except Exception as e:
        print(f"❌ Close Trade Error: {e}")
        return {"status": "error", "message": "Unable to close trade. Please retry."}

@app.post("/api/ai/chat")
async def ai_chat(req: AIChatRequest):
    """Real AI chat using DeepSeek - inject Master Prompt từ Admin config"""
    friendly = (
        "Hệ thống AI đang thực hiện phân tích kỹ thuật tạm thời. "
        "Vui lòng thử lại sau vài giây — tín hiệu rule-based vẫn khả dụng trên Trading Room."
    )
    try:
        if not DEEPSEEK_API_KEY:
            return {
                "status": "error",
                "response": friendly,
                "fallback": True,
                "message": friendly,
            }

        current_price = streamer.last_price
        candles_summary = ""
        sorted_times = sorted(streamer.candle_map.keys())
        if len(sorted_times) >= 20:
            recent = [streamer.candle_map[t] for t in sorted_times[-20:]]
            candles_summary = f"Dữ liệu 5 nến gần nhất (OHLC): {json.dumps(recent[-5:])}"

        # ── Lấy Master Prompt từ Admin config (có cache) ──
        master_prompt = await get_chat_master_prompt()

        # ── Ghép context thị trường vào system message ──
        system_prompt = (
            f"{master_prompt}\n\n"
            f"--- DỮ LIỆU THỜI GIAN THỰC ---\n"
            f"Cặp tiền: {req.symbol} | Khung giờ: {req.timeframe}min\n"
            f"Giá hiện tại: {current_price}\n"
            f"{candles_summary}"
        )

        response = ai_client.chat.completions.create(
            model="deepseek-chat",
            messages=[
                {"role": "system", "content": system_prompt},
                {"role": "user", "content": req.message}
            ],
            max_tokens=600,
            temperature=0.0,
        )

        ai_response = response.choices[0].message.content
        print(f"✅ AI Chat [{req.symbol}]: {req.message[:50]}...")
        return {"status": "success", "response": ai_response, "fallback": False}
    except Exception as e:
        print(f"❌ AI Chat Error: {e}")
        # Day 5/7 — never leak stack/exception to clients
        return {
            "status": "error",
            "response": friendly,
            "fallback": True,
            "message": friendly,
        }

@app.post("/api/risk-config")
async def save_risk_config(req: RiskConfigRequest):
    """Save user's risk configuration"""
    try:
        config_data = {
            'balance': req.balance,
            'riskPerTrade': req.riskPerTrade,
            'maxDailyLoss': req.maxDailyLoss,
            'updatedAt': firestore.SERVER_TIMESTAMP,
        }
        db.collection('users').document(req.userId).collection('settings').document('risk_config').set(config_data)
        
        # Update streamer account info
        streamer.account_info['balance'] = req.balance
        streamer.account_info['equity'] = req.balance
        
        return {"status": "success"}
    except Exception as e:
        return {"status": "error", "message": str(e)}

@app.get("/api/risk-config/{user_id}")
async def get_risk_config(user_id: str):
    """Get user's risk configuration"""
    try:
        doc = db.collection('users').document(user_id).collection('settings').document('risk_config').get()
        if doc.exists:
            return {"status": "success", "config": doc.to_dict()}
        return {"status": "success", "config": None}
    except Exception as e:
        return {"status": "error", "message": str(e)}

@app.get("/api/trades/{user_id}")
async def get_open_trades(user_id: str):
    """Get user's open trades — each position marked with its OWN symbol price."""
    try:
        trades = db.collection('users').document(user_id).collection('trades').where('status', '==', 'OPEN').get()
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
    except Exception as e:
        return {"status": "error", "message": str(e)}

@app.websocket("/ws/trading")
async def websocket_endpoint(websocket: WebSocket):
    await websocket.accept()
    print("Client Connected")
    streamer.connections.add(websocket)
    # Gửi ngay dữ liệu hiện có
    candles_list = [streamer.candle_map[t] for t in sorted(streamer.candle_map.keys())]
    await websocket.send_text(json.dumps({
        "type": "init",
        "symbol": streamer.chart_symbol_clean(),
        "price": streamer.last_price,
        "prices": streamer.last_prices,
        "candles": candles_list,
        "account": streamer.account_info,
    }))
    try:
        while True:
            data = await websocket.receive_text()
            msg = json.loads(data)
            if msg.get("action") == "set_interval":
                streamer.interval = msg["interval"]
                streamer.candle_map = {}
                await streamer.start()
            elif msg.get("action") == "set_symbol":
                sym = normalize_symbol(msg["symbol"])
                streamer.symbol = TV_SYMBOL_MAP.get(sym, f"OANDA:{sym}")
                streamer.candle_map = {}
                # Keep last_prices for other symbols; do not wipe the book
                await streamer.start()
    except:
        streamer.connections.discard(websocket)

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

if __name__ == "__main__":
    import uvicorn
    port = int(os.environ.get("PORT", 8000))
    uvicorn.run(app, host="0.0.0.0", port=port)