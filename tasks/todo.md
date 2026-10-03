# ProTrading AI VIP V2.1 Master — Executable Task List

> **Execution split — 2026-09-18:** This file remains the Master traceability
> ledger. Execute Web work from `tasks/web-completion-plan.md` and Mobile work
> from `tasks/mobile-completion-plan.md`; do not count this ledger as another
> active plan.

Status convention: `[ ]` not started, `[~]` in progress, `[x]` verified complete, `[!]` blocked. A task is complete only after every acceptance and verification item passes.

## Phase 0 — Contract and baseline

### T01 — Authoritative requirement-to-test matrix [~]

**Description:** Convert both PDFs into one traceability matrix. Resolve direct conflicts using the Tab 1 correction and assign a stable ID to all 16 master checklist items, 27 render components, eight Tab 1 functions, Tabs 2–7, and four Admin modules.

**Acceptance criteria:** [ ] Every PDF requirement has one ID and source reference. [ ] Conflicts and ambiguities are explicit. [ ] Every ID maps to an automated or manual acceptance test.

**Verification:** [ ] Independent review finds no unmapped requirement. [ ] Stakeholder signs off the precedence and acceptance matrix.

**Dependencies:** None. **Likely files:** `tasks/requirements-v2.1.md`, `tasks/acceptance-matrix.md`, `tasks/plan.md`. **Scope:** M.

### T02 — Restore and expand the test baseline [~]

**Description:** Recreate the deleted Python regression coverage and define deterministic test fixtures for cache, MTF, fallback, parity, hardening, and the existing Dart behaviors.

**Acceptance criteria:** [ ] Day 3–7 regression intents are covered without network. [ ] Tests distinguish current failures from intended V2.1 behavior. [ ] No test embeds credentials or production data.

**Verification:** [ ] `python3 -m unittest discover -p 'test_*.py'`. [ ] `flutter test`. [ ] `flutter analyze` has no errors.

**Dependencies:** T01. **Likely files:** `test_day3_analysis.py`, `test_day4_mtf.py`, `test_day5_fallback.py`, `test_day6_parity.py`, `test_day7_harden.py`. **Scope:** M.

### T03 — Resolve provider and product gates

**Description:** Record decisions for live versus paper trading, the fifth role, provider licensing, TTS, IAP/AdMob, historical data, Radar assets, mobile targets, and Data Lake privacy.

**Acceptance criteria:** [ ] G1–G7 each have an owner and written decision. [ ] Required sandbox/provider accounts exist. [ ] No implementation assumes an unapproved paid service or live-trading authority.

**Verification:** [ ] Architecture/decision record approved by product, security, and project owner.

**Dependencies:** T01. **Likely files:** `tasks/decisions-v2.1.md`, `tasks/provider-matrix.md`. **Scope:** S.

## Checkpoint A0 — Planning contract

- [ ] T01–T03 accepted by the stakeholder.
- [ ] Scope, role count, execution mode, providers, targets, and budgets are no longer ambiguous.

## Phase 1 — Identity, security, and shared contracts

### T04 — Firebase ID-token authentication middleware [~]

**Description:** Verify Firebase ID tokens at the FastAPI boundary and derive UID/claims server-side for every private, broker, trade, risk, chat, quota, and Admin operation.

**Acceptance criteria:** [~] Trade/close/list/risk endpoints reject missing/invalid/expired tokens with 401; remaining private endpoints are not covered. [~] These endpoints reject cross-UID body/path claims; broker/chat/quota/Admin audit remains. [ ] Role claims are available to authorized handlers.

**Verification:** [ ] Focused API tests for valid, invalid, expired, and cross-UID tokens. [ ] `python3 -m py_compile server.py`.

**Dependencies:** T03/G1. **Likely files:** `server.py`, `test_day7_harden.py`, `lib/data/repositories/trading_repository.dart`, `lib/data/repositories/profile_repository.dart`. **Scope:** M.

### T05 — Firestore Rules and index isolation [~]

**Description:** Lock private signals, analysis requests, chat history, backtests, Admin data, FCM tokens, community ownership, and withdrawals to the correct identities and roles.

**Acceptance criteria:** [~] Signals and analysis requests are owner-readable, and direct client trade writes are denied; other private collections remain unaudited. [ ] Admin writes require an Admin claim. [~] Three owner/cross-user Emulator cases pass; remaining query and collection paths need coverage.

**Verification:** [ ] Firebase Emulator positive and negative rules tests. [ ] Index definitions match all changed queries. [ ] No blanket public/write rule remains for private data.

**Dependencies:** T04, G1. **Likely files:** `firestore.rules`, `firestore.indexes.json`, `test/firestore_rules_test.*`. **Scope:** M.

### T06 — API boundary hardening [~]

**Description:** Add strict validation, request limits, idempotency for trade/link/withdrawal actions, safe error responses, CORS allowlists, and SSRF protection for image proxying.

**Acceptance criteria:** [~] Paper-trade symbol, chart, price, lot, and target intent are checked against the current signal; other input/URL/size boundaries remain. [~] Paper-trade creation is idempotent for the same key, but cross-refresh client retry and other mutations remain. [x] Logs and responses contain no secrets or sensitive exception strings.

**Verification:** [ ] API adversarial tests pass. [ ] CORS and proxy allowlist tests pass. [x] Secret/error-pattern regression scan passes.

**Dependencies:** T04. **Likely files:** `server.py`, `test_day7_harden.py`, `analysis_cache.py`, `Dockerfile`. **Scope:** M.

### T07 — Three-layer Admin/role authorization

**Description:** Hide unauthorized UI, deny unauthorized Firestore access, and reject unauthorized backend mutations for Admin, Verified Partner, Professional, and Enterprise capabilities.

**Acceptance criteria:** [ ] Free users cannot see or call Admin/link-only actions. [ ] Direct API/Firestore bypass attempts fail. [ ] Admin and intended partner roles retain access.

**Verification:** [ ] Widget tests by role. [ ] Firestore Emulator tests. [ ] Backend claim tests.

**Dependencies:** T04, T05, T03/G3. **Likely files:** `lib/core/widgets/web_sidebar.dart`, `lib/features/dashboard/web/web_dashboard_shell.dart`, `lib/features/trading_room/web/trading_room_web_page.dart`, `firestore.rules`, `server.py`. **Scope:** M.

### T08 — Mandatory analysis JSON contracts [~]

**Description:** Define request/response JSON Schema and backend validation for `chart_id`, stage/veto fields, exact five-layer object keys, Hex colors, coordinates, limits, and MTF candles with volume.

**Acceptance criteria:** [ ] Invalid payloads never reach Firestore or Flutter. [x] Soft/Veto responses cannot contain active Layer 4 or executable prices. [~] Golden valid/invalid fixtures cover the five-layer contract shapes; painter/runtime coverage for all 27 components remains.

