# Web provider matrix — local design, 2026-09-25

This file records choices, availability and evidence. It contains no credentials.
The project owner delegated local provider choices; provider account access,
redistribution rights and staging checks are still separate facts to verify.

| Flow | Selected source | Local implementation | External/runtime gate |
|---|---|---|---|
| Market history MTF | OANDA v20 Practice midpoint candles, UTC aligned; `volume` means tick count | `oanda_history.py` fetches three exact closed series with 5 s timeout. `OANDA_PRACTICE_ACCOUNT_ID` and `OANDA_PRACTICE_TOKEN` are read only at runtime; absent/invalid data yields unavailable | Practice account, supported instrument, display rights, provider sample and authenticated browser pass |
| Chart/marks | Existing TradingView stream | Chart display only; never substitutes for trusted OANDA MTF analysis. Paper P&L stays symbol-bound | Provider reliability and terms |
| High-impact calendar | Trading Economics Calendar API | Target selected; UI/news guard remains unavailable without approved adapter and source sample | API account, importance mapping, display/redistribution rights, budget |
| Social sentiment | Official X API | Unavailable; no scraped or fabricated score | API scope, retention terms, budget and live sample |
| AI | Existing DeepSeek integration | Temperature 0 and deterministic fallback; `DEEPSEEK_API_KEY` read at runtime | Account, quota/budget, 402/429 runtime test |
| TTS Web | Browser `speechSynthesis` | Journal play/stop implemented with `dart:js_interop`; disabled if unsupported or no real insight | Browser audio playback acceptance |
| Web push | Firebase Messaging | Opt-in guard and owner-only signal delivery in backend | Web VAPID config, permitted browser/notification sandbox and deep-link test |
| Broker | MetaApi | Verified Partner claim only for linking; `/api/trade` remains paper | Claim-bearing QA user and sandbox account |
| Referral cash | No provider/policy | Monetary accrual and withdrawal remain unavailable | F1/F2 rates, currency, qualification, settlement, reversal and approval workflow |
| Data Lake | No destination selected | Export disabled | Written consent/retention/deletion policy and approved sink |

Official API contracts and URLs are in `tasks/decisions-v2.1.md`.
