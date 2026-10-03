# V2.1 Decision Register

Status values: `PENDING`, `APPROVED`, `REJECTED`, `SUPERSEDED`.

> Cập nhật Web 2026-10-03: G6 đã được chủ dự án duyệt cho push/deploy FE/BE và
> Rules/index, Web/BE đã triển khai ngày 25/09, backend TradingView triển khai
> ngày 03/10. G5 cho nguồn nến đã có chỉ đạo chọn TradingView tạm thời; tài khoản
> OANDA và quyền sử dụng dữ liệu thương mại vẫn chưa có bằng chứng. Live trading
> tiếp tục ngoài phạm vi. Các dòng LOCAL/PENDING bên dưới là quyết định gốc,
> không phải lý do xin lại quyền triển khai đã được duyệt. Xem
> `checkpoint-2026-10-03-web-production-readiness.md` cho điều kiện còn thiếu.

| Gate | Decision needed | Recommended safe default | Status | Owner |
|---|---|---|---|---|
| G1 | Firestore Rules, indexes, canonical paths, migrations/backfills | Local Rules/index patch approved 2026-09-24; deploy only after staging, existing-document audit, and separate G6 approval | APPROVED for local Rules/index only; migration and deployment pending | Project owner |
| G2 | New production Flutter/Python dependencies | Use existing packages and browser APIs on local; review a new dependency only if the selected flow cannot work with them | LOCAL DEFAULT SET; no new dependency selected | Project owner |
| G3 | Fifth account role omitted by the PDF | Keep `reserved_fifth` with zero capabilities; four named roles retain only existing rights. Do not provision the reserved claim | LOCAL DEFAULT SET; entitlement remains disabled | Product owner |
| G4 | Paper versus real MetaApi execution | Paper trading only; broker linking never authorizes a live order | APPROVED for local paper flow; live trading remains out of scope | Project owner + risk owner |
| G5 | External providers, licenses, credentials, and budgets | Select the provider targets below for adapters; disable each flow until its account, redistribution rights and budget are verified | LOCAL DESIGN SET; provider runtime not approved/configured | Product/procurement |
| G6 | Staging/production deploy, Rules deploy, migration, push, mobile release | Local build and tests now; later staging with immutable build ID and rollback plan | PENDING; no push or deploy requested yet | Release owner |
| G7 | Data Lake consent, retention, deletion, PII, country/device segments | Data export and sensitive push segments disabled until policy and deletion workflow exist | LOCAL DEFAULT SET; export disabled | Privacy/security owner |

## Local provider choices, chosen by project owner delegation on 2026-09-24

- Market history: OANDA v20 Practice is the target for supported forex/gold instruments. Its candle contract includes `complete`, granularities M5/M15/H1/H4/D and tick-count `volume`; label this **tick volume**, never exchange-traded volume. Keep analysis unavailable until a licensed account supplies enough closed bars for each timeframe and the symbol is actually supported. Existing TradingView stream may display prices but does not substitute for an independently verified MTF history.
- Economic calendar: Trading Economics Calendar API is the target because it exposes UTC event time, importance and source fields. High-impact events remain unavailable until API access and display/redistribution terms are verified.
- Social sentiment: official X API is the target. Without an approved account, API scope, retention terms and a tested parser, show unavailable; do not scrape posts or infer a live score from unrelated RSS.
- AI: retain the existing DeepSeek integration at `temperature=0.0`, bounded calls and deterministic labeled fallback. Live calls require an account, budget and failure test; no raw candle history or user data in prompts.
- TTS: use browser `speechSynthesis` for Web where available, without a new dependency or server audio billing. Show a disabled/unavailable state where the browser lacks voices or permission.
- Push: use existing Firebase Messaging only after Web VAPID configuration and explicit opt-in. No background send/segment claim based on a unit test alone.
- Broker: only Verified Partner may link a MetaApi account; the `/api/trade` contract stays paper. A sandbox account and verified claim are still required for runtime acceptance.
- QR: use a server-issued referral code and existing rendering capability; if no code or renderer is available, leave download unavailable. No UID-derived placeholder.
- Mobile IAP/AdMob, production Redis SLA and Data Lake sink are outside the local Web completion gate.

## Local product safety defaults

- Fifth role: `reserved_fifth` is a disabled placeholder with no quota, broker, Admin or trading capability. Do not silently map it to another paid tier.
- Referral: link/kit may be prepared, but no F1/F2 monetary accrual or withdrawal while percentages, currency, settlement and reversal terms are undefined. Display an explicit unavailable state rather than a zero balance that implies settlement.
- Daily-loss session: UTC calendar day, ending at 00:00 UTC. Once tripped, the server latch remains active through the session and does not clear merely because floating P&L recovers. Reopening in a later session requires a persisted review and user acknowledgement; no automatic unlock and no AI-dependent unlock. The local implementation and tests must enforce this before the flow is offered.
- Web push: opt-in only; no country/device targeting or retained segment history without G7 policy. Quiet hours default to no noncritical push until a user preference is defined.
- Browser support and accessibility are verified on the actual local build; no minimum-version promise without browser matrix evidence.

Provider contracts, account access, real licensed samples and staging credentials are still external prerequisites. These local selections authorize implementation and fail-closed states; they do not claim a service is connected.

## Official contract references

- OANDA candle fields and granularities: https://developer.oanda.com/rest-live-v20/instrument-df/
- Trading Economics Calendar fields: https://docs.tradingeconomics.com/economic_calendar/schema/
- X API search documentation: https://github.com/xdevplatform/docs/blob/main/x-api/posts/search/introduction.mdx
- Web Speech synthesis interface: https://developer.mozilla.org/en-US/docs/Web/API/Window/speechSynthesis
- Firebase Messaging Web VAPID: https://firebase.google.com/docs/cloud-messaging/flutter/get-started