**Verification:** [x] JSON Schema artifact/contract tests pass. [x] Python serializer and Dart fixture parity tests pass. [x] Schema drift test fails on renamed/missing fields.

**Dependencies:** T01. **Likely files:** `schemas/analysis-request-v2.1.json`, `schemas/analysis-response-v2.1.json`, `test_day6_parity.py`, `test/analysis_contract_test.dart`. **Scope:** M.

## Checkpoint A — Security and contract

- [ ] T04–T08 pass locally and in emulators.
- [ ] No private collection or mutation trusts client identity.
- [ ] Shared analysis fixtures are frozen for downstream work.

## Phase 2 — Trusted market data

### T09 — Per-connection market-data sessions [x]

**Description:** Replace global mutable chart/account selection with connection-scoped symbol/timeframe state while retaining an independent shared mark-price book per symbol.

**Acceptance criteria:** [x] Two simultaneous users can stream different symbols/timeframes without interference. [x] Position P&L always uses its symbol. [x] Disconnects release session resources.

**Verification:** [x] Async two-client WebSocket test. [x] Symbol-flip P&L regression. [x] Connection lifecycle leak test.

**Dependencies:** T02, T04. **Likely files:** `server.py`, `scripts/tradingview_probe.py`, `test_day7_harden.py`. **Scope:** M.

### T10 — Volume end to end [~]

**Description:** Preserve TradingView/provider volume through backend extraction, WebSocket full/delta messages, aggregation, Dart Candle, analysis payloads, and fixtures.

**Acceptance criteria:** [ ] Every candle schema has `v`. [ ] Resampled volume is summed. [ ] A sampled candle matches the approved source.

**Verification:** [ ] Python extraction/aggregation tests. [ ] Dart WebSocket/model tests. [ ] Manual source comparison evidence.

**Dependencies:** T08, T09. **Likely files:** `server.py`, `feature_engine.py`, `lib/data/models/trading_models.dart`, `lib/data/repositories/trading_repository.dart`, `test_day4_mtf.py`. **Scope:** M.

### T11 — Exact MTF historical datasets

**Description:** Fetch trusted server-side execution/HTF1/HTF2 histories with exact 120/120/150 closed candles, timestamp alignment, gap validation, symbol normalization, and provider timeouts.

**Acceptance criteria:** [ ] Matrix counts are exact for all three modes. [ ] H1/H4/D1 bars align to interval boundaries. [ ] Missing/gapped data yields a labeled unavailable state, never silent analysis.

**Verification:** [ ] Fixture tests for all nine mode/timeframe combinations. [ ] Gap/weekend/DST tests. [ ] Provider sandbox smoke test.

**Dependencies:** T09, T10, G5. **Likely files:** `server.py`, `feature_engine.py`, `test_day4_mtf.py`, `deploy/REDIS.md`. **Scope:** M.

### T12 — User-neutral analysis cache [~]

**Description:** Cache only market-analysis artifacts under the mandated key and compute balance/risk/lot values after retrieval; preserve Redis single-flight and memory fallback.

**Acceptance criteria:** [x] Cache hit never calls LLM. [ ] Different users receive their own risk sizing while sharing the same market analysis. [x] Redis failure uses deterministic memory fallback without exposing connection details.

**Verification:** [x] Cache hit/miss/stampede tests. [x] Cross-user market-artifact neutrality test. [x] TTL tests for required timeframes.

**Dependencies:** T08, T11. **Likely files:** `analysis_cache.py`, `server.py`, `test_day3_analysis.py`, `test_day5_fallback.py`. **Scope:** M.

## Checkpoint B — Market data

- [ ] T09–T12 pass concurrency and source-parity tests.
- [ ] No analysis runs with missing volume, insufficient HTF bars, or foreign session state.

## Phase 3 — Analysis engine and consensus

### T13 — Correct SMC structure and structural risk levels [x]

**Description:** Make HH/HL and LH/LL trend rules symmetric, derive BOS/MSS/CHoCH/OB/FVG from evidence, and calculate one SL beyond the relevant trap/swing structure.

**Acceptance criteria:** [x] Neutral never defaults to BUY. [x] Bullish/Bearish fixtures are symmetric. [x] No synthetic OB/BOS/SL is emitted when evidence is absent.

**Verification:** [x] Deterministic SMC fixture suite. [x] Structural SL invariant tests. [x] `python3 -m py_compile feature_engine.py`.

**Dependencies:** T10, T11. **Likely files:** `feature_engine.py`, `test_day3_analysis.py`, `test_day4_mtf.py`. **Scope:** M.

### T14 — VSA and Wyckoff engine [x]

**Description:** Derive rolling volume baselines, ≥3x spikes, climax, no-demand/no-supply, spread alerts, divergence, and evidence-backed Wyckoff phase.

**Acceptance criteria:** [x] Every Layer 2/3/5 VSA label references measured candle evidence. [x] Unsupported/ambiguous phase is omitted. [x] No fixed-index candle overrides remain.

**Verification:** [x] Hand-calculated volume fixtures. [x] Boundary tests around 3x threshold. [x] No-fabrication assertions.

**Dependencies:** T10, T13. **Likely files:** `feature_engine.py`, `test_day3_analysis.py`, `test_day6_parity.py`. **Scope:** M.

### T15 — Macro News and Risk Guard inputs [~]

**Description:** Normalize approved high-impact events and sentiment into time-aware, symbol/currency-aware risk input; calculate minimum 1:2 R:R and user-neutral risk constraints.

**Acceptance criteria:** [x] Events have source, time, impact, currencies, freshness, and provenance. [x] R:R below 1:2 prevents execution in Python and Dart. [x] Stale/unavailable news is labeled.

**Verification:** [~] Event mapping/time fixtures pass; timezone/provider integration remains. [x] R:R veto fixtures. [ ] Provider-failure fallback tests.

**Dependencies:** T03/G5, T11. **Likely files:** `server.py`, `feature_engine.py`, `test_day5_fallback.py`, `test_day6_parity.py`. **Scope:** M.

### T16 — Three specialist agents [~]

**Description:** Run separate SMC/ICT, VSA/Wyckoff, and Macro/Risk agent calls with bounded prompts built only from compact feature summaries.

**Acceptance criteria:** [~] The provider-neutral orchestrator produces exactly three independently audited outputs, but cache-miss/backend persistence wiring awaits the approved provider. [x] Every provider call uses `temperature=0.0` and a bounded allowlist-only feature prompt with no raw candle array or PII. [x] Each output validates against a closed specialist schema and invalid output fails closed to `WAIT`.

**Verification:** [x] Injected-provider call-count, prompt-content, response-schema, and cross-agent tests pass. [x] Timeout/402/429-equivalent provider classifications fail closed without exception detail. [x] Audit records contain only opaque correlation ID, agent, and allowlisted outcome. [ ] Approved DeepSeek sandbox, cache-miss integration, and durable specialist/aggregator records remain under G5.

