# Web local checkpoint — 2026-09-24

This records current local work only. It is not staging or production
acceptance. The repository still has pre-existing uncommitted changes, so the
2026-09-17 source/build hash does not identify this working tree.

- W01: every ID in the consolidated requirements has a test target, browser
  target, and status in the acceptance ledger; Web-only scope is stated
  separately. `test_v21_web_traceability.py` passes. Original stakeholder
  sign-off remains a Master T01 obligation.
- W05: the owner approved the local G1 Rules/index patch. Firestore Emulator
  passed 15/15 owner, cross-user, Admin, query, referral, and token cases. Three
  composite indexes were added for the existing Backtest, trade-history, and
  pending-request queries. Existing documents need a read-only ownership audit
  before staging; Rules/index have not been deployed.
- Broker-link Web flow: Trading Room's nonfunctional form now opens Profile's
  existing form. Profile accepts a link request only when the backend returns
  `status=success` with an account ID; creating a pending broker account does
  not mark it as connected. The Verified Partner authorization contract F-01
  still needs separate local approval and implementation.

Verification on this working tree: 182 Python tests pass with 15 Emulator-only
tests skipped in ordinary discovery; the 15 Emulator tests pass separately.
Flutter has 107/107 passing tests, and the Web release build passes. Targeted
Dart analysis of changed code passes. Full `flutter analyze` has no errors or
warnings, but exits nonzero on five existing deprecation infos (two Web, three
Mobile). Authenticated browser and provider runtime checks were not repeated
for this working tree.

The next critical local gate is W06/F-01 role authorization, followed by W09
trusted historical data and W14–W15 server execution/cutoff persistence. The
remaining provider, fifth-role, privacy, and staging decisions are tracked in
`tasks/decisions-v2.1.md`.
