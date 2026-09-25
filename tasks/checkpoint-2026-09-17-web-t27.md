# V2.1 Web T27 Checkpoint — 2026-09-17

This supersedes the local source/build identity in `tasks/checkpoint-2026-09-16-t27-panel.md`; it is not staging or production acceptance.

- The Execution Panel and BLoC share one current-chart identity check. Soft, Veto, cutoff, stale-timeframe, and contract-invalid signals expose no order controls. A legacy Soft signal without `chart_id` remains visible but cannot execute; a Hard signal without `chart_id` remains locked.
- A current Hard Setup dispatches one `ExecuteTrade` event with the chart ID. The panel no longer claims an order was submitted before backend confirmation.
- Widget panel tests: 5/5 passed; focused panel/BLoC tests: 12/12 passed; full Flutter suite: 96/96 passed. Focused `dart analyze` on changed panel/BLoC/tests: no issues.
- `flutter build web --release`: passed. Source manifest SHA-256: `afa1a7c30c410837ca593df7117ca855e44d6f28766f4323abc76f82b47c0091`; `build/web` directory digest: `80b25defd3d9e52b48bec876a118cdc5d28474ebe462a0e83d70be3eac1eae9b`.
- Repository-wide `flutter analyze` on this source had no errors or warnings, but 11 pre-existing deprecation infos under Flutter 3.47.4 caused a nonzero exit. The final narrow changed-file analysis passed; `git diff --check` passed.

T27 remains incomplete until authenticated backend `/api/trade` independently enforces signal identity, Hard Setup, cutoff/risk, and idempotency. T04/T05 and approval for the public contract/Firestore changes remain prerequisites. No VPS credential, production write, or deployment was used.
