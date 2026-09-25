# Tab 1 Local Acceptance Evidence — 2026-09-12

This record covers deterministic local verification for T30. It is not staging or
production acceptance. A requirement remains non-PASS until runtime evidence from
the same identified build is attached to `tasks/acceptance-matrix.md`.

## Build identity

- Baseline commit: `b7d2f2c23506`
- Local source-manifest SHA-256: `9cdb0c5f386520af2b3f79b2fbdf03afe705f2eb3e2e8a737aded1ce81ff0e8c`
- Manifest scope: current Python, Dart, schema, Firebase, dependency, Android,
  iOS, Web manifest, test, and container source/configuration files. Credential
  files and generated Xcode settings are deliberately excluded.
- Flutter: `3.32.8` stable project metadata revision
  `edada7c56edf4a183c1735310e123c7f923584f1`
- Python: `3.14.7`
- Environment: local workspace; no staging deployment, credential, private user
  data, provider mutation, notification delivery, or live trade.

The source hash can be reproduced from the file list used by this checkpoint:

```sh
rg --files -g '*.py' -g '*.dart' -g '*.json' -g '*.yaml' -g '*.yml' \
  -g '*.kts' -g '*.gradle' -g '*.xcconfig' -g '*.plist' -g '*.rules' \
  -g 'Dockerfile' -g 'requirements.txt' -g 'pubspec.lock' -g 'Podfile' \
  -g 'Podfile.lock' -g 'project.pbxproj' -g 'contents.xcworkspacedata' \
  | rg -v 'adminsdk|Generated\.xcconfig$' | sort \
  | xargs shasum -a 256 | shasum -a 256
```

## Deterministic fixture identity

- Role: no authenticated role; local contract/render fixture only
- Symbol/timeframe: `XAUUSD` / `M5`
- Signal ID: canonical `chart_id` `XAUUSD_M5_1700003300`
- Data provenance: every analytical overlay carries `source=fixture`, a stable
  `source_id`, and timestamp. Scheduled-news tests use explicitly licensed-source
  fixture metadata. These fixtures prove deterministic behavior, not live data.

## Tab 1 render traceability

`AUTO_PASS` means the relevant deterministic test passed in the 84-test Flutter
suite. Runtime remains mandatory for final PASS.

| ID | Local automated evidence | Local status | Runtime still required |
|---|---|---|---|
| R-01 | `kinetic_chart_layers_test.dart`: diagonal dashed line | AUTO_PASS | Web/mobile visual capture |
| R-02 | Same fixture: solid OB box and canonical colors | AUTO_PASS | Pixel/visual capture |
| R-03 | Same fixture: transparent bordered mitigation box | AUTO_PASS | Pixel/visual capture |
| R-04 | Same fixture plus parser length validation | AUTO_PASS | Overlap/text-scale review |
| R-05 | Same fixture: backend `$$$` tag | AUTO_PASS | Marker visual capture |
| R-06 | Same fixture: backend `LIQ` tag/background | AUTO_PASS | Marker visual capture |
| R-07 | Same fixture: directed trap arrow and label | AUTO_PASS | Marker visual capture |
| R-08 | Same fixture plus VSA provenance suite: measured STOP | AUTO_PASS | Real-volume sample trace |
| R-09 | Renderer/default candle contract | AUTO_PASS | Bull/bear visual capture |
| R-10 | Five-layer fixture plus VSA provenance: climax | AUTO_PASS | Real-volume sample trace |
| R-11 | Parser/renderer contract plus VSA provenance: ND/NS | AUTO_PASS | Real-volume sample trace |
| R-12 | Parser/renderer contract: two-character candle text | AUTO_PASS | Pixel/visual capture |
| R-13 | Five-layer fixture plus VSA provenance: spread border | AUTO_PASS | Real-spread sample trace |
| R-14 | Five-layer fixture: directed divergence | AUTO_PASS | Marker visual capture |
| R-15 | `analysis_contract_test.dart`, `trading_signal_safety_test.dart` | AUTO_PASS | Soft/Hard/Veto runtime transition |
| R-16 | Canonical Layer 4 fixture: blue Entry line | AUTO_PASS | Right-axis badge capture |
| R-17 | Canonical Layer 4 fixture and stage gate: one red SL | AUTO_PASS | Structural-source trace |
| R-18 | Layer 4 fixture and TP3 opacity test | AUTO_PASS | TP selection capture |
| R-19 | `take_profit_allocation_test.dart`: 100%, lot-step, API legs | AUTO_PASS | Paper execution reconciliation |
| R-20 | Contract test: real probability or hidden/null | AUTO_PASS | Real backtest provenance |
| R-21 | Canonical Layer 4 momentum fixture | AUTO_PASS | Marker visual capture |
| R-22 | Canonical quadratic/cubic curves terminate at TP3 | AUTO_PASS | Dashed/glow visual capture |
| R-23 | Canonical evidence-backed Ghost Box at 15% | AUTO_PASS | HTF-source trace |
| R-24 | Ghost hit-test tooltip and bounded focus interaction | AUTO_PASS | Web/mobile interaction capture |
| R-25 | Countdown, repaint, scheduled-event strictness tests | AUTO_PASS | Approved calendar parity |
| R-26 | Evidence-backed Wyckoff fixture/no-fabrication suite | AUTO_PASS | Real-analysis source trace |
| R-27 | HTF fixture and legend callback opens `H4` | AUTO_PASS | Web/mobile navigation capture |

