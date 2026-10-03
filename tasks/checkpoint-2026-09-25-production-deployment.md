# Web/BE production deployment checkpoint — 2026-09-25

## Released identity

- GitHub branch: `codex/web-backend-release-20260925`, commit `7c5ef68febcc2799d1f37c4324460c579d56f929`. The same commit was fast-forwarded directly to remote `main` after the production release. The temporary repository-scoped push tokens were revoked after verification of the remote refs.
- FE: Firebase Hosting `https://protrading-ai-2026.web.app/`; served `main.dart.js` SHA-256 `3ad38cd3e0b015eb3bd4f06654653f0abedf444c50e3c30f2821484912af6e97`, identical to the local release build. The candidate preview is `https://protrading-ai-2026--release-7c5ef68-62z7yj63.web.app/` (expires 2026-10-02).
- BE: VPS container `protrading-ai-live-7c5ef68`, image `sha256:3b92df109b789029c3dc5d59eb698a804b6bceecadfbe559cfba599db4c8f8de`, behind `https://103-69-189-243.sslip.io/`. The previous `protrading-ai` container and image were retained, stopped.
- Firestore Rules: the released text matched local `firestore.rules` (length 7,794, FNV-32 `e759b74f`). The prior production Rules matched `origin/main:firestore.rules` exactly (length 3,121, FNV-32 `7a34b646`). Four composite indexes were deployed and reached `Enabled` in Firebase Console.
- FE rollback channel: `https://protrading-ai-2026--backup-20260925-u2n67svo.web.app/`, cloned from live before this release.

## Verification

- `flutter test`: 120/120 passed. `flutter analyze --no-pub --no-fatal-infos`: exit 0; three existing Mobile deprecation infos. `flutter build web --release`: passed.
- Python discovery: 216 cases found; 193 passed and 23 Emulator-only cases were skipped because this host has no usable Java runtime. The same source passed 216/216 with Auth/Firestore Emulators in the preceding local QA checkpoint.
- BE candidate built on the VPS and passed loopback health, Redis connection, anonymous private API 401, invalid image proxy 400, and untrusted-origin CORS rejection before cutover.
- After cutover: public HTTPS `/health` 200 with Redis, anonymous private API 401, FE index 200, served Web SHA-256 matched local, Web login page rendered, browser error log empty, BE container running with zero restarts and zero `Traceback`/`ERROR`/`Exception` matches in the initial log window.

## Remaining acceptance limits

- This deployment does **not** close the Web completion plan. OANDA practice credentials and licensed calendar/social sources are absent, so their dependent flows remain unavailable. Referral money/withdrawal and Data Lake remain disabled by policy.
- Production Firebase Auth has Email/Password disabled; no temporary production QA account or authenticated browser acceptance was performed. The four existing Auth users have neither `admin` nor `role` custom claims, so an Admin production flow has not been accepted.
- The full same-build staging matrix, live paper trade/cutoff, provider samples, push, Admin mutation, referral and all-tab authenticated journeys remain open. Do not describe this release as Web 100% complete.

## Rollback assets

- BE: stop `protrading-ai-live-7c5ef68` and start the retained `protrading-ai` container, then verify HTTPS `/health` and authenticated critical flows.
- FE: clone Hosting channel `backup-20260925` back to `live`, then verify the served JS identity.
- Rules: the exact previous production text is `origin/main:firestore.rules` at `b7d2f2c`; Firebase Console also retains the May 27, 2026 release. Indexes can remain while rolling back the FE/BE; review query behavior before deleting them.

No VPS password, provider key, service-account body or user token is recorded here.
