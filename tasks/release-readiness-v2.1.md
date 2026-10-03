# V2.1 Release Readiness and Rollback Record

> **Trạng thái hiện tại — 2026-10-03:** FE/BE/Rules/index đã phát hành ngày 25/09;
> BE TradingView đã phát hành ngày 03/10 và có QA production đăng nhập. Các
> mục HOLD/auth/backend cũ phía dưới là hồ sơ lịch sử, không mô tả runtime hiện
> tại. Nghiệm thu toàn bộ Web vẫn chưa đủ; xem
> `checkpoint-2026-10-03-web-production-readiness.md` và checkpoint TradingView
> production để biết điều kiện còn thiếu, identity mới và rollback assets.

> The original immutable identities below describe the 2026-09-12 source. The
> current Web candidate and production inspection are recorded in
> `tasks/checkpoint-2026-09-17-web-auth-sessions.md`. Mobile release identities
> are outside the current Web-only acceptance scope.
> The current local Rules/index and Web-flow delta is recorded in
> `tasks/checkpoint-2026-09-25-web-local.md`; it has only an unauthenticated
> browser smoke, not same-build authenticated or production acceptance.

This record is local build evidence, not staging or production approval. An
approved QA identity was used for authenticated Web inspection, but no deploy,
production mutation, push, or live trade was performed. Production still
reports `v21-day7` and therefore does not verify this source.

## Current Web candidate — 2026-09-17

| Item | Evidence | Status |
|---|---|---|
| Web release manifest | `04a1c8cbe14b8338c97be3ebab1d4c28c75b85e35571335ee2ba935f9b50719e` (41 MB) | Built locally; not deployed |
| Flutter suite | 103/103 passed | Green |
| Python suite | 178 discovered: 166 passed, 12 Emulator-only cases skipped; 8/8 cache-neutrality/single-flight/security tests passed | Green outside the Rules gate |
| Firestore Rules gate | 12 cases executed: 3 baseline passed, 9 security/functional cases failed | Red: G1 Rules patch required; failures are now committed regression tests |
| Static analysis | Zero errors/warnings; 2 Web and 3 Mobile deprecation infos | Green for correctness; Web deprecation debt remains |
| Authenticated browser | Production login plus Trading/Journal; local release login plus all non-admin Web pages at desktop and responsive checks at 600 px | Admin needs a QA identity with verified `admin=true` claim |
| Backend production | Image created 2026-09-06; deployed source hash differs from local | Red: candidate absent from production |
| Production auth/CORS | Anonymous AI chat returns 200; untrusted origin is reflected with credentials | Red: security stop condition |
| Provider runtime | Market stream, News DNS, Radar fetch errors; DeepSeek returns HTTP 402 | Red: reliability stop condition |

The production rollout is currently `HOLD`. Deploying the Web bundle alone
would make its authenticated API calls fail against the old backend. Backend,
Web and approved Rules/index changes must be staged as one versioned candidate,
then pass the remaining browser and emulator gates before production approval.

## Immutable local identities

| Item | Identity | Status and limitation |
|---|---|---|
| V2.1 source manifest | `9cdb0c5f386520af2b3f79b2fbdf03afe705f2eb3e2e8a737aded1ce81ff0e8c` | Reproduction command is in `tasks/tab1-local-acceptance-2026-09-12.md`; credential files and generated Xcode settings are excluded |
| Web release directory | `f2a9b9fc73510ba8416f5e0f11eb2e4f3767002236c66d99297301b02e819841` | Built locally; not deployed |
| Android release APK | `7f858428ab5b58d63eef486206147edf7be1d956896789e11ec0a7c0387bc00d` | 54,546,937 bytes; Android API 23+; existing release config is debug-signed |
| iOS release app directory | `577ea48ad6753a4dce796eb62888640fd842033aa83b7423b3fc515da97da86a` | iOS 15+; built with `--no-codesign` |

## Local gates completed

- Python regression: 141/141 passed; V2.1 Python modules compile.
- Backend container source contract passes after including all local direct imports;
  an image build/startup is still unverified because this host has no Docker engine.
- Flutter regression: 84/84 passed.
- Flutter analyze: zero errors and warnings; two legacy Web-only `dart:html`
  deprecation infos remain.