**Dependencies:** T12–T15, G5. **Likely files:** `server.py`, `test_day5_fallback.py`, `test_day6_parity.py`. **Scope:** M.

### T17 — Consensus Aggregator and candle confirmation [~]

**Description:** Aggregate specialist votes, calculate auditable consensus, and require ≥75% agreement plus an approved confirmation candle before `setup_ready=true`.

**Acceptance criteria:** [~] Votes retain bounded evidence references, reason, confidence, agreement, and final deterministic decision in the gate result; durable persistence awaits the approved authenticated storage path. [x] Missing, directionally invalid, or timestamp-free confirmation always yields Soft Alert. [x] LLM votes cannot override zone-touch, confirmation, MTF, macro, or HTF Veto gates.

**Verification:** [x] Consensus table tests cover unanimous, 2/3, malformed, cross-direction, and evidence filtering. [x] Pinbar/Engulfing/Climax fixtures pass and confirmation now requires a measured candle timestamp. [x] Repeated inputs produce identical gate/audit results. [ ] Same-build provider and persistence evidence remains under G1/G5.

**Dependencies:** T16. **Likely files:** `server.py`, `feature_engine.py`, `test_day4_mtf.py`, `test_day6_parity.py`. **Scope:** M.

### T18 — Reliable HTF Veto [x]

**Description:** Apply opposing HTF supply/demand veto only to validated HTF histories and return complete `veto_data` with conflict timeframe and danger zone.

**Acceptance criteria:** [x] Veto always forces Soft/Frozen state and removes Layer 4. [x] Same-direction/remote zones do not veto. [x] The decision is reproducible and auditable.

**Verification:** [x] BUY/SELL HTF conflict matrix tests. [x] Insufficient-HTF test. [x] One shared JSON fixture validates in Python and parses fail-closed in Dart with identical `veto_reason`, `conflict_htf`, danger zone, and absent Layer 4.

**Dependencies:** T11, T13, T17. **Likely files:** `feature_engine.py`, `server.py`, `test_day4_mtf.py`, `test_day6_parity.py`. **Scope:** M.

### T19 — Truthful signal and layer builder [~]

**Description:** Emit the mandatory object-shaped layers, Hex colors, coordinates, chart ID, provenance, and forecast without fabricated structures, labels, probability, or Wyckoff phases.

**Acceptance criteria:** [~] The pure legacy-to-V2.1 emitter validates against the T08 contract for Soft, Hard BUY/SELL, Veto, and unavailable fallback; replacing the deployed legacy persistence/API envelope still requires the public-contract approval gate. [x] Missing evidence omits the component. [x] Soft/Veto output contains no executable Layer 4 values.

**Verification:** [x] Canonical SHA-256 goldens cover Soft bullish, Hard bullish, Hard bearish, unavailable fallback, and the shared Veto fixture. [x] Every emitted analytical color is checked as `#RRGGBB`; client named-color/icon lookup tables remain absent. [x] Repeated inputs produce byte-equivalent canonical output and stable golden digests.

**Dependencies:** T13–T18. **Likely files:** `feature_engine.py`, `server.py`, `test_day6_parity.py`, `schemas/analysis-response-v2.1.json`. **Scope:** M.

## Checkpoint C — AI engine

- [ ] T13–T19 pass deterministic, provenance, consensus, confirmation, and Veto tests.
- [ ] One analysis produces three specialist records plus one aggregator record.
- [~] Local builders/adapters omit unsupported visual components; same-build provider and persistence evidence remains.

## Phase 4 — Tab 1 Flutter and execution behavior

### T20 — Safe Dart signal contract [x]

**Description:** Parse the object-shaped five-layer contract, chart ID, stage/veto/fallback/provenance fields, optional executable values, and compatibility aliases without unsafe defaults.

**Acceptance criteria:** [x] Missing `setup_ready` defaults to false. [x] Soft/Veto signals cannot expose Entry/SL/TP/lot/Layer 4 as valid values. [x] Malformed layers become a labeled error, not a crash.

**Verification:** [x] Dart parses the shared Python-generated Soft bullish, Hard bullish, Hard bearish, unavailable fallback, and Veto golden fixtures with matching stage/execution behavior. [x] Negative parsing tests. [x] Focused `flutter analyze` passes with no issues.

**Dependencies:** T08, T19. **Likely files:** `lib/data/models/trading_models.dart`, `lib/data/repositories/trading_repository.dart`, `test/analysis_contract_test.dart`. **Scope:** M.

### T21 — Layer 1 renderer [~]

**Description:** Render arbitrary two-point dashed lines, solid boxes, bordered boxes, and dynamic labels with exact Hex colors and length limits.

**Acceptance criteria:** [x] Diagonal BOS/MSS/CHoCH works. [x] Solid and bordered boxes are distinct. [x] Labels are positioned and constrained without covering candles.

**Verification:** [~] Combined exact-contract painter fixture covers all four components; dedicated pixel goldens remain. [x] The painter and deterministic test share one time/price projection, proving pan offset plus X/Y zoom remap for Layer 1 geometry.

**Dependencies:** T20. **Likely files:** `lib/features/trading_room/web/widgets/kinetic_chart.dart`, `test/kinetic_chart_layer1_test.dart`. **Scope:** S.

### T22 — Layer 2 renderer [~]

**Description:** Render backend-supplied `$$$`, `LIQ`, directional arrows, short labels, and STOP volume tags without client icon inference.

**Acceptance criteria:** [x] Text and direction come directly from JSON. [x] Character limits and colors match the correction PDF. [x] Removing a backend item removes it from the chart.

**Verification:** [~] Combined five-layer painter fixture covers every Layer 2 marker; dedicated pixel goldens remain. [x] Search confirms `_getIconString` and named-color `_parseColor` are removed.

**Dependencies:** T20. **Likely files:** `lib/features/trading_room/web/widgets/kinetic_chart.dart`, `test/kinetic_chart_layer2_test.dart`. **Scope:** S.

### T23 — Layer 3 renderer [~]

**Description:** Render default green/red candles plus backend-authorized purple/white/gray fill, two-character text above the candle, gold spread border, and divergence arrows.

**Acceptance criteria:** [x] Normal candles never change color. [x] Fill/border/text/divergence can coexist. [x] Unknown or unsupported overrides fail safely.

**Verification:** [~] Combined exact-contract painter fixture covers the candle override matrix; dedicated pixel goldens remain. [x] Backend provenance fixtures cover measured overrides. [x] Search finds no named-color client analytical lookup.

**Dependencies:** T14, T20. **Likely files:** `lib/features/trading_room/web/widgets/kinetic_chart.dart`, `test/kinetic_chart_layer3_test.dart`. **Scope:** S.

### T24 — Layer 4 execution renderer and partial TP [~]

**Description:** Render exact Entry/SL/TP colors, one structural SL, TP opacity selection, probability, momentum signs, and SIG1/SIG2 ending at TP3; connect TP allocation percentages to the order contract.

