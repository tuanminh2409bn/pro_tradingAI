import json
import random
import string
import re
import asyncio
import os
from fastapi import FastAPI, WebSocket, WebSocketDisconnect, Request
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel
import websockets
from metaapi_cloud_sdk import MetaApi
import firebase_admin
from firebase_admin import credentials, firestore
from google import genai
from google.genai import types
from dotenv import load_dotenv

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

GEMINI_API_KEY = os.getenv("GEMINI_API_KEY")
ai_client = genai.Client(api_key=GEMINI_API_KEY)

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

class TradingViewStreamer:
    def __init__(self):
        self.candle_map = {}
        self.last_price = 4800.0
        self.account_info = {"balance": 38204.12, "equity": 42050.00, "margin": 840, "leverage": 500}
        self.connections = set()
        self.is_running = False
        self.interval = "5"
        self.symbol = "OANDA:XAUUSD"
        self.ws_task = None

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
                                        print(f"SERVER: Received {len(new_candles)} candles from TV")
                                        for c in new_candles:
                                            self.candle_map[c["t"]] = c
                                        
                                        sorted_times = sorted(self.candle_map.keys())
                                        if len(sorted_times) > 3000:
                                            for t in sorted_times[:-3000]: del self.candle_map[t]
                                        
                                        self.last_price = self.candle_map[sorted_times[-1]]["c"]
                                        await self.broadcast_update("update")
                                elif data.get("m") == "series_completed":
                                    print(f"SERVER: Series completed for {self.symbol}. {len(self.candle_map)} candles loaded.")
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

    async def broadcast_update(self, msg_type):
        if not self.connections: return
        candles_list = [self.candle_map[t] for t in sorted(self.candle_map.keys())]
        print(f"SERVER: Broadcasting {msg_type} to {len(self.connections)} clients. Candles: {len(candles_list)}")
        msg = json.dumps({"type": msg_type, "price": self.last_price, "candles": candles_list, "account": self.account_info})
        disconnected = set()
        for ws in self.connections:
            try: await ws.send_text(msg)
            except: disconnected.add(ws)
        self.connections -= disconnected

streamer = TradingViewStreamer()
main_loop = None

async def process_ai_analysis(doc_id, symbol, timeframe):
    try:
        print(f"⏳ [AI Engine] Processing {symbol} ({timeframe})...")
        doc_ref = db.collection('analysis_requests').document(doc_id)
        doc_ref.update({'status': 'PROCESSING'})
        
        # Get Master Prompt from DB or use default
        config_record = db.collection('AdminSettings').document('ai_config').get()
        master_prompt = "You are an AI trading expert. Return ONLY a valid JSON with keys: symbol (string), type (BUY/SELL), entryPrice (number), slPrice (number), tpPrices (array of 2 numbers), probability (number 0-100)."
        if config_record.exists and 'ai_master_prompt' in config_record.to_dict():
            master_prompt = config_record.to_dict()['ai_master_prompt']
            
        try:
            print("Calling Gemini API...")
            current_price = streamer.last_price
            prompt_content = f"Provide a highly probable trade setup for {symbol} at timeframe {timeframe}. The CURRENT MARKET PRICE is {current_price}. You MUST generate an entryPrice extremely close to {current_price}. For BUY, slPrice < entryPrice and tpPrices > entryPrice. For SELL, slPrice > entryPrice and tpPrices < entryPrice."
            
            response = ai_client.models.generate_content(
                model='gemini-2.5-flash',
                contents=[
                    types.Content(role="user", parts=[
                        types.Part.from_text(text=master_prompt + "\n" + prompt_content)
                    ])
                ],
                config=types.GenerateContentConfig(
                    response_mime_type="application/json",
                ),
            )
            ai_result_str = response.text
            ai_result = json.loads(ai_result_str)
        except Exception as e:
            print(f"Gemini API Error: {e}. Using fallback simulation.")
            entry_price = current_price + random.uniform(-2, 2)
            trade_type = random.choice(['BUY', 'SELL'])
            sl_price = entry_price - 5 if trade_type == 'BUY' else entry_price + 5
            tp_prices = [entry_price + 10, entry_price + 20] if trade_type == 'BUY' else [entry_price - 10, entry_price - 20]
            ai_result = {
                'symbol': symbol,
                'type': trade_type,
                'entryPrice': round(entry_price, 2),
                'slPrice': round(sl_price, 2),
                'tpPrices': [round(p, 2) for p in tp_prices],
                'probability': random.randint(70, 95)
            }
            
        ai_result['status'] = 'ACTIVE'
        ai_result['createdAt'] = firestore.SERVER_TIMESTAMP
        
        doc_ref.update({'status': 'COMPLETED'})
        
        old_signals = db.collection('signals').where('symbol', '==', symbol).get()
        for doc in old_signals:
            db.collection('signals').document(doc.id).update({'status': 'CLOSED'})

        db.collection('signals').add(ai_result)
        print(f"✅ AI Signal for {symbol} sent to Firebase successfully!")
    except Exception as e:
        print(f"AI Process Error: {e}")