Local result: **27/27 render requirements have deterministic automated coverage**.
Final contractual result remains **0/27 PASS** because same-build authenticated
Web/mobile runtime evidence has not been produced.

## Tab 1 function traceability

| ID | Local automated evidence | Local status | Missing for contractual PASS |
|---|---|---|---|
| F-01 | Client-side gate coverage is incomplete | INCOMPLETE | Approved role claim, Rules, and backend enforcement |
| F-02 | Existing popup/widget path is covered locally | AUTO_PARTIAL | Authenticated eligible first-run persistence capture |
| F-03 | Account model exposes unavailable instead of invented values | BLOCKED | Licensed authorized broker sandbox and approved role |
| F-04 | Existing risk-input gate behavior is covered locally | AUTO_PARTIAL | Fresh authenticated-user Web/mobile flow |
| F-05 | Exact three-timeframe matrix unit tests pass | AUTO_PASS | Web/mobile interaction capture |
| F-06 | Forecast-below-chart and Soft execution safety tests pass | AUTO_PASS | Responsive Web/mobile visual capture |
| F-07 | Two-level detector, dedupe, Veto, and opt-out tests pass | AUTO_PARTIAL | Permission adapters plus FCM/device/browser delivery |
| F-08 | Realized+floating cutoff and latch tests pass | AUTO_PARTIAL | Persistence, backend bypass rejection, review/unlock |

Local result: F-05 and F-06 have complete provider-independent automated
coverage; F-02/F-04/F-07/F-08 are partial; F-01 is incomplete; F-03 is gated.
The contractual result remains **0/8 PASS** until same-build authenticated runtime
evidence exists.

## Verification commands and results

- `python3 -m unittest discover -q`: 141/141 passed.
- `python3 -m py_compile server.py admin_controls.py feature_engine.py analysis_cache.py analysis_contract.py data_masker.py entitlements.py enterprise_controls.py news_scenario.py news_sentiment.py observability.py radar_worker.py push_delivery.py specialist_analysis.py`: passed.
- `flutter test -r compact`: 84/84 passed.
- `flutter build web --release`: passed; directory digest `f2a9b9fc73510ba8416f5e0f11eb2e4f3767002236c66d99297301b02e819841`.
- `flutter build apk --release`: passed; APK SHA-256 `7f858428ab5b58d63eef486206147edf7be1d956896789e11ec0a7c0387bc00d`; existing release config is debug-signed, not production-ready.
- `LANG=en_US.UTF-8 LC_ALL=en_US.UTF-8 flutter build ios --release --no-codesign`: passed; unsigned app directory digest `577ea48ad6753a4dce796eb62888640fd842033aa83b7423b3fc515da97da86a`.
- `flutter analyze`: zero errors and warnings; two info-level legacy Web SDK migration findings remain.
- Local Web runtime: desktop login rendered at 1280x720; semantics exposed every login control; EN/VI switch passed; console had no errors and one WebGL-to-CPU environment warning.
- `git diff --check`: passed.

## Runtime acceptance script still pending

Run this only after G1/G2/G3/G5/G6 decisions and an identified staging deploy:

1. Record immutable build ID, environment, reviewer, user UID hash and effective
   role; never record credentials or raw private data.
2. Use one approved real-data `XAUUSD` signal for each required mode/timeframe and
   record `chart_id`, closed-candle timestamp, provider/source IDs and cache state.
3. Capture all R-01..27 on Web, then repeat touch/applicable rows on Android and
   iOS against the same build.
4. Execute F-01..08 with eligible and ineligible accounts, provider outage,
   Soft/Hard/Veto transitions, notification permissions, cross-symbol positions,
   cutoff bypass attempts and review/unlock.
5. Reconcile paper executions, provider/account values and audit records with
   their authoritative sources. Attach artifacts and reviewer/date per row.
6. Mark a row PASS only when its automated and runtime artifacts match the build
   and no unresolved discrepancy remains.

Production currently reports `v21-day7`, which predates this local manifest and
therefore cannot be used as acceptance evidence for these changes.
