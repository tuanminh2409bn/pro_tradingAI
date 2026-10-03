# TradingView free-candle probe — 2026-10-03

## Scope and evidence

- User requested inspection and a bounded live test of `scripts/tradingview_probe.py` before choosing a temporary free provider.
- Twelve anonymous read-only WebSocket connections were made from local: two passes over M5/M15/H1/H4/D1 plus a final CLI smoke check over M5/H4 for the exact symbol `OANDA:XAUUSD`; 151 bars requested per connection. No TradingView login or APISed key used.
- All five timeframes returned 151 closed OHLCV bars with nonzero volume. Initial connection times were 0.47–0.71 seconds per timeframe. This verifies this symbol at this time; other instruments, long-running service reliability and concurrent users were not tested.
- Detailed second-pass results: `tasks/tradingview-probe-2026-10-03.json`.
- Latest M5 bar opened on 2026-10-02 at 20:55 UTC. The test was performed Saturday; the sample is historical, not evidence of a current live quote.

## Existing backend acceptance

| Timeframe | Existing validate_candle_history result |
| --- | --- |
| M5 | Passed |
| M15 | `unexpected_gap` |
| H1 | `unexpected_gap` |
| H4 | `timestamp_not_aligned` |
| D1 | `timestamp_not_aligned`, `unexpected_gap` |

The backend requires UTC alignment and exact ordered series with allowed market closures.
TradingView returns provider session boundaries. No timestamps were rounded, no candles
were synthesized, and the backend gates remain unchanged. A successful diagnostic is
not an accepted MTF provider for all three trading modes, nor a Web completion claim.

## Changes

- Probe uses `websockets`, already declared in `requirements.txt`, instead of undeclared `websocket-client`; installed only in `/tmp/protrading-probe-deps` for this run.
- Added bounded completion handling, H4/D1, preserved original price precision and missing volume, explicit CLI exit status, and optional unchanged backend validation.
- Removed the APISed hardcoded credential; legacy APISed probe is opt-in and reads the key from its environment. No credential rotation performed.
- Offline regression tests are in `test/backend/test_tradingview_probe.py`.

## Verification

- 21/21 focused offline tests passed: probe (10), MTF history (6), trusted history (5).
- Syntax checks and `git diff --check` passed.
- Final live CLI with `--check-backend --timeframes 5 240` returned the expected exit code 1: M5 passed, H4 failed `timestamp_not_aligned`. Provider connectivity itself succeeded for both.

## Provider decision still open

- TradingView states it does not offer a raw-data API through widgets: https://www.tradingview.com/widget-docs/faq/data/
- Its current terms restrict non-display algorithmic processing and commercial services without a separate agreement: https://www.tradingview.com/policies/ (section 3).
- Thus anonymous accessibility alone does not establish rights for the customer-facing AI product. Resolve data rights and provider session/closure semantics before introducing a TradingView analysis adapter.
- `process_ai_analysis` still uses the existing OANDA adapter. No FE/BE runtime provider, production configuration, deployment or execution authorization changed.