**Acceptance criteria:** [x] Layer appears only for Hard Setup. [x] Allocation totals 100% and selected TP behavior matches V2.1. [x] Both Bezier paths end exactly at TP3.

**Verification:** [~] Combined exact-contract painter fixture passes; dedicated Layer 4 pixel goldens remain. [x] Allocation validation and lot-step tests. [x] Soft/Veto absence tests. [x] Split execution payload test against the existing `/api/trade` contract.

**Dependencies:** T17–T20. **Likely files:** `lib/features/trading_room/web/widgets/kinetic_chart.dart`, `lib/features/trading_room/web/widgets/execution_panel.dart`, `lib/data/models/trading_models.dart`, `test/kinetic_chart_layer4_test.dart`. **Scope:** M.

### T25 — Layer 5 environment renderer [~]

**Description:** Render backend-colored Ghost Box with 15% opacity and hit testing, real scheduled Red Zone/countdown, evidence-backed Wyckoff watermark, and clickable HTF trend legend.

**Acceptance criteria:** [x] Ghost click reveals bounded tooltip/zoom behavior. [x] Red Zone uses actual start/duration and a live repainting countdown. [x] Legend opens the specified HTF.

**Verification:** [~] Combined exact-contract painter and Ghost/HTF interaction tests pass; dedicated pixel goldens remain. [x] Injected-clock countdown and repaint-timer tests. [~] HTF and strict scheduled-event fixtures pass; parity against an approved live calendar provider remains.

**Dependencies:** T15, T18–T20. **Likely files:** `lib/features/trading_room/web/widgets/kinetic_chart.dart`, `lib/features/trading_room/web/widgets/news_red_zone_binder.dart`, `test/kinetic_chart_layer5_test.dart`. **Scope:** M.

### T26 — Chart gestures, navigation, and forecast layout [~]

**Description:** Add explicit X-axis time scaling, preserve Y-axis scaling/wheel/pinch/center pan, remap all layers, and move forecast text below the chart responsively.

**Acceptance criteria:** [x] Price axis, time axis, wheel, pinch, and chart-center gestures are independently usable. [x] All layer coordinates use the shared candle/time/price viewport and survive gesture remapping. [x] Forecast is below chart on desktop and mobile layouts.

**Verification:** [x] Gesture/controller tests plus five-layer remap smoke. [ ] Browser mouse/touchpad smoke video. [ ] Mobile touch smoke video.

**Dependencies:** T21–T25. **Likely files:** `lib/features/trading_room/web/widgets/kinetic_chart.dart`, `lib/features/trading_room/web/trading_room_web_page.dart`, `lib/features/trading_room/mobile/trading_room_mobile_page.dart`, `test/trading_mode_and_price_window_test.dart`. **Scope:** M.

### T27 — Execution state, symbol reset, and Hard-Setup gate [~]

**Description:** Reset symbol-specific panel state, use correct tick/pip/lot/spread/swap metadata, remove generated Soft values, and block UI/backend execution unless the current signal is Hard and not vetoed.

**Acceptance criteria:** [x] Symbol change clears stale levels and preserves other-symbol positions. [x] Soft/Veto has no executable controls. [x] Client BLoC rejects Soft/Veto, cutoff, mismatched symbol/timeframe/chart ID, and altered execution values; changing timeframe clears the old signal. [x] The Web panel hides order controls for stale-timeframe and contract-invalid signals, keeps non-executable legacy Soft visible, and never claims execution success before the backend responds. [~] Authenticated backend checks signal document ID, chart ID, ownership, Hard/Veto, Layer 4, freshness, and order values; trusted market-data provenance and server-side daily cutoff are still missing.

**Verification:** [x] Pure BLoC transition and execution-safety model tests and dedicated panel widget tests pass. [x] Cross-symbol P&L/state test. [x] Client execution-gate tests cover Hard/Soft/Veto/cutoff, chart identity, symbol, timeframe aliases/transitions, altered order values, and absent premature success messaging. [~] Isolated API-handler bypass/retry tests and three Firestore Emulator owner/cross-user tests pass; real FastAPI/Firebase Admin runtime integration remains.

**Dependencies:** T04, T09, T17, T20. **Likely files:** `lib/features/trading_room/bloc/trading_room_bloc.dart`, `lib/features/trading_room/web/widgets/execution_panel.dart`, `lib/data/repositories/trading_repository.dart`, `server.py`, `test/trading_execution_gate_test.dart`. **Scope:** M.

### T28 — Two-level alerts [~]

**Description:** Monitor real-time price against waiting zones for level-one vibration/push, and trigger level-two siren/flashing popup/deep link when a Hard Setup is published.

**Acceptance criteria:** [x] The deterministic detector emits each stage once per chart/signal transition. [~] The state machine honors opt-out; platform permission adapters remain. [ ] Foreground/background Web, Android, and iOS behavior is documented and tested.

**Verification:** [x] Fake-price state-machine tests cover waiting-zone touch, Hard transition, duplicate suppression, Veto, and opt-out. [ ] FCM sandbox delivery test. [ ] Recorded device/browser evidence with sound for level two.

**Dependencies:** T05, T17, T25, G2, G5. **Likely files:** `lib/core/services/fcm_service.dart`, `lib/features/trading_room/bloc/trading_room_bloc.dart`, `server.py`, `pubspec.yaml`, `test/trading_alerts_test.dart`. **Scope:** M.

### T29 — Daily-loss cutoff and session review [~]

**Description:** Persist realized plus floating daily P&L, enforce cutoff in UI and backend for analysis and execution, and request a friendly LLM/rule-based session-review report before manual unlock.

**Acceptance criteria:** [~] Client cutoff is latched but persistence across refresh/device needs G1 and a session-boundary decision. [~] Client blocks both Analyze and Trade; backend rejection remains. [ ] Review and explicit acknowledgement are recorded before unlock.

**Verification:** [~] Realized-plus-floating threshold and latch tests pass; timezone/session boundary remains. [ ] API bypass tests. [ ] LLM outage fallback review test.

**Dependencies:** T04, T12, T27. **Likely files:** `lib/features/trading_room/bloc/trading_room_bloc.dart`, `lib/features/trading_room/web/widgets/execution_panel.dart`, `lib/data/repositories/trading_repository.dart`, `server.py`, `firestore.rules`. **Scope:** M.

### T30 — Tab 1 end-to-end acceptance [~]

**Description:** Prove the complete Tab 1 path against all 27 render and eight functional requirements using deterministic fixtures plus authenticated staging data.

**Acceptance criteria:** [~] All 27 render rows have deterministic local automated evidence; same-build authenticated Web runtime evidence remains. [ ] 8/8 function rows pass on Web. [ ] Applicable mobile rows pass. [~] Local evidence identifies source manifest, fixture role, symbol, timeframe, signal ID, and provenance; staging identity remains.

