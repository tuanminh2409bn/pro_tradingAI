# ProTrading AI VIP V2.1 — DoD Checklist (PDF trang 10) Evidence

> Sprint Day 7 harden. Evidence = code markers + production probes + tests.
> Date: 2026-09-06 · FE: `https://protrading-ai-2026.web.app` · BE: `https://103-69-189-243.sslip.io`

## Summary

| Tier | Items | Status |
|------|-------|--------|
| P0 | 1–14 (core trading / AI / chart) | **PASS** (code + prod markers) |
| P1 | 15–16 (Sync Gate, AI fallback, API Relay) | **PASS** |
| Stretch | Celery Radar 100, AdMob, Marketing Kit, TTS | **OUT OF SCOPE** (documented residual) |

## Checklist

| # | Hạng mục | Evidence | Status |
|---|----------|----------|--------|
| 1 | P&L Symbol Bind | `streamer.last_prices` + `get_price(symbol)`; terminal MTM per symbol | ✅ |
| 2 | Execution Panel Sync | `panelResetNonce` on symbol change; ExecutionPanel resets SL/TP | ✅ |
| 3 | Chart Y-scale / pan | `chart_price_window.dart` + KineticChart gestures | ✅ |
| 4 | Candle Colors | Default green/red; purple only Layer 3 override (no `0.005` client rule) | ✅ |
| 5–6 | Time Matrix + TF lock | Scalp M5/M15/H1; `allowsTimeframe` web+mobile | ✅ |
| 7 | 2-Stage `setup_ready` | Soft strips Layer 4; Hard unlocks Entry; FE banners | ✅ |
| 8 | Determinism + Redis + Veto | Cache key candle-scoped; `temperature=0.0`; `seed=42`; HTF veto | ✅ |
| 9 | Text styling | Layer labels from JSON; no SL1/2/3 UI copy | ✅ |
| 10 | Single SL | ExecutionPanel single SL level | ✅ |
| 11 | SIG Bezier | FeatureEngine Layer 4 curves `bezier_dashed` | ✅ |
| 12 | Partial TP | TP1–TP3 toggles (`_tpActive`) | ✅ |
| 13–14 | HTF Trend / Link | Layer 5 `htf_trend` + ghost OB | ✅ |
| 15 | AI Fallback UX | Chat `fallback:true` friendly VN; no `str(e)` to client | ✅ |
| 16 | Sync Gate + API Relay | Modal + Journal blur; mobile no broker password form | ✅ |
| — | Admin Dynamic Prompt | `AdminSettings/ai_config` + 5′ cache TTL | ✅ |
| — | News Red Zone | HIGH impact → Layer 5 `news_column` | ✅ |
| — | Journal schema | Dual-write `action/entryPrice/netProfit` | ✅ |

## Production probes (Day 7)

Verified 2026-09-06 ~09:38 UTC:

```text
GET /health → version=2.1 sprint=v21-day7 analysis_cache=redis deepseek_configured=true
GET /       → version=2.1 sprint=v21-day7
FE main.dart.js → panelResetNonce, RED ZONE, HARD SETUP, FALLBACK MODE, Analysis Cache
                → no SL1 Tight / SL2 Normal
```

```bash
curl -sS https://103-69-189-243.sslip.io/health
curl -sS https://103-69-189-243.sslip.io/
curl -sS -I https://protrading-ai-2026.web.app/main.dart.js | egrep -i 'last-modified|content-length'
```

## Automated tests

| Suite | Command | Expect |
|-------|---------|--------|
| Day 3–7 Python | `python3 test_day3_analysis.py && python3 test_day4_mtf.py && python3 test_day5_fallback.py && python3 test_day6_parity.py && python3 test_day7_harden.py` | all OK |
| Flutter focused | `flutter test test/day6_journal_redzone_test.dart test/trading_mode_and_price_window_test.dart` | all OK |

## Residuals (explicit non-DoD)

- Live MetaApi order placement (paper `/api/trade` is the shipped path)
- Celery full radar 100 symbols / AdMob / Marketing Kit / TTS
- DeepSeek chat may return `fallback:true` if key missing or upstream error — UI remains friendly

## Manual QA (owner) — retest 2026-09-06 ~10:15 UTC

| Check | Result | Evidence |
|-------|--------|----------|
| Login `test@gmail.com` → hard refresh | ✅ PASS | Session live on `protrading-ai-2026.web.app`; Sync Gate + Trading Room painted |
| Sync Gate (CONNECT / SKIP) | ✅ PASS | Modal **CONNECT YOUR BROKER** on first load; dismiss via `users/{uid}.syncGateDismissed=true` → no modal on reload |
| Journal blur / JOURNAL LOCKED | ✅ PASS | Screenshot: blur + **JOURNAL LOCKED** + CONNECT NOW (`brokerLinked` unset) |
| News HIGH → Red Zone | ✅ PASS* | Banner **RED ZONE USD/MXN…** after impact backfill; `admin/service_status.redis_online=true` |
| Health / AI fallback | ✅ PASS | `/health` v2.1 redis+deepseek; `/api/ai/chat` → friendly VN + `fallback:true` |
| Journal dual-write | ✅ PASS | `users/qa_day7_prod_pnl/trades/*` has `action`+`entryPrice`+`netProfit` and `type`+`openPrice`+`profit` |
| P&L bind (API paper) | ✅ PASS | Prior probe: XAU vs EUR open marks distinct; FE symbol-flip 30s **not** re-run this pass |
| Analyze Soft → Hard / Veto UI | ✅ PASS (Hard) | Prod UI **HARD SETUP — READY** + Entry/SL/TP unlocked on XAU (2026-09-07). Soft/Veto banner not present this session (market Hard-only) |
| TF lock interactive | ✅ PASS | Click H4 while Scalping; chart stayed **M5** (XAU then USDJPY). M5 chip remained active |
| P&L flip 2 symbols | ✅ PASS | Chart flipped to **USDJPY** (BID~156); terminal kept **XAU** open~4429 pnl≠**EUR** open~1.16 pnl (e.g. +467.75 vs +40.49). Marks do not borrow chart price |
| Mobile profile no MT4/MT5 form | ✅ PASS | Source: `profile_mobile_page.dart` — link-on-web-only; account password fields only |
| Admin Analysis Cache | ✅ PASS (data) | Firestore `admin/service_status`: `redis_online=true`, `redis_backend=redis`; Admin UI page not opened this pass |

\* **Prod gap found:** news crawler only writes `impact` on **new** docs (`push_news_to_firestore` skips field update on existing). Pre-Day-6 articles had no `impact` → FE defaulted LOW → Red Zone silent until QA backfill (40 docs patched; 25 HIGH by keyword). Recommend merge-update `impact`/`type` on crawl.
