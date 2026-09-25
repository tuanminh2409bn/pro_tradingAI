# V2.1 Web T27 Panel Checkpoint — 2026-09-16

This is local Web evidence only. It does not certify authenticated staging or production execution.

- The Execution Panel and BLoC now share one current-chart identity check. Stale-timeframe, foreign-symbol, and contract-invalid signals cannot expose executable controls. Soft, Veto, and daily-loss cutoff states also expose none.
- A valid Hard Setup dispatches one `ExecuteTrade` event carrying the current chart ID. The panel no longer displays an immediate "order submitted" snackbar before the repository/backend confirms execution.
- New widget test `test/execution_panel_gate_test.dart`: 4/4 passed. Focused panel/BLoC safety tests: 11/11 passed. Full Flutter suite: 95/95 passed.
- Focused `dart analyze` on the touched panel/BLoC/tests: no issues. Repository-wide `flutter analyze`: no errors or warnings, but 11 deprecation infos under Flutter 3.47.4 cause nonzero exit.
- `flutter build web --release`: passed. Source manifest SHA-256: `8a8ba06117ab72ea7cd195d829c71e6dcd8dd031488613178a9f6d7df8534423`; `build/web` directory digest: `36fc63c9a3e2c44f6ce4e2403c9b06ba9bf8dcc2e24322abdd43e076df4a1230`. Reproduce the source hash with the command in `tasks/tab1-local-acceptance-2026-09-12.md`.

T27 remains incomplete: `/api/trade` must independently validate authenticated identity, current Hard Setup, chart ID, cutoff/risk, and idempotency. That requires approval for its public contract and the Firebase/Firestore security work (T04/T05/G1). No VPS credential, production data, production write, or deployment was used.