**Verification:** [x] Full regression suites: 141/141 Python and 84/84 Flutter passed. [x] `flutter build web --release` passed. [~] Deterministic evidence is recorded in `tasks/tab1-local-acceptance-2026-09-12.md`; authenticated browser and mobile recorded acceptance remain.

**Dependencies:** T20–T29. **Likely files:** `tasks/acceptance-matrix.md`, `docs/DOD_V21_CHECKLIST.md`, `test/tab1_acceptance_test.dart`, `test_day6_parity.py`. **Scope:** M.

## Checkpoint D — Tab 1

- [ ] 27 render components and eight functions pass.
- [ ] No fake label, cross-symbol price, unsafe execution, or unsupported layer remains.
- [ ] Stakeholder signs off Tab 1 before dependent production integrations continue.

## Phase 5 — Tabs 2 and 3

### T31 — Journal broker metrics [~]

**Description:** Normalize broker-sourced Swap, Commission, and Slippage into the dual trade schema and Journal statistics while preserving paper-trade labeling.

**Acceptance criteria:** [x] Accepted broker metrics require source and currency. [x] Missing/unproven broker metrics display unavailable, not zero-as-real. [x] The dual execution/journal field aliases resolve to the same closed trade. [~] Explicit paper/broker labels are preserved when present; writing the label to legacy persisted trades remains gated by G1/G4.

**Verification:** [x] Model fixture tests cover Swap, Commission, Slippage, source, currency, execution mode, legacy aliases and unavailable values. [ ] Broker sandbox parity sample. [x] Existing journal tests and full Flutter suite pass (50/50); Web release build passes.

**Dependencies:** T04, T09, T03/G4–G5. **Likely files:** `lib/data/models/journal_models.dart`, `lib/data/repositories/journal_repository.dart`, `server.py`, `test/day6_journal_redzone_test.dart`. **Scope:** M.

### T32 — Journal behavioral insight, heatmap, and TTS [~]

**Description:** Generate evidence-based behavior insights and playable Vietnamese/English audio while retaining the existing real-trade heatmap.

**Acceptance criteria:** [ ] TTS button plays/cancels real audio; provider/dependency approval remains. [x] Insight cites the computed worst loss weekday/hour, sample count, and net loss. [x] Readable text remains available and the audio control is explicitly disabled instead of faking playback.

**Verification:** [x] Deterministic loss-time insight calculation test passes. [ ] Audio lifecycle/widget tests. [ ] Web/mobile playback smoke test.

**Dependencies:** T31, G2, G5. **Likely files:** `lib/features/journal/web/journal_web_page.dart`, `lib/features/journal/bloc/journal_bloc.dart`, `lib/data/repositories/journal_repository.dart`, `server.py`, `pubspec.yaml`. **Scope:** M.

### T33 — Approved news sources and normalized sentiment [~]

**Description:** Ingest approved ForexFactory-equivalent calendar and Twitter/X sentiment, deduplicate events, map symbols/currencies, and calculate a transparent -100..100 score.

**Acceptance criteria:** [~] The pure normalized item retains provider, provider type, approval, license reference, observed time, age, and freshness; Firestore persistence waits for G1/G5. [x] The transparent mention-weighted score reaches -100..100 with Bullish `>=25`, Bearish `<=-25`, and Neutral between. [x] Duplicate, stale, unapproved, malformed, and provider-unavailable handling is deterministic and fail-closed.

**Verification:** [x] Five normalization, scoring, mapping, deduplication, freshness, failure and crawler-policy tests pass. [ ] Provider sandbox smoke test. [x] The legacy hardcoded RSS list is removed and crawler startup is disabled while the approved-provider list is empty; G5 must record every future source license.

**Dependencies:** T03/G5, T04. **Likely files:** `server.py`, `lib/data/models/news_models.dart`, `lib/data/repositories/news_repository.dart`, `test/news_sentiment_test.*`. **Scope:** M.

### T34 — What-If scenario workflow [~]

**Description:** Provide a dedicated event scenario request/response contract with assumptions, affected assets, bullish/bearish paths, invalidation, risk notice, and friendly fallback.

**Acceptance criteria:** [~] Python request contract requires the exact `news_what_if` workflow and rejects body-supplied identity; authenticated API/UI wiring remains. [~] Python and Dart contracts require assumptions, affected assets, bullish/bearish paths, invalidation, risk notice and fallback state; per-user save remains gated by T04/G1. [x] Both contracts recursively reject direct or nested Entry/SL/TP/lot/order/execution fields, so a scenario cannot represent a trade.

**Verification:** [~] Four Python contract tests and three Dart model tests pass; API/widget tests remain. [x] 402/429/timeout use one deterministic structured fallback without provider details or fabricated paths. [ ] Auth isolation and authorized persistence test.

**Dependencies:** T04, T12, T33. **Likely files:** `server.py`, `lib/features/news_feed/web/news_feed_web_page.dart`, `lib/features/news_feed/bloc/news_bloc.dart`, `lib/data/repositories/news_repository.dart`, `test/news_what_if_test.dart`. **Scope:** M.

### T35 — Cross-tab scheduled Red Zone [~]

**Description:** Publish HIGH-impact scheduled events into Tab 1 using real start time, duration, currencies, countdown, audible/push policy, and deduplicated lifecycle.

**Acceptance criteria:** [x] Tab 3 stores one `ScheduledNewsEvent` and Tab 1 derives its overlay without changing event ID, start time, duration, currencies, or evidence. [x] Duplicate provider records collapse to the newest evidence for one event lifecycle and expired events return null, causing the binder to clear Layer 5. [~] The alert detector respects opt-out and deduplication; role/device permission delivery remains gated by T28/G1/G5.

**Verification:** [x] Injected-clock cross-tab identity, dedupe, and expiry tests. [x] Layer 5 carries canonical `event_id`, timing, currencies, color, and evidence. [ ] Staging countdown and push evidence.

**Dependencies:** T25, T28, T33. **Likely files:** `lib/features/trading_room/web/widgets/news_red_zone_binder.dart`, `lib/features/news_feed/bloc/news_bloc.dart`, `lib/data/repositories/news_repository.dart`, `server.py`, `test/day6_journal_redzone_test.dart`. **Scope:** M.

## Checkpoint E — Tabs 2 and 3

- [ ] Real broker metrics/TTS and licensed news/sentiment paths pass.
- [ ] Cross-tab event identity and timing are consistent.

## Phase 6 — Tabs 4, 5, and 6

### T36 — Historical Backtest replay engine [~]

**Description:** Load approved historical candles, advance one closed candle at a time, implement x1/x5/x10 control, and persist cursor/session state.