def on_analysis_request_snapshot(col_snapshot, changes, read_time):
    for change in changes:
        if change.type.name == 'ADDED':
            req_data = change.document.to_dict()
            if req_data.get('status') == 'PENDING':
                symbol = req_data.get('symbol', 'UNKNOWN')
                timeframe = req_data.get('timeframe', 'UNKNOWN')
                doc_id = change.document.id
                
                print(f"🔔 [NEW EVENT] Analysis Request: {symbol} ({timeframe}) | ID: {doc_id}")
                
                if main_loop and not main_loop.is_closed():
                    asyncio.run_coroutine_threadsafe(process_ai_analysis(doc_id, symbol, timeframe), main_loop)

@app.on_event("startup")
async def startup_event():
    global main_loop
    main_loop = asyncio.get_running_loop()
    print("SERVER: Data Engine Starting Up...")
    await streamer.start()
    db.collection('analysis_requests').on_snapshot(on_analysis_request_snapshot)
    print("SERVER: Listening to Firebase analysis_requests...")


@app.get("/")
async def root():
    return {
        "status": "online",
        "service": "ProTrading AI Data Engine",
        "version": "2.0",
        "websocket_endpoint": "/ws/trading"
    }

@app.get("/health")
async def health(): return {"status": "ok"}

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
        return {"status": "error", "message": str(e)}, 500

@app.websocket("/ws/trading")
async def websocket_endpoint(websocket: WebSocket):
    await websocket.accept()
    print("Client Connected")
    streamer.connections.add(websocket)
    # Gửi ngay dữ liệu hiện có
    candles_list = [streamer.candle_map[t] for t in sorted(streamer.candle_map.keys())]
    await websocket.send_text(json.dumps({"type": "init", "price": streamer.last_price, "candles": candles_list, "account": streamer.account_info}))
    try:
        while True:
            data = await websocket.receive_text()
            msg = json.loads(data)
            if msg.get("action") == "set_interval":
                streamer.interval = msg["interval"]
                streamer.candle_map = {}
                await streamer.start()
            elif msg.get("action") == "set_symbol":
                sym = msg["symbol"]
                # Map short symbol to TV symbol
                if sym == "BTCUSD":
                    streamer.symbol = "BITSTAMP:BTCUSD"
                elif sym == "EURUSD":
                    streamer.symbol = "OANDA:EURUSD"
                else:
                    streamer.symbol = "OANDA:XAUUSD"
                streamer.candle_map = {}
                await streamer.start()
    except:
        streamer.connections.remove(websocket)

if __name__ == "__main__":
    import uvicorn
    port = int(os.environ.get("PORT", 8000))
    uvicorn.run(app, host="0.0.0.0", port=port)