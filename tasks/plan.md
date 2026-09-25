# Implementation Plan: ProTrading AI VIP V2.1 Master

> **Execution split — 2026-09-18:** This document is the immutable Master
> requirements/dependency source. Active implementation is split into
> `tasks/web-completion-plan.md` and `tasks/mobile-completion-plan.md`; use
> `tasks/execution-plans.md` for the handoff order. Do not treat this Master as
> a third active execution plan.

## 1. Outcome

Deliver the full V2.1 Master scope on Web and Flutter mobile, with the Tab 1 correction document taking precedence where it explicitly resolves conflicts with V2.1. Completion means the behavior is implemented end to end, secured, tested, deployed to staging, and demonstrated against every contractual acceptance item. A visible widget or a Firestore field alone does not count as complete.

Primary source documents:

- `fix/BẢN_YÊU_CẦU_SỬA_ĐỔI_VÀ_NÂNG_CẤP_APP_PROTRADING_AI_VIP_CHO_DEV.pdf`
- `fix/YEU_CAU_DIEU_CHINH_TAB1_CHUAN_PHU_LUC_8.pdf`

## 2. Normative precedence

1. The Tab 1 correction document wins for direct conflicts, especially Layer 4 colors:
   - Entry `#0000FF`
   - SL `#FF0000`
   - TP1/TP2/TP3 `#00FF00`
2. V2.1 additions still apply when not contradicted: two-stage execution, partial TP, SIG1/SIG2 Bezier paths, Multi-Agent Consensus, HTF Veto, and two-level alerts.
3. Data-truth rule: if an item cannot be derived from real inputs, do not render or publish it.
4. Repository contracts remain binding unless the user explicitly approves a change. In particular, `/api/trade` remains paper trading until live MetaApi execution is separately authorized.

## 3. Current baseline

- Flutter/FastAPI/Firestore architecture exists and is usable as the implementation base.
- Symbol-bound P&L, timeframe matrix, basic Sync Gate, Redis/memory cache, deterministic fallback, and portions of the five-layer renderer already exist.
- The current signal schema differs from the mandatory Tab 1 schema.
- Volume and exact HTF datasets are absent from the analysis path.
- Multi-Agent Consensus, two-level alerts, real partial TP, reliable HTF Veto, and multiple Tab 2–7 features are absent or placeholders.
- Firestore/API authorization and Admin enforcement are not production-safe.
- Existing `docs/DOD_V21_CHECKLIST.md` is historical evidence only and must be regenerated from verified results.

## 4. Definition of 100% complete

The project is complete only when all of the following are true:

- All 16 V2.1 master checklist items pass on Web and the affected mobile targets.
- All 27 Tab 1 render components pass the corrected JSON contract, color, geometry, data-origin, and interaction requirements.
- All eight Tab 1 functional requirements pass end to end.
- Tabs 2–7 and all four Admin modules satisfy their stated behavior with no placeholder actions or fabricated product data.
- Firebase identity, role, quota, user isolation, Admin authorization, and server-side money/risk enforcement are tested.
- Redis/DeepSeek/provider outages produce deterministic, labeled fallbacks without raw errors or cross-user leakage.
- Web production and Android/iOS release candidates pass the acceptance matrix with recorded evidence.
- No critical/high security issue, analyzer error, failing test, fake production data, or unowned PII flow remains.

## 5. Approval gates

Planning does not grant authority for these changes. Implementation must stop at the relevant gate until explicitly approved:

| Gate | Required decision |
|---|---|
| G1 | Approve the mandatory Firestore Rules/index and persistent schema changes. |
| G2 | Approve new production Flutter/Python dependencies for audio, vibration, notifications, QR/media generation, validation, workers, testing, and provider SDKs. |
| G3 | Confirm the fifth account role: the PDF says five levels but enumerates only Standard, Verified Partner, Professional, and Enterprise. |
| G4 | Confirm whether V2.1 acceptance includes real live MetaApi order execution. This is high risk and currently prohibited by the repository contract without separate approval. |
| G5 | Provide/approve accounts, credentials, licensing, and budgets for ForexFactory-compatible data, Twitter/X, DeepSeek, MetaApi, TTS, IAP, AdMob, Firebase, Redis, and the Data Lake. |
| G6 | Approve production deployment, Firebase Rules deployment, database backfill/migration, App Store/TestFlight submission, and push notifications to real users. |
| G7 | Confirm legal/privacy retention, consent, deletion, country segmentation, and PII fields before Data Lake integration. |

## 6. Architecture decisions