**Acceptance criteria:** [x] The pure replay boundary exposes only candles through the cursor and each playback tick advances exactly one validated closed candle. [~] Pause/resume, x1/x5/x10 cadence, cursor, and playing state survive a validated in-memory snapshot restore; lifecycle persistence remains gated by G1 and the approved dataset identity remains gated by G5. [ ] Placeholder prices, sliders, and equity are removed after repository/BLoC/widget integration.

**Verification:** [x] Four deterministic replay tests cover future isolation, one-candle ticks, x1/x5/x10 cadence, pause/resume, snapshot restore, input copying, and closed/ordered data validation. [ ] Approved historical-provider fixture parity. [ ] Widget interaction test.

**Dependencies:** T03/G5, T09, T10. **Likely files:** `lib/data/models/backtest_models.dart`, `lib/data/repositories/backtest_repository.dart`, `lib/features/backtest/bloc/backtest_bloc.dart`, `lib/features/backtest/web/backtest_web_page.dart`, `test/backtest_replay_test.dart`. **Scope:** M.

### T37 — Backtest No-Repaint execution and lock [~]

**Description:** Analyze only candles through the replay cursor, implement simulated entries/exits/P&L, enforce max-loss lock, generate review, and require explicit acknowledgement to unlock.

**Acceptance criteria:** [x] Analysis receives an immutable list ending at the replay cursor, and mutation of the source's future candle cannot change a prior decision. [x] BUY/SELL trades enter and exit only at the current closed-candle price and reconcile realized balance plus floating equity using an explicit contract size. [~] Max-loss pauses replay and requires the matching generated review acknowledgement; lock/review/trades survive validated snapshot restore, while durable per-user persistence remains gated by G1.

**Verification:** [x] No-Repaint future-mutation test. [x] BUY/SELL realized P&L, balance, and equity test. [~] Domain lock/review/acknowledgement and refresh-restore tests pass, including tampered-balance rejection; repository/widget persistence integration remains.

**Dependencies:** T19, T29, T36. **Likely files:** `lib/features/backtest/bloc/backtest_bloc.dart`, `lib/data/repositories/backtest_repository.dart`, `lib/features/backtest/web/backtest_web_page.dart`, `server.py`, `test/backtest_no_repaint_test.dart`. **Scope:** M.

### T38 — Authenticated community interactions

**Description:** Replace fake identity and wire authenticated posts, comments, reactions, discussion, and share actions with ownership and abuse-safe validation.

**Acceptance criteria:** [ ] User identity derives from auth. [ ] Like/comment operations are idempotent and ownership rules apply. [ ] Empty/error/loading states are real.

**Verification:** [ ] Repository/BLoC/widget tests. [ ] Firestore Emulator ownership tests. [ ] No hard-coded identity remains.

**Dependencies:** T04, T05. **Likely files:** `lib/data/models/community_models.dart`, `lib/data/repositories/community_repository.dart`, `lib/features/community/bloc/community_bloc.dart`, `lib/features/community/web/community_web_page.dart`, `firestore.rules`. **Scope:** M.

### T39 — Privacy-safe trade sharing and leaderboard [~]

**Description:** Convert monetary amounts to permitted growth percentages before persistence/display and compute leaderboard ranking from verified growth and unit volume.

**Acceptance criteria:** [x] The pure Privacy Masker converts verified opening equity/net profit to rounded growth percent and its persistence payload omits broker account ID, verification reference, and raw monetary amounts. [~] Ranking rejects unverified/invalid/duplicate records and deterministically sorts verified growth, then numeric unit volume; authoritative server derivation and Rules enforcement remain gated by T04/T05/G1/G7. [ ] Existing posts require an approved migration/backfill decision.

**Verification:** [x] Privacy payload snapshot and amount/identity exclusion tests. [x] Verified ranking/tie-break fixtures. [ ] Firestore tampering tests. [~] Pure output PII/amount scan passes; repository data-flow scan remains after schema approval.

**Dependencies:** T05, T31, T38, G7. **Likely files:** `lib/data/models/community_models.dart`, `lib/data/repositories/community_repository.dart`, `server.py`, `firestore.rules`, `test/community_privacy_test.dart`. **Scope:** M.

### T40 — Referral QR and personalized Marketing Kit [~]

**Description:** Generate authenticated referral links/QR codes and personalize approved videos/banners with the user's code before download without embedding another user's identity.

**Acceptance criteria:** [~] A validated server-issued code produces one HTTPS canonical link and byte-for-byte QR payload; actual QR image encoding/decoding remains gated by G2. [~] Every approved, licensed Marketing Kit descriptor must contain the active code and cannot retain the template token; binary banner/video rendering and download remain. [x] No approved asset returns an explicit unavailable state, and missing referral stats no longer fabricate `/demo` or derive a code from UID.

**Verification:** [~] Canonical QR payload URI round-trip passes; image encode/decode test awaits an approved QR implementation. [x] Approved/unapproved asset metadata, personalization, missing-token fail-closed, and missing-server-link tests pass. [ ] Web/mobile rendered-asset download smoke test.

**Dependencies:** T04, T03/G2. **Likely files:** `lib/data/models/referral_models.dart`, `lib/data/repositories/referral_repository.dart`, `lib/features/referral/web/referral_web_page.dart`, `pubspec.yaml`, `test/referral_kit_test.dart`. **Scope:** M.

### T41 — F1/F2 accounting and withdrawal workflow [~]

**Description:** Define commission rates and ledger entries, wire withdrawal UI/BLoC/repository, and require Admin approval/rejection with auditable status transitions.

**Acceptance criteria:** [x] Available balance derives only from unique settled immutable credit/debit entries; pending/reversed entries do not alter it and mixed currencies fail closed. [x] Withdrawal creation enforces an explicit currency/minimum policy and cannot exceed available balance. [~] The state machine permits one version-matched approve/reject transition by Super Admin and appends an immutable audit record; verified claims, Firestore transactions, Rules, and the UI workflow remain gated by T04/T05/G1/G6.

**Verification:** [x] Settled/pending credit/debit arithmetic, duplicate-ID, mixed-currency, minimum, and available-balance tests. [~] Stale version and second-decision tests pass locally; real concurrent Firestore transaction tests remain. [ ] Rules/API/Admin workflow tests.

**Dependencies:** T04, T05, T07, T03/G6. **Likely files:** `lib/data/repositories/referral_repository.dart`, `lib/features/referral/bloc/referral_bloc.dart`, `lib/features/referral/web/referral_web_page.dart`, `lib/data/repositories/admin_repository.dart`, `firestore.rules`. **Scope:** M.

## Checkpoint F — Tabs 4–6

- [ ] Backtest, Community, and Referral acceptance rows pass without placeholders or fake identity/data.
- [ ] Privacy and monetary workflow tests pass under concurrency.

## Phase 7 — Roles, Admin, Radar, and privacy

### T42 — Entitlements and server-enforced quotas [~]

**Description:** Implement the approved role model and weekly/daily counters with atomic resets and enforcement on analysis, backtest, realtime, and privileged operations.

