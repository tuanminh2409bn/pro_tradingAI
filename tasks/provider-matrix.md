# Web provider matrix — local design, 2026-09-25

> Cập nhật 2026-10-03: backend đã chạy TradingView theo yêu cầu chủ dự án, 21 mã
> Web có dữ liệu được chấp nhận và 10/10 request QA đạt. Xem
> `checkpoint-2026-10-03-web-production-readiness.md` và checkpoint TradingView
> production. Lựa chọn nguồn/runtime không tự xác nhận quyền sử dụng thương mại.

This file records choices, availability and evidence. It contains no credentials.
The project owner delegated local provider choices; provider account access,
redistribution rights and staging checks are still separate facts to verify.

| Flow | Selected source | Local implementation | External/runtime gate |
|---|---|---|---|
| Market history MTF | TradingView anonymous exact-provider series on production; OANDA Practice remains optional adapter | `tradingview_history.py` validates exact closed bars/volume/NY session/DST; `MARKET_HISTORY_PROVIDER=tradingview`. OANDA credentials absent. 21 Web markets accepted, crypto browser QA passed; closed forex/metals fail closed | Commercial/non-display rights, forex open-session comparison and broader markets/load remain unverified |
| Chart/marks | Existing TradingView stream | Separate chart session per WebSocket, shared symbol-bound marks. Analysis uses its own stateless validated history reader | Provider reliability/terms and sustained multi-user load |
| Official news | Federal Reserve Board official RSS, attributed text only | Production reads `press_all`/`press_monetary`; 13 unique articles with real publication timestamps, provenance/freshness, UNRATED impact and absent sentiment. FE excludes unapproved legacy records. See `web-production-news-qa-2026-10-03.json` | [Fed disclaimer](https://www.federalreserve.gov/disclaimer.htm) covers public-domain information with attribution; no images/logos or third-party copyrighted media. This feed is not a high-impact calendar or social sentiment source |
| High-impact calendar | Trading Economics Calendar API | Target selected; UI/news guard remains unavailable without approved adapter and source sample | API account, importance mapping, display/redistribution rights, budget |
| Social sentiment | Official X API | Unavailable; no scraped or fabricated score | API scope, retention terms, budget and live sample |
| AI | Existing DeepSeek integration | Temperature 0, real three-specialist pipeline and deterministic fallback; key read at runtime. Earlier QA returned 402; owner reports top-up. 04/10 read-only GET balance/models with live container key both return 401; its mask does not match the screenshot key. No model call or credential output in this check. Auto-review subsequently rejected Docker credential comparison before execution; specific read approval/location remains pending | Locate/configure the valid website key securely; successful real specialist/aggregator/chat evidence after top-up remains unverified. Separate bounded paid/QA probe awaits approval; do not bypass QA quota or read credentials through a workaround. See `deepseek-readonly-auth-check-2026-10-04.json` |
| TTS Web | Browser `speechSynthesis` | Journal play/stop implemented with `dart:js_interop`; disabled if unsupported or no real insight | Browser audio playback acceptance |
| Web push | Firebase Messaging | Opt-in guard and owner-only signal delivery in backend | Web VAPID config, permitted browser/notification sandbox and deep-link test |
| Broker | MetaApi | Verified Partner claim only for linking; `/api/trade` remains paper | Claim-bearing QA user and sandbox account |
| Referral cash | No provider/policy | Monetary accrual and withdrawal remain unavailable | F1/F2 rates, currency, qualification, settlement, reversal and approval workflow |
| Data Lake | No destination selected | Export disabled | Written consent/retention/deletion policy and approved sink |

Official API contracts and URLs are in `tasks/decisions-v2.1.md`.
