# ProTrading AI VIP V2.1 — Sprint Schedule (updated)

> Cập nhật sau tin khách (Determinism + Redis + FeatureEngine). Day 1 đã PASS trên production.

## Day 1 — DONE
- P0#1 P&L symbol bind, P0#2 panel sync, P0#10 single SL, P0#4 candle colors
- TF matrix + lock (Scalp M5/M15/H1) — một phần P0#5/#6

## Day 2 — Chart UX (hiện tại)
- P0#3 MVP: **Y-scale** (kéo trục giá / wheel trên Y-axis) + **vertical pan** giá; giữ scaleX/pan X
- Reset View reset cả X và Y
- Verify P0#5/#6 TF lock còn đúng trên web Execution chips + top bar
- **Không** làm AI/Redis ở Day 2

## Day 3 — AI Determinism Foundation (contract khách) — IMPLEMENTED

**Mục tiêu:** 0 token khi cache hit; 1 LLM call khi stampede; cùng input → cùng output trong chu kỳ nến.

| # | Task | Chi tiết / DoD |
|---|------|----------------|
| 3.1 | Redis infra | `redis` dependency + `REDIS_URL`; memory fallback nếu chưa có Redis (`deploy/REDIS.md`) |
| 3.2 | Cache key | `analysis:{symbol}:{timeframe}:{last_closed_candle_timestamp}` — **không** gắn `userId` |
| 3.3 | TTL theo TF | M5: 240s; M15: 600s; H1: 2400s (trong khoảng khách yêu cầu) |
| 3.4 | Cache-first path | Hit → trả JSON ngay. Miss → pipeline rồi `SET` cache |
| 3.5 | Stampede lock | Redis `SET NX` / memory holder; waiters `wait_for` cache |
| 3.6 | LLM determinism | `temperature=0.0`; `seed=42` khi API nhận |
| 3.7 | No-random fallback | `build_signal_from_features` — không `random.*` |
| 3.8 | FeatureEngine v1 | Pure Python: Swing, OB, FVG, BOS/CHOCH, ATR — prompt chỉ summary |
| 3.9 | Wire `process_ai_analysis` | Firestore Analyze → cache → lock → features → LLM |

**DoD Day 3:** 2 user bấm Analyze cùng symbol/TF/nến → 1 LLM call; request thứ 2 trong TTL → cùng JSON từ cache; tắt key → fallback không random.

**Files:** `feature_engine.py`, `analysis_cache.py`, `server.py`, `test_day3_analysis.py`

## Day 4 — 2-Stage + Multi-Agent trên nền Day 3 — IMPLEMENTED

| # | Task | Chi tiết / DoD |
|---|------|----------------|
| 4.1 | MTF payload | FE gửi `candles_execution` + `account_context` (+ optional HTF); BE resample HTF nếu thiếu |
| 4.2 | FeatureEngine MTF | `build_mtf_feature_pack` — exec + HTF1/HTF2 |
| 4.3 | 2-Stage `setup_ready` | Soft: strip Layer 4; Hard: Entry/SL/TP khi tap OB/FVG |
| 4.4 | HTF Veto | Opposing HTF OB chứa giá → `veto=true`, freeze BUY/SELL |
| 4.5 | Prompt budget | 1 LLM call Aggregator + MTF feature summary only |

**DoD Day 4:** Analyze không bung Entry khi `setup_ready=false`; VETO khóa lệnh; Redis Day 3 vẫn giữ.

## Day 5 — AI Fallback UX + Sync Gate + API Relay — IMPLEMENTED

| # | Task | Chi tiết / DoD |
|---|------|----------------|
| 5.1 | AI chat fallback | `/api/ai/chat` trả `fallback:true` + message thân thiện VN; không lộ exception |
| 5.2 | FE bubble | `ChatMessage.isFallback` + nhãn FALLBACK MODE trên AI chat |
| 5.3 | News AI soft | `getAISentimentAnalysis` không lộ raw error |
| 5.4 | Sync Gate | Modal CONNECT NOW → Profile; SKIP → `syncGateDismissed` + `manualRiskMode` (risk modal Trading Room) |
| 5.5 | Firestore flags | `users/{uid}`: `brokerLinked`, `syncGateDismissed`, `manualRiskMode`; set `brokerLinked` khi link OK |
| 5.6 | Journal blur | `BrokerLinkGate` khi `!brokerLinked` + CTA CONNECT NOW |
| 5.7 | API Relay mobile | Xóa form MT4/MT5 trên mobile; chỉ hướng dẫn link trên Web |
| 5.8 | Mobile trades | BUY/SELL → `ExecuteTrade` + `LoadTradingData(userId)` |

**DoD Day 5:** Chat lỗi không lộ stack; Sync Gate hiện 1 lần; Journal blur khi chưa link; mobile không form broker.

## Day 6 — Journal / News / Admin verify + mobile parity — IMPLEMENTED

| # | Task | Chi tiết / DoD |
|---|------|----------------|
| 6.1 | Journal schema | Parse `type/openPrice/profit` + dual-write `action/entryPrice/netProfit` khi close |
| 6.2 | News impact | Keyword HIGH (Fed/NFP/CPI…) trên RSS; badge HIGH trên News |
| 6.3 | Red Zone | HIGH news → Layer 5 `news_column` + banner trên Trading Room |
| 6.4 | Admin cache | `service_status` ghi `redis_online/backend`; Admin Services hiện Analysis Cache |
| 6.5 | Mobile parity | TF matrix + mode lock, ExecutionPanel (1 SL / soft-hard), P&L, Red Zone |
| 6.6 | Mobile News | Wire News/Radar/Community tabs (không còn Coming Soon cho News) |

**DoD Day 6:** Journal đọc được lệnh đóng từ `/api/trade`; HIGH news hiện Red Zone; Admin thấy Redis cache; mobile trade parity web.

## Day 7 — Harden + DoD evidence — IMPLEMENTED

| # | Task | Chi tiết / DoD |
|---|------|----------------|
| 7.1 | API version 2.1 | `/` + `/health` report `version=2.1`, `sprint=v21-day7`, `deepseek_configured` |
| 7.2 | Error harden | Trade/link/chat không lộ `str(e)`; chat guard khi thiếu DeepSeek key |
| 7.3 | i18n cleanup | Xóa copy SL1/SL2/SL3 |
| 7.4 | Regression suite | `test_day7_harden.py` + checklist evidence |
| 7.5 | Evidence doc | `docs/DOD_V21_CHECKLIST.md` (PDF trang 10 mapping) |

**DoD Day 7:** Checklist P0/P1 có evidence; prod health 2.1; residual stretch ghi rõ.

## Contract khách (đóng đinh)
```
cache_key = f"analysis:{symbol}:{timeframe}:{last_closed_candle_timestamp}"
HIT  → JSON, 0 token
MISS → FeatureEngine → LLM(temp=0[, seed]) → cache
LOCK → chỉ 1 thread LLM khi stampede
```
TA-Lib optional (binary Docker); MVP = Pandas + pure Python SMC.
