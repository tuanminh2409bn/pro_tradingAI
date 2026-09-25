# G1 Firestore Rules proposal — Web V2.1

Status: `APPROVED_FOR_LOCAL`, applied to local `firestore.rules` on 2026-09-24;
not deployed. The original 2026-09-17 baseline below remains historical.

This proposal converts the Web data paths already used by the repositories into
one explicit authorization contract. The executable gate is
`test_v21_firestore_rules.py`; on 2026-09-17 it ran 12 cases against the local
Firestore Emulator: 3 passed and 9 failed.

On 2026-09-24, the owner approved this local Rules/index change. The local
Firestore Emulator now passes 15/15 cases, including a signal-query test,
referral ownership, and Admin-only broadcast writes. The matching local
backtest, trade-history, and pending-request indexes were added. Existing
documents still need a read-only ownership audit before any staging rollout.

## Required authorization contract

| Path | Client read | Client write | Required invariant |
|---|---|---|---|
| `signals/{signalId}` | Signal owner | Backend only | Stored `userId` equals authenticated UID |
| `analysis_requests/{requestId}` | Request owner | Owner creates `PENDING`; backend completes | Client cannot change owner or status after create |
| `users/{uid}/trades/{tradeId}` | Owner | Backend only | Paper execution remains server-authoritative |
| `backtest_sessions/{sessionId}` | Owner | Owner | Create owner matches UID; update cannot change `userId` |
| `backtest_sessions/{sessionId}/trades/{tradeId}` | Parent-session owner | Parent-session owner | Access is derived from the parent session, never from an arbitrary authenticated user |
| `community/{postId}` | Public | Authenticated creator/owner; authenticated likes-only update | Create owner matches UID; every update preserves `userId` |
| `admin/**` and `AdminSettings/**` | Verified `admin=true` claim | Verified `admin=true` claim | Ordinary authenticated users receive permission denied |
| `admin/requests/pending/{requestId}` | Request owner or verified Admin | Owner creates; Admin reviews | Create owner matches UID; client update cannot reassign owner |
| `chat_history/{uid}/{chatType}/{messageId}` | Owner | Owner | UID comes from the path and must equal the authenticated UID |
| `fcm_tokens/{tokenId}` | Token owner | Token owner | Create/update `userId` matches UID; token ownership cannot be reassigned |

Admin SDK calls continue to bypass client Rules. The Web Admin UI must still
perform its existing claim check, and backend Admin mutations must verify the
same claim; Rules are one layer of the three-layer boundary.

## Minimal Rules change after approval

1. Add `isAdmin()` requiring `request.auth.token.admin == true`.
2. Split Backtest create/read/update/delete and require both existing and new
   session ownership on updates. Resolve nested-trade access through `get()` of
   the parent session.
3. Restrict broad `admin` and `AdminSettings` matches to `isAdmin()` so a more
   permissive overlapping match cannot bypass the pending-request rule.
4. Require matching `userId` for Community and pending-request creation; keep
   ownership immutable on updates.
5. Add canonical owner-only matches for chat messages and Web FCM tokens.
6. Keep public `news`, `analytics`, `radar`, Community reads, and leaderboard
   reads unchanged unless a separate product decision changes their contract.

No persistent schema migration is needed for newly created compliant records.
Existing Backtest, Community, pending-request, and FCM documents must be audited
for missing or inconsistent `userId` before production deployment. That audit
is read-only until a separate backfill is approved.

## Verification and rollout

1. Apply the approved patch only to the local Rules file.
2. Run all 12 Emulator cases and require 12/12 passing.
3. Add query/index checks for every changed repository query; update indexes
   only if the Emulator or staging query proves one is required.
4. Deploy Rules to staging together with the matching backend and Web build.
5. Test owner, cross-user, unauthenticated, and verified-Admin sessions in the
   browser. Confirm Web FCM opt-in can create and delete only its own token.
6. Record the Rules release identifier, perform the rollback rehearsal, and
   request the separate G6 production approval.

Rollback restores the previous versioned Rules only together with the previous
compatible Web/backend release. A Rules rollback must never reopen the nine
known failures to production traffic.