- Web, Android, and unsigned iOS release compilation passed.
- Local Web login smoke: 1280x720 render, complete login semantics, EN/VI
  switch, no console error; the test environment emitted one WebGL-to-CPU
  fallback warning.
- Whitespace/error-marker check: `git diff --check` passed.

## Gates required before staging

1. Resolve G1-G5 and G7 in `tasks/plan.md`, including authoritative Firebase
   identity/Rules, named role policy, licensed provider sandboxes, approved
   production dependencies, and privacy/retention policy.
2. Assign named owners for release command, backend, Firebase, Web QA, Android,
   iOS, security, and rollback. Placeholders are deliberately not treated as
   approval.
3. Produce signed Android and iOS candidates from the same reviewed source
   manifest. Record certificate/team identifiers without exposing secrets.
4. Establish an approved staging environment with isolated test users, test
   broker/provider accounts, Redis/Firebase access, and auditable build IDs.
5. Define and approve numeric latency, error-rate, saturation, and rollback
   thresholds from an observed baseline; this document does not invent them.

## Same-build staging acceptance sequence

1. Record source, backend image, Web release, Android, iOS, environment, reviewer,
   and effective role identities. Use pseudonymous test-user references only.
2. Run token identity, cross-user isolation, Rules/API bypass, Admin role, quota,
   entitlement, and kill-switch tests before any trading workflow.
3. Run provider failure injection for market data, Firebase, Redis, DeepSeek,
   licensed news, broker, notification, TTS, purchase, and Data Lake boundaries;
   verify deterministic, labeled degraded states and safe logs.
4. Run concurrent market sessions, cache single-flight, 50-100 asset Radar, and
   sustained load tests against the approved thresholds.
5. Execute every automated and runtime row in `tasks/acceptance-matrix.md` on Web,
   Android, and iOS where applicable. Attach device/browser versions, timestamps,
   screenshots/video, request correlation IDs, and reviewer sign-off.
6. Reconcile paper trades, per-symbol marks, broker/account facts, referral
   ledger, quotas, notifications, and retained/deleted analytics records against
   authoritative sources. Never use a chart price for another symbol.
7. Mark a row `PASS` only when its automated and runtime evidence refer to these
   exact candidate identities and every discrepancy is closed.

## Stop criteria

Stop the rollout and preserve evidence if any of the following occurs:

- authentication, authorization, tenant isolation, consent, or secret exposure;
- cross-symbol price/P&L contamination, execution without a valid Hard Setup,
  Veto/risk/cutoff bypass, or any unintended live trade;
- fabricated provider/account/analysis data or non-deterministic result for an
  identical closed-candle input;
- schema incompatibility, unreconciled money/ledger values, or data loss;
- failed health/readiness checks, error/latency/saturation above the approved
  thresholds, or a required observability signal is absent;
- a candidate/build identity differs from the reviewed evidence.

## Rollback rehearsal and production procedure

1. Before release, capture the currently running backend image digest, Firebase
   Hosting release ID, mobile store versions, Rules/index versions, configuration
   revisions, and any approved migration/backfill checkpoint.
2. Rehearse rollback in staging: restore the previous immutable backend and Web
   versions, revert configuration via its audited revision, verify Rules/schema
   compatibility, and repeat health plus critical auth/trading smoke tests.
3. After explicit G6 approval, roll out progressively to the approved audience.
   Mobile rollout must use signed store/TestFlight candidates and staged rollout
   controls; Web/backend changes must retain the previous immutable release.
4. On a stop condition, halt expansion, restore the previous immutable versions,
   disable unsafe new execution through the approved kill switch if applicable,
   preserve logs/correlation IDs, and notify the named owners. Do not delete or
   rewrite evidence.
5. Complete production smoke and the rollback drill only with the approved test
   identities and scope. Production users, credentials, push delivery, data
   mutation, or live trading are never implicit in G6.

## Current disposition

`HOLD`: local Web build, deterministic regression gates, and authenticated
same-build browser checks for every non-admin page are green. The production
backend is older, anonymous private API access and reflective CORS are still
active, provider failures are present, nine Firestore Rules checks
fail, and Admin lacks a claim-bearing QA identity. Staging, rollback rehearsal,
named release/monitoring owners, stakeholder sign-off, and explicit G6
authority remain required.