- Preserve Flutter Repository → BLoC → Widget boundaries and FastAPI as the backend entry point.
- Make backend-generated, schema-validated JSON the sole source of all analytical labels, colors, coordinates, probabilities, setup state, and alerts.
- Keep `feature_engine.py` pure and deterministic. Network/provider access remains in `server.py` or narrowly scoped boundary modules.
- Treat Firebase ID tokens as identity; body/path `userId` is never authoritative.
- Store canonical private data under `users/{uid}/...`; use claims/roles for Admin and entitlements.
- Isolate market-data sessions by user/connection/symbol/timeframe. Never let global chart state determine another user's analysis or position mark.
- Fetch exact execution/HTF candle sets server-side. Client candles may be an optimization or consistency check, not the trusted source.
- Preserve the exact shared analysis cache key `analysis:{SYMBOL}:{timeframe}:{last_closed_candle_timestamp}` and exclude account-specific execution sizing from the shared cached artifact.
- Separate market analysis from user-specific risk sizing so shared cache entries cannot leak or reuse balance/risk context.
- Keep paper and live execution as explicit, separately authorized modes with server-side risk and idempotency controls.

## 7. Dependency graph

```text
Normative contract + acceptance matrix
        |
        +--> Identity / roles / Firestore / API security
        |
        +--> Market data: session isolation -> volume -> exact MTF history
        |                                      |
        |                                      +--> SMC/VSA/Wyckoff/Macro agents
        |                                                   |
        |                                                   +--> Consensus + Veto + 2-stage signal
        |                                                                  |
        |                                                                  +--> JSON contract
        |                                                                          |
        |                                                                          +--> Flutter models/renderers
        |                                                                                   |
        |                                                                                   +--> Tab 1 UX/alerts/risk
        |
        +--> Tabs 2-7 and Admin/Radar, using the secured contracts above
        |
        +--> Cross-platform hardening -> staging acceptance -> production rollout
```

## 8. Delivery phases

The detailed acceptance criteria, dependencies, verification commands, and likely files for every task are in `tasks/todo.md`.

### Phase 0 — Contract and baseline

- T01: Build the authoritative requirement-to-test matrix.
- T02: Restore and expand the local automated-test baseline.
- T03: Resolve external product/provider decisions and approval gates.

### Phase 1 — Identity, security, and contracts

- T04: Add Firebase ID-token authentication middleware.
- T05: Enforce private data isolation in Firestore Rules and indexes.
- T06: Harden API validation, CORS, proxying, logging, and idempotency.
- T07: Enforce Admin and role authorization at all three layers.
- T08: Define and validate the mandatory analysis JSON contracts.

### Phase 2 — Trusted market-data foundation

- T09: Isolate WebSocket market state per connection and symbol.
- T10: Carry real volume end to end.
- T11: Fetch and validate exact 120/120/150 MTF candle sets.
- T12: Separate shared analysis caching from user-specific risk output.

### Phase 3 — Deterministic analysis and Multi-Agent Consensus

- T13: Correct SMC structure, OB/FVG, trend, and structural SL logic.
- T14: Implement real VSA and Wyckoff features from volume.
- T15: Implement Macro News and Risk Guard inputs.
- T16: Implement three independent specialist-agent calls.
- T17: Implement the Consensus Aggregator and confirmation rules.
- T18: Make HTF Veto deterministic and auditable.
- T19: Replace fabricated fallback layers with truthful signal construction.

### Phase 4 — Tab 1 contract, renderer, and execution UX

- T20: Parse the new signal schema safely in Dart.
- T21–T25: Complete Layers 1–5.
- T26: Complete chart X/Y gestures, HTF navigation, and forecast placement.
- T27: Enforce symbol reset, hard-setup execution gating, and real broker fields.
- T28: Implement two-level alerts on Web and mobile.
- T29: Enforce daily-loss cutoff and generate the session-review report.
- T30: Run full Tab 1 contract and runtime acceptance.

### Phase 5 — Tabs 2 and 3

- T31: Journal broker metrics and canonical trade schema.
- T32: Journal behavioral insight, heatmap, and real TTS.
- T33: ForexFactory/Twitter-X ingestion and normalized sentiment.
- T34: What-If scenario workflow.
- T35: Scheduled cross-tab Red Zone and alert propagation.

### Phase 6 — Tabs 4, 5, and 6

- T36: Historical Backtest replay engine.
- T37: No-Repaint simulation, trades, cutoff, and manual unlock.
- T38: Authenticated community posts, comments, reactions, and sharing.
- T39: Privacy-safe trade cards and verified leaderboard.
- T40: Referral links, QR, and personalized Marketing Kit.
- T41: F1/F2 accounting and Admin-reviewed withdrawal flow.

### Phase 7 — Tab 7, Admin, and Radar

- T42: Role/entitlement and server-enforced quota system.
- T43: Standard ads and Professional purchase entitlements.
- T44: Verified Partner and Enterprise master/sub-account controls.
- T45: Secure dynamic Admin prompt, risk, kill switch, and watchlist.
- T46: Redis-backed 50–100 asset two-stage Radar worker.
- T47: Manual segmented push with deep links and delivery audit.
- T48: PII DataMasker and consent-aware Data Lake boundary.

### Phase 8 — Hardening and release

- T49: Error recovery, observability, accessibility, localization, and performance hardening.
- T50: Staging acceptance, production rollout, mobile release candidates, evidence, and rollback.

## 9. Checkpoints