**Acceptance criteria:** [~] The server-side contract fixes Standard at 2/week, Professional at 50/day, Enterprise at 300/day, grants Verified Partner only its specified unlimited realtime/multi-timeframe capabilities, and fails closed for the unnamed fifth role or unspecified capabilities; Firebase dependency wiring remains. [~] Web/Mobile no longer display legacy fabricated allowances and show quota only when `source=server_enforced` plus reset metadata is present; the authoritative API response remains unwired. [~] Consumption requires one atomic shared-store compare-and-increment and the contract rejects invalid counts; a production Redis/Firestore implementation remains gated by G1.

**Verification:** [x] Exact role/quota allowlist and fail-closed policy tests. [x] UTC weekly/daily, named-timezone, naive-clock rejection, exhaustion, and 80-request concurrency tests; exactly 50 Professional requests succeed. [x] Two Dart authoritative/unavailable quota model tests and focused Profile analyzer pass. [ ] Firebase-token/API bypass and shared-store integration tests.

**Dependencies:** T03/G3, T04, T05. **Likely files:** `lib/data/models/profile_models.dart`, `lib/data/repositories/profile_repository.dart`, `lib/features/profile/bloc/profile_bloc.dart`, `server.py`, `firestore.rules`. **Scope:** M.

### T43 — Standard ads and Professional purchase entitlement [~]

**Description:** Show approved AdMob placements only for Standard users and validate Professional IAP receipts server-side before granting entitlements.

**Acceptance criteria:** [~] The pure eligibility contract permits only a consented Standard user at an exact approved placement; paid/partner/Admin identities fail closed, while real AdMob widgets remain gated by G2/G5. [~] The client cannot select a role: only a trusted server verifier result matching the verified token subject, an allowlisted Professional product, active state, transaction ID, and future expiry can produce a Professional grant; provider wiring remains gated. [~] Refunded, revoked, expired, cross-user, and cross-product receipts are rejected locally; store restore/webhook persistence and authoritative claim removal remain gated by G1/G2/G5.

**Verification:** [~] Five-identity ad eligibility contract covers Standard, Verified Partner, Professional, Enterprise, and Admin; widget/provider tests remain. [ ] Store sandbox purchase/restore tests. [x] Four server-boundary tests cover active grant, allowlists, malformed input, subject mismatch, refund, revocation, and expiry without calling a provider for rejected client input.

**Dependencies:** T42, G2, G5. **Likely files:** `pubspec.yaml`, `lib/main.dart`, `lib/features/dashboard/mobile/mobile_dashboard_shell.dart`, `lib/data/repositories/profile_repository.dart`, `server.py`. **Scope:** M.

### T44 — Verified Partner and Enterprise controls [~]

**Description:** Gate broker sync/realtime features for Verified Partner and implement Enterprise master/sub-account membership, limits, and aggregate risk without exposing child credentials.

**Acceptance criteria:** [~] The server-side pure authorization contract grants broker sync, realtime signals, and multi-timeframe access exclusively to Verified Partner; UI, Rules, and authenticated API integration remain gated by T04/T05/T07/G3. [~] The Enterprise service reads authoritative membership through an injected store and permits management only when the verified Enterprise master owns the exact subaccount assignment; persistent membership schema remains gated by G1. [~] Aggregate risk requires complete authoritative snapshots for every assigned subaccount, applies an explicit injected policy to both team and target-account exposure, and fails closed on missing/duplicate/invalid state; transaction-time enforcement remains gated by T04/T27/G4.

**Verification:** [x] Five-role matrix tests cover all three exclusive Partner capabilities and reject unrelated capability checks. [~] Local cross-tenant, wrong-role, malformed-membership, duplicate, and incomplete-snapshot denial tests pass; Firebase/API bypass tests remain. [x] Deterministic aggregate-risk fixtures cover allowed, subaccount-limit, team-limit, daily-loss-limit, and proposal accounting paths without credential fields.

**Dependencies:** T07, T27, T42, G3–G4. **Likely files:** `lib/features/trading_room/web/trading_room_web_page.dart`, `lib/data/repositories/profile_repository.dart`, `server.py`, `firestore.rules`, `test/role_entitlement_test.dart`. **Scope:** M.

### T45 — Effective Admin configuration and controls [~]

**Description:** Securely save/cache the master prompt for five minutes and make global risk, kill switch, watchlist, approvals, and service status effective in backend behavior.

**Acceptance criteria:** [~] A pure server boundary accepts only an identity with the verified Admin claim; applying it to UI, Firestore reads/mutations, and Rules remains gated by T04/T05/T07. [~] The authoritative `AdminSettings/ai_config.ai_master_prompt` loader now uses a thread-safe exact five-minute cache, can be invalidated without rebuild, fails closed for missing/invalid content, and no longer has an operational hard-coded prompt fallback; Admin-save invalidation and the Radar worker remain. [~] The backend now reads `admin/system_config.tradingEnabled` off the event loop and gates background analysis, AI chat, and new paper execution while deliberately allowing trade close; global-risk enforcement and authenticated bypass testing remain gated.

**Verification:** [~] Five negative role cases and one verified-Admin case pass at the server contract; UI/Rules/API tests remain. [x] Exact 300-second cache boundary, manual invalidation, invalid-config, and no-stale-fallback tests pass. [~] Both operation types and AST wiring for all three entry points pass; authenticated API bypass test remains. [~] Watchlist validation proves 50/100 accepted and 49/101/duplicate/invalid rejected; worker integration remains T46.

**Dependencies:** T05–T08, T42. **Likely files:** `lib/data/repositories/admin_repository.dart`, `lib/features/admin/bloc/admin_bloc.dart`, `lib/features/admin/web/admin_web_page.dart`, `server.py`, `firestore.rules`. **Scope:** M.

### T46 — 50–100 asset two-stage Radar worker [~]

**Description:** Implement a Redis-backed worker that scans the Admin watchlist, filters real volume ≥3x or structural barriers, calls DeepSeek only for candidates, and publishes traceable confirmations.

**Acceptance criteria:** [~] The deterministic worker requires an exact Admin-validated set of 50–100 assets and complete approved-provider snapshots; real provider throughput/SLA remains gated by G5. [x] Stage one sends only measured volume `>=3x` baseline or provenance-bearing structural barriers to the confirmer; a 100-asset all-reject run makes zero model calls. [~] Every accepted BUY/SELL confirmation cites only included closed source bars and carries a structured Tab 1 target with symbol/timeframe/closed timestamp; FCM route encoding and device navigation remain T47/runtime work.

**Verification:** [x] Six worker tests cover 50/100 assets, both filter reasons, invalid provenance, incomplete snapshots, and untraceable model output. [~] Exact call-count tests prove two candidates/two calls and 100 rejects/zero calls; approved provider/model load test remains. [~] Atomic `begin_once` contract suppresses duplicate confirmation and failed validation abandons the claim for retry; real Redis restart/concurrency remains. [ ] Staging FCM/deep-link evidence. The legacy hard-coded eight-asset momentum publisher is no longer runnable, so no momentum-only result is mislabeled as AI.

