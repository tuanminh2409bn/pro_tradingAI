# Web local full-stack QA checkpoint — 2026-09-25

This checkpoint uses only loopback Firebase Auth/Firestore Emulators and a
loopback FastAPI process. No production Firebase account, provider account,
credential, Rules deployment, Git push, or VPS cutover was made. Browser QA
data was disposable and existed only in the Emulators.

## Local runtime boundary

- `PROTRADING_LOCAL_QA=1` requires Auth `127.0.0.1:9099`, Firestore
  `127.0.0.1:8080`, and `GCLOUD_PROJECT`. It does not load `.env` or the
  service-account file. Firestore uses anonymous Emulator credentials.
- Local QA disables DeepSeek, OANDA history, Yahoo price fallback, and
  TradingView streams, including WebSocket interval/symbol changes, and
  broker linking. The Web
  build uses `PROTRADING_USE_FIREBASE_EMULATORS=true` and loopback API/WS
  endpoints. This is a fail-closed provider-outage test, not evidence that a
  live market-data provider has been accepted.
- Image proxy returns 400 for malformed/unapproved HTTPS hosts. Local QA
  rejects all image proxy requests; outside QA, exact hosts must be configured
  through `IMAGE_PROXY_ALLOWED_HOSTS`. CORS allowed the QA Web origin.
- The first analysis request before `admin/system_config.tradingEnabled`
  existed failed closed. After a QA-only Emulator fixture set it to `true`,
  Analyze produced an unavailable Soft signal without Layer 4. The fixture
  was not written to production.

## Browser evidence

Final QA Web release `main.dart.js` SHA-256:
`55723172dc497faf2493e74aae25d6bb858dbaf9c214ca11807ac4c29d34c8809909`.
The final source was checked at `http://127.0.0.1:8086/`; the broader tab
flow was checked on the immediately preceding QA build at 8085, before the
last EN/VI copy changes. Both builds used the same backend/Emulator wiring.

- Standard QA account signed in with a real local Auth Emulator token. The
  Admin entry was absent.
- Trading Room showed unavailable market data; BID, ASK and spread now show
  em dashes instead of prices synthesized from zero. Risk configuration was
  saved through FastAPI/Firestore. Analyze with no approved candle provider
  wrote an unavailable signal with `setup_ready=false`, no Layer 4, and no
  paper execution control. M5→M15 did not start an external stream.
- Journal showed zero trades and unavailable audio advice. News showed no
  articles/sentiment. Backtest timed out to its unavailable state without
  provider history. Radar showed unavailable data and a disabled push switch.
  Referral showed no code, reward amounts or transactions. Profile showed no
  broker account and disabled MFA setup.
- Community posted one QA-only item through the browser, liked it via the
  authenticated FastAPI transaction, and retained count 1 after a tab change.
  A repeated like stayed at count 1. The button's per-user "Liked" state
  resets on tab recreation; W24 remains open for that UI restoration.
- Final build showed source-aware AI/News copy in English and Vietnamese;
  Referral's new description was also checked in both languages. Other
  Referral labels remain English in VI mode and are part of W34.

## Verification

- Python discovery with both Emulators: **216/216 passed, no skips**.
- Flutter tests: **120/120 passed**.
- `flutter analyze --no-pub --no-fatal-infos`: exit 0, zero errors/warnings;
  three pre-existing Mobile `activeColor` infos remain.
- Local QA Web release build, `python3 -m py_compile server.py
  http_boundary.py`, and `git diff --check`: passed.
- FastAPI runtime: `/health` 200, malformed and unapproved image URLs 400,
  QA CORS preflight 200. Browser Auth, Rules, risk-config, trades, Community,
  and unavailable-analysis paths reached real local services.

## Not yet accepted

This is not a 100% Web acceptance. Approved historical volume/news/broker
providers and licensed sandbox samples are still absent. Backtest playback,
paper trade/cutoff browser paths, referral code/ledger/withdrawal, quota,
Admin mutations, Radar worker, push, end-to-end EN/VI and staging proof have
not met the plan's acceptance criteria. The earlier VPS backend candidate
predates this local QA work. The Web plan and acceptance matrix remain open.

## Next local handoff

1. Finish W07 mutation validation/idempotency and adversarial API checks.
2. Restore Community's per-user liked state after tab recreation, then verify
   comment/share and ownership paths for W24.
3. Establish an approved historical-volume/news/broker sandbox and verify
   provider samples before closing W09/W11/W18/W20 or Backtest playback.
4. Repeat browser acceptance on one identified build and audit existing Admin
   claims/documents before any Rules deployment.

The local QA browser, FastAPI and Emulators were stopped after verification.
The working tree remains uncommitted; no GitHub or VPS deployment occurred.