| Checkpoint | Exit criteria |
|---|---|
| A — Contract/Security | Identity comes from verified tokens; Rules emulator proves isolation; schema fixtures validate; no Admin route is user-accessible. |
| B — Market Data | Per-session streams are isolated; volume matches source; exact aligned MTF bars are available; cache is user-neutral. |
| C — AI Engine | Three agent outputs and votes are persisted; consensus/confirmation/Veto are deterministic; no fabricated layer survives. |
| D — Tab 1 | 27/27 render items and 8/8 functions pass; Soft/Veto cannot execute; colors and geometry match the correction PDF. |
| E — Tabs 2–3 | Broker metrics/TTS and news/sentiment/What-If/Red Zone work with provider-failure fallbacks. |
| F — Tabs 4–6 | Backtest No-Repaint, community privacy, QR/Marketing Kit, and withdrawal workflows pass end to end. |
| G — Roles/Admin/Radar | Quotas and roles are enforced server-side; Admin controls have effect; Radar covers 50–100 configured assets; DataMasker tests pass. |
| H — Release | Full automated suite, security tests, load tests, Web/mobile builds, staging video evidence, rollback drill, and stakeholder sign-off pass. |

## 10. Parallel work lanes

Parallel work starts only after T08 defines stable contracts.

- Lane A: Market data and AI engine — T09–T19.
- Lane B: Flutter renderer — T20–T26, using schema fixtures before the live backend is ready.
- Lane C: Security/roles/Admin — T04–T07, then T42–T48.
- Lane D: Independent feature tabs — T31–T41 after shared identity and trade contracts stabilize.
- Integration owner: resolves schema changes, maintains fixtures, and runs each checkpoint. No lane may independently change the shared schema.

## 11. Estimated effort

These are engineering-day estimates, not contractual promises. External-provider approval or App Store review is excluded.

| Phase | Estimated engineering days |
|---|---:|
| Contract, baseline, approvals | 4–6 |
| Security and shared contracts | 8–12 |
| Market data foundation | 8–12 |
| AI engine and consensus | 14–20 |
| Tab 1 Flutter/runtime | 15–22 |
| Tabs 2–3 | 8–12 |
| Tabs 4–6 | 15–22 |
| Tab 7, Admin, Radar, DataMasker | 16–24 |
| Hardening and release | 10–15 |
| **Total** | **98–145 engineering days** |

Expected calendar duration:

- One full-stack engineer: roughly 5–7 months.
- A coordinated team of four engineers plus QA: roughly 10–14 weeks.
- The seven-day delivery stated in the PDF is not credible for the current gap unless scope, evidence, security, mobile releases, and external integrations are materially reduced.

## 12. Risks and mitigations

| Risk | Impact | Mitigation |
|---|---|---|
| Live trading sends an unintended order | Critical | Separate paper/live modes, explicit G4 approval, broker sandbox, idempotency key, server risk checks, audit log, global kill switch. |
| Cross-user market or account state | Critical | Per-connection sessions, token-derived UID, concurrency tests, no global mutable account context. |
| Fabricated analysis reaches users | Critical | Data-origin fields, schema validation, deterministic fixtures, omit unsupported components, no fallback labels without evidence. |
| Provider data is unavailable or unlicensed | High | Resolve G5 early, provider adapters, timeouts, circuit breakers, labeled degraded state. |
| Firestore rule changes lock out valid flows or expose data | Critical | Rules emulator tests for every collection and negative access case before deployment. |
| Shared cache contains account-specific values | High | Cache only user-neutral market analysis; apply risk sizing after cache retrieval. |
| Mobile notification/audio behavior differs by platform | High | Platform-specific integration tests, permissions, foreground/background/deep-link matrix. |
| PDF ambiguity produces rework | High | T01 traceability matrix and stakeholder sign-off before code changes. |
| Large `server.py` changes become unreviewable | Medium | Thin vertical slices, pure helpers, focused tests, checkpoint merges; no framework rewrite. |
| Historical PASS documentation masks regressions | High | Generate DoD from current test evidence and store date/environment/build identifiers. |

## 13. Open questions requiring stakeholder answers

1. What is the fifth role referenced by “five account levels” in the PDF?
2. Does 100% acceptance require live MetaApi execution, or is verified paper execution acceptable for this release?
3. Which licensed APIs are approved for ForexFactory-equivalent events and Twitter/X sentiment?
4. Which TTS provider, supported languages/voices, and monthly budget should be used?
5. What are the exact country/device segments and consent policy for manual push and Data Lake export?
6. What is the source of truth for commission-tree rates, reward currency, minimum withdrawal, and approval SLA?
7. Which historical market-data provider and symbol mappings are authorized for No-Repaint backtests?
8. Which assets make up the required 50–100 Radar watchlist, and what is the acceptable scan latency/cost?
9. Which mobile targets are contractual for acceptance: Android APK only, Android+iOS TestFlight, or all Flutter desktop targets too?

## 14. Change-control rule

Any change to the analysis schema, role model, quota semantics, Firestore paths, execution mode, or external provider must update:

1. The requirement-to-test matrix.
2. Backend validation and fixtures.
3. Dart parsing/compatibility tests.
4. Firestore/API authorization tests when applicable.
5. The production acceptance script and evidence checklist.
