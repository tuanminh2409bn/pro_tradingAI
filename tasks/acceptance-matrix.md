# ProTrading AI VIP V2.1 - Acceptance Matrix

This matrix is the execution ledger. A row becomes `PASS` only when its automated and runtime evidence are linked to the same identified build. `IMPLEMENTED` without evidence is not `PASS`.

Status values: `NOT_STARTED`, `IN_PROGRESS`, `BLOCKED`, `PASS`, `FAIL`.

For a range row, the automated target, browser scenario, and current status
apply to every ID in that range separately. A range does not become `PASS`
until each ID has its own same-build evidence record. The consolidated
requirement-to-ledger coverage is checked by `test_v21_web_traceability.py`.

### Web-only scope for this execution plan

| IDs | Web evidence required | Mobile-only obligation excluded here |
|---|---|---|
| ARC-04, M-16 | Authorized Web broker relay and API boundary | Mobile credential-form absence and mobile build |
| ARC-09, M-03, F-05, R-24, R-27 | Browser mouse, touchpad, keyboard, responsive layout and navigation | Android/iOS touch and device acceptance |
| F-07 | Web permission, sound/flash, push and deep-link flow | Device vibration and native notification behavior |
| ROLE-01, ROLE-03 | Server-enforced Web quotas and role states | AdMob placement and IAP purchase/restore |
| ADM-03 | Web FCM sandbox delivery and navigation | Android/iOS delivery and navigation |

All other IDs retain their Web acceptance target below. This table changes
scope only; it does not mark a requirement complete.

## Contract and master checklist

| ID | Automated evidence | Runtime evidence | Current status |
|---|---|---|---|
| ARC-01..09 | Schema, auth, determinism, fallback, isolation suites | Architecture/security review and cross-platform smoke | IN_PROGRESS |
| M-01 | Symbol-bound P&L unit/integration tests | Two open symbols while switching chart | IN_PROGRESS |
| M-02 | Symbol-reset and metadata tests | Switch unlike symbols and inspect panel | IN_PROGRESS |
| M-03 | Gesture/controller tests | Web mouse/touchpad and mobile touch video | IN_PROGRESS |
| M-04 | Candle/color provenance tests | Chart sample traced to candle evidence | IN_PROGRESS |
| M-05 | Mode matrix tests | Web/mobile disabled-frame demonstration | IN_PROGRESS |
| M-06 | Soft/Hard/Veto gate tests | Soft has zones only; Hard transition video | IN_PROGRESS |
| M-07 | Three-call, vote, cache, Veto tests | Correlated agent/aggregator staging record | IN_PROGRESS |
| M-08 | Structural SL fixture tests | One SL traced to swing/trap | IN_PROGRESS |
| M-09 | Allocation and execution tests | TP allocation/dimming demonstration | IN_PROGRESS |
| M-10 | Bezier endpoint tests | SIG1/SIG2 render ending at TP3 | IN_PROGRESS |
| M-11 | Renderer/golden tests | Right-axis badge visual review | IN_PROGRESS |
| M-12 | HTF structure/navigation tests | Bearish HTF plus legend navigation | IN_PROGRESS |
| M-13 | Provider failure tests | Staging 402/429/timeout fallback | IN_PROGRESS |
| M-14 | Gate/widget/rules tests | Eligible first-run plus Journal lock | IN_PROGRESS |
| M-15 | Admin auth/cache/worker tests | Prompt/watchlist effective without rebuild | FAIL |
| M-16 | Verified Partner relay auth and Web navigation tests | Claim-bearing Web broker-link flow | IN_PROGRESS |

## Tab 1 render contract

| IDs | Automated evidence | Runtime evidence | Current status |
|---|---|---|---|
| R-01..04 Layer 1 | Schema plus painter golden tests | Structural chart video | IN_PROGRESS |
| R-05..08 Layer 2 | Volume/liquidity provenance plus golden tests | Marker-by-marker chart evidence | IN_PROGRESS |
| R-09..14 Layer 3 | Candle matrix plus provenance tests | Normal and evidence-overridden candles | IN_PROGRESS |
| R-15..22 Layer 4 | Gate/color/allocation/Bezier/momentum tests | Soft/Hard/Veto execution video | IN_PROGRESS |
| R-23..27 Layer 5 | HTF/news/time/interaction tests | Ghost, Red Zone, watermark, legend video | IN_PROGRESS |

## Tab 1 functions

| ID | Automated evidence | Runtime evidence | Current status |
|---|---|---|---|
| F-01 | Exact Verified Partner claim, UI gate, Rules and API bypass tests | Free versus Verified Partner accounts in the same Web build | IN_PROGRESS |
| F-02 | Popup persistence widget test | Eligible first-run demonstration | IN_PROGRESS |
| F-03 | Broker/account model parity tests | Live authorized source comparison | BLOCKED |
| F-04 | Risk-gate widget/BLoC tests | Fresh-user configuration saved through local Web/FastAPI/Firestore Emulator on 2026-09-25; cutoff/review browser flow remains | IN_PROGRESS |
| F-05 | Matrix unit/widget tests | Web/mobile timeframe interaction | IN_PROGRESS |
| F-06 | Soft-value absence/layout tests | Forecast below chart and empty Soft panel | IN_PROGRESS |
| F-07 | Alert state-machine tests | Recorded vibration/push/siren/flash | BLOCKED |
| F-08 | Sizing/cutoff/review/API tests | Floating-loss cutoff and unlock review | IN_PROGRESS |

