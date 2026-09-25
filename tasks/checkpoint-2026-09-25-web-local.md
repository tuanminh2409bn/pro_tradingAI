# Web local checkpoint — 2026-09-25

This is a working-tree checkpoint, not staging or production acceptance. The
repository has pre-existing uncommitted changes, so the older immutable source
hashes in the release record do not identify this tree. No code was committed,
pushed or deployed for this checkpoint.

## Local behavior and evidence

- W01/W03: the Web acceptance map and delegated product/provider defaults are
  recorded in `web-completion-plan.md`, `decisions-v2.1.md` and
  `provider-matrix.md`. Provider access and licensing remain external gates.
- W04/W05/F-01: private API token checks, exact Verified Partner broker-link
  claim, and owner-scoped Firestore Rules are in place. The client cannot forge
  profile tier/broker state, referral ledger, broker account or cutoff state.
  Firestore Emulator passes 20/20 cases, including malformed analysis requests.
  Browser role-matrix and existing-document audit remain open.
- W09/W14: OANDA Practice adapter requests exact closed MTF candles with tick
  volume; unsupported or absent provider data yields an unavailable signal and
  never enters the shared cache. Paper-trade validation requires the trusted
  history provenance, matching signal, owner and idempotency key. No OANDA
  account/sample is configured or claimed as tested.
- W15: UTC daily cutoff is persisted server-side and checked before Analyze and
  Trade. Review and acknowledgement APIs and Web banner are wired. Browser
  refresh and authenticated Firestore transaction evidence remain open.
- W19/W34: Journal Web TTS uses browser speech playback/stop where available;
  Web `dart:html` imports were replaced with JS interop. The current release
  build rendered the login page, switched EN/VI and had no console error in an
  unauthenticated browser smoke. Authenticated audio/page checks remain open.
- Notification security: executable user signals now target only that owner's
  opted-in FCM tokens; recipient filtering is unit tested. FCM sandbox delivery
  and deep link are still open.
- Analysis queue boundary: Firestore Rules limit request keys, symbol and
  mode/timeframe; the listener rejects malformed pending requests before any
  provider work. This does not yet implement atomic quota/rate enforcement.
- AI chat now sends a chart price only when the requested symbol and timeframe
  match the active display stream. A mismatch is labeled unavailable; no raw
  candle dump is sent in the chat prompt. Chat input length and market IDs are
  bounded. Provider-sandbox behavior remains unverified.
- Community posts may be created only with owner UID, bounded text, zero
  engagement counts and no client-asserted verification. Client updates can no
  longer forge verified trades, profit or likes. Existing documents need audit
  before their historical verification flags can be trusted. The new
  `/api/community/like` derives UID from the Firebase token and atomically
  records one marker per user/post; a repeated request returns the existing
  like without increasing the counter. The Web button is wired through
  Repository/BLoC and shows disabled/busy/error states. The currently deployed
  backend does not have this endpoint; authenticated same-build browser testing
  remains open. A real Firestore Emulator transaction counted Alice and Bob
  once each and kept a replay at the same count. Comments, share and
  authoritative ranking remain W24/W25 work.

## Verification on this tree

- Python discovery: 212 tests, 191 passed and 21 Emulator-only skipped.
- Firestore Emulator: 21/21 passed separately. The transaction case used a
  temporary Python environment outside the repository with the existing
  `firebase-admin` and `fastapi` dependencies.
- Flutter: 117/117 passed.
- Flutter analyzer: exit 0 with `--no-fatal-infos`; zero errors/warnings and
  three Mobile-only `activeColor` deprecation infos.
- Flutter Web release build: passed after the Community like UI change.
- Python syntax/import and Dockerfile local-import contract: passed.
- `git diff --check`: passed.

## Remaining Web acceptance gates

W06, W09, W11–W35 are not all complete. The critical missing evidence is a
licensed provider sandbox and sample, a claim-bearing Web QA user, authenticated
same-build browser flows, quota/concurrency checks, and staging/runtime checks.
The chosen defaults keep referral cash/withdrawal, Data Lake export, X sentiment
and unlicensed calendar data unavailable. No PASS status in the acceptance
matrix is inferred from pure fixtures or the unauthenticated login smoke.
