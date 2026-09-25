# V2.1 Local Checkpoint — 2026-09-16

This supplements the 2026-09-12 checkpoint; it does not certify staging or production.

- T27 client execution now checks the current Hard signal, cutoff, symbol, timeframe, exact chart ID, direction, and execution values before any repository call. A real timeframe change clears the old signal; selecting an alias of the current timeframe preserves it.
- The chart-layer widget test disables only the Flutter test runtime's InkSparkle splash. This avoids a reproducible shader-manifest decode error under Flutter 3.47.4 while retaining the layer, gesture, tooltip, and callback assertions.
- `flutter test -r expanded`: 91/91 passed.
- `flutter build web --release`: passed; `build/web` directory digest `07e435715ade7b49aeab885e45df22142d2fa2706a4fd212be1d7c1c0b89de92`.
- Focused `dart analyze` on the changed trading and test files: no issues. Repository-wide `flutter analyze` reported no errors or warnings, but 11 existing deprecation infos under Flutter 3.47.4 and therefore exited nonzero.
- Current source manifest SHA-256: `53b8fcb54184cf6f01961d9bd98a5349b160252484471c521c8c15aef531926c`. The reproduction command is in `tasks/tab1-local-acceptance-2026-09-12.md`.

No new Android or iOS release build was produced from this source identity. The 2026-09-12 build digests must not be used as evidence for it. Backend `/api/trade` identity enforcement, authenticated staging bypass checks, and production acceptance remain gated by the approval decisions in `tasks/plan.md`. No deployment or production mutation was performed.