**Dependencies:** T10–T19, T45, G2, G5. **Likely files:** `server.py`, `analysis_cache.py`, `lib/data/repositories/radar_repository.dart`, `lib/features/radar/bloc/radar_bloc.dart`, `deploy/REDIS.md`. **Scope:** M.

### T47 — Manual segmented push [~]

**Description:** Send Admin-authenticated messages to all users or approved role/country/device segments with FCM deep links, opt-out handling, preview, delivery status, and audit log.

**Acceptance criteria:** [~] The pure delivery service accepts only role/country/device filters and loads authoritative recipient attributes plus opaque token references from a server store; Firestore/provider adapter wiring remains gated. [x] A verified Admin claim is required before recipient access, and invalid IDs, empty/oversized copy, invalid deep links, zero recipients, recipient overflow, or inconsistent provider results fail closed. [~] Provider-confirmed invalid token references are retired, while summaries and immutable audit models contain counts rather than token fields/values; real FCM error mapping and persistent retirement remain gated by G7.

**Verification:** [x] Exact role/country/device intersection, all-user empty segment, opt-out, wrong-role, zero-recipient, and provider-partition tests pass. [ ] FCM sandbox test. [~] Structured `trading_room` symbol/timeframe/closed-time payload is tested; Web/Android/iOS navigation remains. [~] Audit record/summary expose no token fields or values and invalid refs are retired; persistent append and delivery reconciliation remain.

**Dependencies:** T05, T07, T28, T42, T45, G7. **Likely files:** `server.py`, `lib/core/services/fcm_service.dart`, `lib/data/repositories/admin_repository.dart`, `lib/features/admin/web/admin_web_page.dart`, `firestore.rules`. **Scope:** M.

### T48 — Consent-aware PII DataMasker [~]

**Description:** Create a tested outbound Data Lake boundary that removes or pseudonymizes email, IP, account IDs, tokens, credentials, and configured PII before transmission.

**Acceptance criteria:** [~] The pure outbound boundary emits only a fixed analytics record with an HMAC-SHA256 subject pseudonym and key ID; raw UID, secret key, free text, account/token/credential fields, and token-bearing audit models are absent, while a real Data Lake/log sink remains gated by G7. [x] Exact consent version, explicit grant, deletion-request absence, timezone-aware event time, future rejection, and injected retention duration are enforced; records at expiry fail closed. [x] The event schema is an exact allowlist with typed/ranged values, so every unknown top-level or nested field is rejected rather than heuristically redacted.

**Verification:** [x] Sensitive-key table tests cover email, IP, account ID, auth/FCM token, password, and credential fields plus stable/rotated pseudonyms. [x] Nested metadata and all other unknown fields are rejected. [~] Output field/repr assertions contain no UID/key/token field; a real sink/log scan remains. [~] Deletion service sends only the pseudonymous subject reference and validates deleted count; persistent Data Lake deletion/retention jobs remain gated.

**Dependencies:** T03/G7, T04, T06. **Likely files:** `data_masker.py`, `server.py`, `test_data_masker.py`, `Dockerfile`. **Scope:** M.

## Checkpoint G — Roles/Admin/Radar

- [ ] Quotas, purchases, partner and enterprise controls resist client bypass.
- [ ] Admin controls affect backend behavior and are audited.
- [ ] Radar meets asset count/SLA/call-budget requirements.
- [ ] Data Lake receives only consented, masked records.

## Phase 8 — Hardening and release

### T49 — Reliability, observability, accessibility, and performance [~]

**Description:** Remove blocking I/O from async paths, add structured safe logs/metrics/traces, harden loading/offline/retry/cancellation, and verify responsive/accessibility/localization behavior.

**Acceptance criteria:** [~] Known Firestore and DeepSeek calls in async server paths are dispatched off the event loop and an AST regression test rejects direct synchronous receiver calls; provider-wide concurrency evidence remains. [~] Analysis, chat, and new paper execution emit a closed, identity-free latency/outcome/fallback metric; broader traces and dashboards remain. [~] The local Web login has verified semantics and EN/VI behavior, while authenticated flows, keyboard/text-scale, mobile, and responsive runtime evidence remain.

**Verification:** [~] Static async-boundary and deterministic unit tests pass; sustained concurrency/load testing remains. [x] `flutter analyze` has zero errors and warnings; two legacy Web SDK-migration info findings remain. [~] Local release Web build renders correctly, exposes the login semantics tree, switches EN/VI, and logs no browser error; one environment WebGL fallback warning, mobile/authenticated audit pending. [~] Existing Redis/DeepSeek/fallback tests pass, but the complete Firebase/broker/news/TTS failure-injection matrix remains.

**Dependencies:** T30–T48. **Likely files:** `server.py`, `analysis_cache.py`, `lib/core/localization/app_localizations.dart`, `lib/core/services/fcm_service.dart`, `analysis_options.yaml`. **Scope:** M.

### T50 — Staging acceptance and controlled release [~]

**Description:** Build immutable Web/Android/iOS candidates, deploy only with approval, run the full acceptance matrix, capture evidence, rehearse rollback, then perform a staged production rollout.

**Acceptance criteria:** [ ] All contractual rows pass on identified builds. [~] Local regression suites and Web/Android/iOS release compilation are green; the APK is debug-signed and the iOS app is unsigned, so approved signed mobile candidates, authenticated security/load, and runtime evidence remain. [~] A release/rollback evidence procedure exists, but named owners, approved staging, drills, and G6 production authority remain required.

**Verification:** [~] `flutter test`, `flutter analyze`, `flutter build web --release`, `flutter build apk --release`, and unsigned `flutter build ios --release --no-codesign` completed locally; signing and same-build device/runtime evidence remain. [~] Full deterministic Python suite and backend container source-contract test pass; a Docker engine is unavailable locally, while authenticated API/security and sustained load tests remain. [ ] Staging video/evidence pack. [ ] Production smoke and rollback drill after G6 approval.

**Dependencies:** T01–T49, G6. **Likely files:** `docs/DOD_V21_CHECKLIST.md`, `tasks/acceptance-matrix.md`, `Dockerfile`, `firebase.json`, `deploy/protrading-ai.nginx`. **Scope:** M.

## Final checkpoint H — V2.1 complete

- [ ] 16/16 Master checklist items pass.
- [ ] 27/27 Tab 1 render components pass.
- [ ] 8/8 Tab 1 functions pass.
- [ ] Tabs 2–7 and Admin/Radar/DataMasker pass their acceptance rows.
- [ ] Web production and approved mobile release candidates pass with recorded evidence.
- [ ] No critical/high unresolved security issue or fabricated product data remains.
- [ ] Stakeholder signs the final acceptance matrix.
