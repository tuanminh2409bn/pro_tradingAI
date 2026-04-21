import json
import random
import string
import re
import asyncio
import os
from fastapi import FastAPI, WebSocket, WebSocketDisconnect
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel
import websockets

app = FastAPI()
app.add_middleware(CORSMiddleware, allow_origins=["*"], allow_credentials=True, allow_methods=["*"], allow_headers=["*"])

TV_WS_URL = "wss://data.tradingview.com/socket.io/websocket"
TV_SYMBOL = "OANDA:XAUUSD"

class TradingViewStreamer:
    def __init__(self):
        self.candle_map = {}
        self.last_price = 4800.0
        self.account_info = {"balance": 38204.12, "equity": 42050.00, "margin": 840, "leverage": 500}
        self.connections = set()
        self.is_running = False
        self.interval = "5"
        self.ws_task = None

    def _pack(self, msg):
        return f"~m~{len(msg)}~m~{msg}"

    def _generate_session(self):
        return "cs_" + "".join(random.choice(string.ascii_lowercase) for _ in range(12))

    async def start(self):
        if self.ws_task: self.ws_task.cancel()
        self.ws_task = asyncio.create_task(self.stream_data())
        asyncio.create_task(self.heartbeat())

    async def heartbeat(self):
        """Gửi heartbeat mỗi 10 giây để giữ kết nối Cloud Run luôn mở"""
        while True:
            await self.broadcast_update("heartbeat")
            await asyncio.sleep(10)

    async def stream_data(self):
        self.is_running = True
        print(f"SERVER: Starting Streamer for {TV_SYMBOL}")
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
                    await ws.send(self._pack(json.dumps({"m": "resolve_symbol", "p": [chart_session, "sds_sym_1", f'={{"symbol":"{TV_SYMBOL}","adjustment":"splits","session":"regular"}}']})))
                    await ws.send(self._pack(json.dumps({"m": "create_series", "p": [chart_session, "sds_1", "s1", "sds_sym_1", self.interval, 300, ""]})))

                    async for message in ws:
                        if "~h~" in message:
                            await ws.send(message)
                            continue
                        
                        # Robust parsing for joined messages (~m~len~m~json~m~len~m~json)
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
                                        if len(sorted_times) > 500:
                                            for t in sorted_times[:-500]: del self.candle_map[t]
                                        
                                        self.last_price = self.candle_map[sorted_times[-1]]["c"]
                                        await self.broadcast_update("update")
                                elif data.get("m") == "series_completed":
                                    print(f"SERVER: Series completed for {TV_SYMBOL}. {len(self.candle_map)} candles loaded.")
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

@app.get("/")
async def root():
    return {
        "status": "online",
        "service": "ProTrading AI Data Engine",
        "version": "2.0",
        "websocket_endpoint": "/ws/trading"
    }

@app.on_event("startup")
async def startup_event():
    print("SERVER: Data Engine Starting Up...")
    await streamer.start()

@app.get("/health")
async def health(): return {"status": "ok"}

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
    except:
        streamer.connections.remove(websocket)

if __name__ == "__main__":
    import uvicorn
    port = int(os.environ.get("PORT", 8000))
    uvicorn.run(app, host="0.0.0.0", port=port)