## Tabs 2-7

| IDs | Automated evidence | Runtime evidence | Current status |
|---|---|---|---|
| J-01..03 Journal | Trade metric, heatmap, TTS lifecycle tests | Broker sample, heatmap, audio playback | IN_PROGRESS |
| N-01..03 News | Parser, sentiment, scenario, fake-clock tests | Local Web showed empty/unavailable state on 2026-09-25; provider sample and cross-tab Red Zone remain | IN_PROGRESS |
| B-01..03 Backtest | Pure replay, future-mutation isolation, BUY/SELL accounting, lock/review/ack, restore, and tamper-rejection tests | Local Web timed out to unavailable state without provider history; approved-history parity, durable state, and full simulation remain | IN_PROGRESS |
| C-01..03 Community | Privacy masking, verified-ranking fixtures, owner-only post Rules, token-bound idempotent like API and Web button tests | Local Auth/Firestore/FastAPI browser post and idempotent like reached count 1 on 2026-09-25; liked-state restoration, comment/share, existing-document audit and leaderboard remain | IN_PROGRESS |
| REF-01..03 Referral | Canonical link/QR payload and approved Marketing Kit personalization contracts; ledger/withdrawal pending | Local Web showed no referral code or reward data; QR decode, kit download and Admin approval remain | IN_PROGRESS |
| ROLE-01..05 | Exact claim allowlist, quota table, reset/timezone, fail-closed policy, atomic-boundary concurrency, Standard-only ad eligibility, Professional receipt lifecycle, exclusive Partner capability matrix, and Enterprise membership/aggregate-risk fixtures | Firebase/shared-store enforcement, AdMob/store sandbox integration, Rules/API bypass denial, durable Enterprise membership, and account-by-account entitlement matrix | IN_PROGRESS |

## Admin and operations

| ID | Automated evidence | Runtime evidence | Current status |
|---|---|---|---|
| ADM-01 | Verified-Admin boundary and exact five-minute authoritative prompt cache/invalidation tests | Local Auth/Firestore Emulator and Web role matrix passed on 2026-09-25; existing Admin claim audit and save propagation without rebuild remain | IN_PROGRESS |
| ADM-02 | 50/100-asset worker, volume/barrier filter, model call-count, provenance, structured target, and atomic idempotency-boundary tests | Approved provider/DeepSeek/Redis adapters, 50-100 asset staging SLA, FCM, and device deep link | IN_PROGRESS |
| ADM-03 | Server-side segment intersection, verified-Admin, opt-out, payload limits, provider reconciliation, opaque-token retirement, token-free audit, and structured deep-link tests | Firestore/FCM adapters, persistent audit, and Web/Android/iOS sandbox deliveries | IN_PROGRESS |
| ADM-04 | Closed output allowlist, sensitive/nested-field rejection, HMAC pseudonym/key rotation, consent/version/retention, and pseudonymous deletion tests | Approved consent policy, secret-managed key, real sink/log scan, and retained/deleted Data Lake sample | IN_PROGRESS |
| ADM-05 | Kill-switch contract and analysis/chat/new-execution wiring; 50-100 watchlist validation | Authenticated bypass, global-risk, watchlist worker, approval, and service-status demonstration | IN_PROGRESS |

## Release gates

| Gate | Required evidence | Status |
|---|---|---|
| A - Security/contract | Token identity, Rules Emulator isolation, schema fixtures | IN_PROGRESS — local G1 approved; Auth/Firestore Emulator role matrix and Standard/Admin/reserved browser checks pass on 2026-09-25. Existing-document/Admin-claim audit and staging remain |
| B - Market data | Session concurrency, volume parity, exact MTF bars, neutral cache | IN_PROGRESS |
| C - AI engine | Three agents, aggregator, confirmation, Veto, no fabrication | IN_PROGRESS |
| D - Tab 1 | 27/27 render and 8/8 functions | IN_PROGRESS |
| E - Tabs 2-3 | Journal/TTS and news/scenario/Red Zone | IN_PROGRESS |
| F - Tabs 4-6 | Backtest, Community, Referral | IN_PROGRESS — Community post/like passed on local Emulator; Backtest/Referral provider and money flows remain |
| G - Roles/Admin/Radar | Quotas, entitlements, controls, worker, push, masking | IN_PROGRESS — local role gate and Admin Rules matrix passed; backend controls, provider worker and push remain |
| H - Release | Local Python/Flutter regression and Web/Android/iOS release compilation are green; APK production signing, iOS signing, same-build device runtime, authenticated security/load, staging evidence, named owners, rollback drill, sign-off, and G6 remain | IN_PROGRESS |

Local Web QA checkpoint 2026-09-25: `checkpoint-2026-09-25-web-fullstack-qa.md`
records the build hash, browser paths, **216/216 Python** tests with Auth and
Firestore Emulators, **120/120 Flutter** tests, analyzer result, and exact
remaining gaps. These are partial row evidence, not `PASS` records.

## Evidence record template

For each PASS row, append a record with:

- Requirement ID:
- Commit/build:
- Environment:
- Automated command and result:
- Runtime scenario and result:
- Evidence path/link:
- Reviewer and date:
- Residual risk:
