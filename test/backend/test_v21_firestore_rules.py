"""Firestore Emulator owner/cross-user rules checks (never contacts production)."""

import base64
import json
import os
import re
import time
import unittest
import urllib.error
import urllib.request
import uuid
from datetime import datetime, timedelta, timezone


EMULATOR = os.environ.get("FIRESTORE_EMULATOR_HOST", "")
PROJECT = "protrading-ai-2026"


def _encode(value):
    return base64.urlsafe_b64encode(
        json.dumps(value, separators=(",", ":")).encode()
    ).decode().rstrip("=")


def _token(uid, *, admin=False, role=None):
    now = int(time.time())
    claims = {
        "iss": f"https://securetoken.google.com/{PROJECT}",
        "aud": PROJECT,
        "sub": uid,
        "user_id": uid,
        "iat": now,
        "exp": now + 3600,
        "firebase": {"sign_in_provider": "password"},
    }
    if admin:
        claims["admin"] = True
        if role is None:
            role = "standard"
    if role is not None:
        claims["role"] = role
    return ".".join((
        _encode({"alg": "none", "typ": "JWT"}),
        _encode(claims),
        "",
    ))


def _request(method, path, uid=None, fields=None, *, admin=False, role=None):
    url = f"http://{EMULATOR}/v1/projects/{PROJECT}/databases/(default)/documents/{path}"
    data = None
    if fields is not None:
        data = json.dumps({"fields": {
            key: (
                {"booleanValue": value}
                if isinstance(value, bool)
                else {"timestampValue": value.isoformat().replace("+00:00", "Z")}
                if isinstance(value, datetime)
                else {"integerValue": str(value)}
                if isinstance(value, int)
                else {"doubleValue": value}
                if isinstance(value, float)
                else {"stringValue": value}
            )
            for key, value in fields.items()
        }}).encode()
    headers = {"Content-Type": "application/json"}
    if uid:
        headers["Authorization"] = (
            "Bearer owner"
            if uid == "_admin"
            else f"Bearer {_token(uid, admin=admin, role=role)}"
        )
    request = urllib.request.Request(url, data=data, method=method, headers=headers)
    try:
        with urllib.request.urlopen(request, timeout=15) as response:
            return response.status
    except urllib.error.HTTPError as error:
        status = error.code
        error.close()
        return status


def _query(collection, uid, filters):
    url = (
        f"http://{EMULATOR}/v1/projects/{PROJECT}/databases/(default)/"
        "documents:runQuery"
    )
    field_filters = [
        {
            "fieldFilter": {
                "field": {"fieldPath": field},
                "op": "EQUAL",
                "value": {"stringValue": value},
            }
        }
        for field, value in filters.items()
    ]
    where = (
        field_filters[0]
        if len(field_filters) == 1
        else {"compositeFilter": {"op": "AND", "filters": field_filters}}
    )
    body = json.dumps({
        "structuredQuery": {
            "from": [{"collectionId": collection}],
            "where": where,
        }
    }).encode()
    request = urllib.request.Request(
        url,
        data=body,
        method="POST",
        headers={
            "Content-Type": "application/json",
            "Authorization": f"Bearer {_token(uid)}",
        },
    )
    try:
        with urllib.request.urlopen(request, timeout=15) as response:
            return response.status
    except urllib.error.HTTPError as error:
        status = error.code
        error.close()
        return status


@unittest.skipUnless(
    re.fullmatch(r"(?:127\.0\.0\.1|localhost):[0-9]+", EMULATOR),
    "requires a loopback Firestore Emulator",
)
class FirestoreRulesTests(unittest.TestCase):
    def test_owner_cannot_forge_broker_or_tier_on_profile(self):
        path = "users/alice"
        base = {"brokerLinked": False, "tier": "FREE", "username": "alice"}
        self.assertEqual(_request("PATCH", path, "_admin", base), 200)
        self.assertEqual(_request("GET", path, "alice"), 200)
        self.assertEqual(_request("GET", path, "bob"), 403)
        self.assertEqual(
            _request("PATCH", path, "alice", {**base, "brokerLinked": True}),
            403,
        )
        self.assertEqual(
            _request("PATCH", path, "alice", {**base, "tier": "enterprise"}),
            403,
        )
        self.assertEqual(
            _request("PATCH", path, "alice", {**base, "username": "new-name"}),
            200,
        )
        new_uid = f"new-{uuid.uuid4().hex}"
        self.assertEqual(
            _request(
                "PATCH", f"users/{new_uid}", new_uid,
                {"brokerLinked": True, "tier": "enterprise"},
            ),
            403,
        )
        self.assertEqual(
            _request(
                "PATCH", f"users/{new_uid}", new_uid,
                {
                    "username": "new",
                    "email": "new@example.test",
                    "displayName": "New",
                    "tier": "FREE",
                    "totalTrades": 0,
                    "winRate": 0.0,
                    "rank": 0,
                    "avatarUrl": "",
                    "brokerLinked": False,
                    "syncGateDismissed": False,
                    "manualRiskMode": False,
                    "createdAt": "test-time",
                    "lastSeen": "test-time",
                },
            ),
            200,
        )

    def test_quota_and_broker_accounts_are_backend_writable_only(self):
        for path in (
            "users/alice/meta/quota",
            "users/alice/broker_accounts/account-1",
        ):
            with self.subTest(path=path):
                self.assertEqual(_request("PATCH", path, "_admin", {"status": "PENDING"}), 200)
                self.assertEqual(_request("GET", path, "alice"), 200)
                self.assertEqual(_request("GET", path, "bob"), 403)
                self.assertEqual(_request("PATCH", path, "alice", {"status": "CONNECTED"}), 403)

    def test_signal_query_must_constrain_authenticated_owner(self):
        path = f"signals/signal-{uuid.uuid4().hex}"
        self.assertEqual(
            _request("PATCH", path, "_admin", {"userId": "alice", "status": "ACTIVE"}),
            200,
        )
        self.assertEqual(
            _query("signals", "alice", {"status": "ACTIVE", "userId": "alice"}),
            200,
        )
        self.assertEqual(_query("signals", "alice", {"status": "ACTIVE"}), 403)
        self.assertEqual(
            _query("signals", "bob", {"status": "ACTIVE", "userId": "alice"}),
            403,
        )

    def test_private_signal_read_and_no_client_write(self):
        signal = f"signal-{uuid.uuid4().hex}"
        path = f"signals/{signal}"
        self.assertEqual(_request("PATCH", path, "_admin", {"userId": "alice", "status": "ACTIVE"}), 200)
        self.assertEqual(_request("GET", path, "alice"), 200)
        self.assertEqual(_request("GET", path, "bob"), 403)
        self.assertEqual(_request("PATCH", path, "alice", {"status": "CLOSED"}), 403)

    def test_analysis_request_create_requires_matching_owner(self):
        own = f"analysis_requests/request-{uuid.uuid4().hex}"
        cross = f"analysis_requests/request-{uuid.uuid4().hex}"
        valid = {
            "userId": "alice", "status": "PENDING", "symbol": "XAUUSD",
            "timeframe": "5", "execution_tf": "5",
            "trading_mode": "scalping",
        }
        self.assertEqual(_request("PATCH", own, "alice", valid), 200)
        self.assertEqual(_request("GET", own, "alice"), 200)
        self.assertEqual(_request("GET", own, "bob"), 403)
        self.assertEqual(_request("PATCH", own, "alice", {"status": "COMPLETED"}), 403)
        self.assertEqual(_request("PATCH", cross, "bob", valid), 403)

    def test_analysis_request_rejects_malformed_and_excessive_payload(self):
        valid = {
            "userId": "alice", "status": "PENDING", "symbol": "XAUUSD",
            "timeframe": "5", "execution_tf": "5",
            "trading_mode": "scalping",
        }
        invalid = (
            {**valid, "symbol": "x" * 500},
            {**valid, "timeframe": "arbitrary"},
            {**valid, "execution_tf": "15"},
            {**valid, "trading_mode": "swing"},
            {**valid, "extra": "untrusted"},
            {key: value for key, value in valid.items() if key != "symbol"},
        )
        for payload in invalid:
            with self.subTest(payload=payload):
                path = f"analysis_requests/request-{uuid.uuid4().hex}"
                self.assertEqual(_request("PATCH", path, "alice", payload), 403)

    def test_community_owner_cannot_forge_verified_trade_or_counters(self):
        base = {
            "userId": "alice", "userName": "Alice", "avatarUrl": "",
            "content": "Market note", "likes": 0, "comments": 0,
            "isVerified": False, "tradeVerified": False,
            "timestamp": datetime.now(timezone.utc) - timedelta(seconds=1),
        }
        path = f"community/post-{uuid.uuid4().hex}"
        self.assertEqual(_request("PATCH", path, "alice", base), 403)
        self.assertEqual(_request("PATCH", path, "_admin", base), 200)
        self.assertEqual(_request("GET", path, "bob"), 200)
        self.assertEqual(_request("PATCH", path, "alice", {**base, "tradeVerified": True}), 403)
        self.assertEqual(_request("PATCH", path, "alice", {**base, "likes": 10000}), 403)
        for payload in (
            {**base, "tradeVerified": True},
            {**base, "profit": 250000},
            {**base, "likes": 10000},
            {**base, "content": "x" * 2001},
        ):
            with self.subTest(payload=payload):
                forged = f"community/post-{uuid.uuid4().hex}"
                self.assertEqual(_request("PATCH", forged, "alice", payload), 403)

    def test_trade_is_owner_readable_but_backend_only_writable(self):
        path = f"users/alice/trades/trade_{uuid.uuid4().hex}"
        self.assertEqual(_request("PATCH", path, "_admin", {"status": "OPEN"}), 200)
        self.assertEqual(_request("GET", path, "alice"), 200)
        self.assertEqual(_request("GET", path, "bob"), 403)
        self.assertEqual(_request("PATCH", path, "alice", {"status": "CLOSED"}), 403)

    def test_daily_cutoff_latch_is_owner_readable_and_backend_only_writable(self):
        path = "users/alice/risk_state/daily_cutoff"
        self.assertEqual(
            _request("PATCH", path, "_admin", {"active": True, "sessionDate": "2026-09-24"}),
            200,
        )
        self.assertEqual(_request("GET", path, "alice"), 200)
        self.assertEqual(_request("GET", path, "bob"), 403)
        self.assertEqual(_request("PATCH", path, "alice", {"active": False}), 403)

    def test_backtest_trade_read_requires_parent_owner(self):
        session = f"session-{uuid.uuid4().hex}"
        session_path = f"backtest_sessions/{session}"
        trade_path = f"{session_path}/trades/trade-{uuid.uuid4().hex}"
        self.assertEqual(
            _request("PATCH", session_path, "_admin", {"userId": "alice"}),
            200,
        )
        self.assertEqual(
            _request("PATCH", trade_path, "_admin", {"status": "OPEN"}),
            200,
        )
        self.assertEqual(_request("GET", trade_path, "bob"), 403)
        self.assertEqual(_request("GET", trade_path, "alice"), 200)

    def test_backtest_trade_write_requires_parent_owner(self):
        session = f"session-{uuid.uuid4().hex}"
        session_path = f"backtest_sessions/{session}"
        trade_path = f"{session_path}/trades/trade-{uuid.uuid4().hex}"
        self.assertEqual(
            _request("PATCH", session_path, "_admin", {"userId": "alice"}),
            200,
        )
        self.assertEqual(
            _request("PATCH", trade_path, "_admin", {"status": "OPEN"}),
            200,
        )
        self.assertEqual(
            _request("PATCH", trade_path, "bob", {"status": "CLOSED"}),
            403,
        )
        self.assertEqual(
            _request("PATCH", trade_path, "alice", {"status": "CLOSED"}),
            200,
        )

    def test_backtest_owner_cannot_reassign_session(self):
        session_path = f"backtest_sessions/session-{uuid.uuid4().hex}"
        self.assertEqual(
            _request("PATCH", session_path, "_admin", {"userId": "alice"}),
            200,
        )
        self.assertEqual(
            _request("PATCH", session_path, "alice", {"userId": "bob"}),
            403,
        )

    def test_backtest_creation_requires_backend_and_preserves_allocation(self):
        path = 'backtest_sessions/quota-' + uuid.uuid4().hex
        self.assertEqual(_request('PATCH', path, 'alice', {'userId': 'alice'}), 403)
        fields = {'userId': 'alice', 'initialBalance': 1000, 'symbol': 'BTCUSD',
                  'source': 'server_enforced', 'currentBalance': 1000}
        self.assertEqual(_request('PATCH', path, '_admin', fields), 200)
        self.assertEqual(_request('PATCH', path, 'alice', {**fields, 'currentBalance': 900}), 200)
        for changes in ({'initialBalance': 999}, {'source': 'forged'}, {'symbol': 'EURUSD'}):
            self.assertEqual(_request('PATCH', path, 'alice', {**fields, **changes}), 403)

    def test_community_creation_is_backend_owned_and_delete_is_owner_bound(self):
        path = f"community/post-{uuid.uuid4().hex}"
        valid = {
            "userId": "alice", "userName": "Alice", "avatarUrl": "",
            "content": "x", "likes": 0, "comments": 0,
            "isVerified": False, "tradeVerified": False,
            "timestamp": datetime.now(timezone.utc) - timedelta(seconds=1),
        }
        self.assertEqual(
            _request("PATCH", path, "bob", valid),
            403,
        )
        self.assertEqual(
            _request("PATCH", path, "alice", valid),
            403,
        )
        self.assertEqual(_request("PATCH", path, "_admin", valid), 200)
        self.assertEqual(
            _request("PATCH", path, "bob", {**valid, "likes": 1}),
            403,
        )
        self.assertEqual(_request("DELETE", path, "bob"), 403)
        self.assertEqual(_request("DELETE", path, "alice"), 200)
        self.assertEqual(
            _request("PATCH", path, "bob", {**valid, "userId": "bob"}),
            403,
        )

    def test_community_comments_are_public_only_while_parent_exists_and_backend_owned(self):
        path = f"community/post-{uuid.uuid4().hex}"
        comment = path + "/comments/comment123"
        fields = {"userId": "alice", "content": "Public reply"}
        self.assertEqual(_request("PATCH", comment, "alice", fields), 403)
        self.assertEqual(_request("PATCH", path, "_admin", {"userId": "alice"}), 200)
        self.assertEqual(_request("PATCH", comment, "_admin", fields), 200)
        for owner in (None, "alice", "bob"):
            self.assertEqual(_request("GET", comment, owner), 200)
        for owner in ("alice", "bob"):
            self.assertEqual(_request("PATCH", comment, owner, {**fields, "content": "forged"}), 403)
            self.assertEqual(_request("DELETE", comment, owner), 403)
        self.assertEqual(_request("DELETE", path, "alice"), 200)
        self.assertEqual(_request("GET", comment), 403)

    def test_admin_data_requires_verified_admin_claim(self):
        path = "admin/stats"
        self.assertEqual(_request("PATCH", path, "_admin", {"status": "READY"}), 200)
        self.assertEqual(_request("GET", path, "auditor", admin=True), 200)
        self.assertEqual(_request("GET", path, "alice"), 403)
        settings = "AdminSettings/ai_config"
        self.assertEqual(_request("PATCH", settings, "_admin", {"prompt": "test"}), 200)
        self.assertEqual(_request("GET", settings, "auditor", admin=True), 200)
        self.assertEqual(_request("GET", settings, "alice"), 403)

    def test_non_admin_role_matrix_cannot_read_or_mutate_admin_data(self):
        stats = "admin/stats"
        settings = "AdminSettings/ai_config"
        self.assertEqual(_request("PATCH", stats, "_admin", {"status": "READY"}), 200)
        self.assertEqual(_request("PATCH", settings, "_admin", {"prompt": "test"}), 200)
        for role in (
            "standard", "verified_partner", "professional", "enterprise",
            "reserved_fifth",
        ):
            with self.subTest(role=role):
                self.assertEqual(_request("GET", stats, role, role=role), 403)
                self.assertEqual(_request("GET", settings, role, role=role), 403)
                self.assertEqual(
                    _request("PATCH", stats, role, {"status": "OFF"}, role=role),
                    403,
                )
                self.assertEqual(
                    _request("PATCH", settings, role, {"prompt": "forged"}, role=role),
                    403,
                )
        for role in ("reserved_fifth", "undefined"):
            with self.subTest(role=role, admin=True):
                self.assertEqual(
                    _request("GET", stats, role, role=role, admin=True), 403
                )
                self.assertEqual(
                    _request(
                        "PATCH", settings, role, {"prompt": "forged"},
                        role=role, admin=True,
                    ),
                    403,
                )

    def test_pending_request_create_requires_matching_owner(self):
        path = f"admin/requests/pending/request-{uuid.uuid4().hex}"
        self.assertEqual(
            _request("PATCH", path, "bob", {"userId": "alice", "status": "PENDING"}),
            403,
        )
        self.assertEqual(
            _request("PATCH", path, "alice", {"userId": "alice", "status": "PENDING"}),
            200,
        )
        self.assertEqual(
            _request("PATCH", path, "alice", {"userId": "alice", "status": "APPROVED"}),
            403,
        )
        self.assertEqual(
            _request("PATCH", path, "auditor", {"userId": "bob"}, admin=True),
            403,
        )

    def test_pending_request_read_requires_owner_or_admin(self):
        path = f"admin/requests/pending/request-{uuid.uuid4().hex}"
        self.assertEqual(
            _request(
                "PATCH",
                path,
                "_admin",
                {"userId": "alice", "status": "PENDING"},
            ),
            200,
        )
        self.assertEqual(_request("GET", path, "auditor", admin=True), 200)
        self.assertEqual(_request("GET", path, "alice"), 200)
        self.assertEqual(_request("GET", path, "bob"), 403)

    def test_chat_history_is_available_only_to_its_owner(self):
        message = f"message-{uuid.uuid4().hex}"
        path = f"chat_history/alice/trading_room/{message}"
        self.assertEqual(
            _request("PATCH", path, "alice", {"content": "hello"}),
            200,
        )
        self.assertEqual(_request("GET", path, "alice"), 200)
        self.assertEqual(_request("GET", path, "bob"), 403)

    def test_fcm_token_registration_requires_matching_owner(self):
        path = f"fcm_tokens/token-{uuid.uuid4().hex}"
        self.assertEqual(
            _request("PATCH", path, "alice", {"userId": "alice", "platform": "web"}),
            200,
        )
        self.assertEqual(_request("GET", path, "alice"), 200)
        self.assertEqual(_request("GET", path, "bob"), 403)
        self.assertEqual(
            _request("PATCH", path, "alice", {"userId": "bob", "platform": "web"}),
            403,
        )
        self.assertEqual(_request("DELETE", path, "bob"), 403)
        self.assertEqual(_request("DELETE", path, "alice"), 200)

    def test_referral_parent_and_ledger_are_owner_only(self):
        parent = "referrals/alice"
        ledger = f"{parent}/transactions/entry-{uuid.uuid4().hex}"
        self.assertEqual(_request("PATCH", parent, "_admin", {"code": "ALICE"}), 200)
        self.assertEqual(_request("PATCH", ledger, "_admin", {"status": "SETTLED"}), 200)
        for path in (parent, ledger):
            with self.subTest(path=path):
                self.assertEqual(_request("GET", path, "alice"), 200)
                self.assertEqual(_request("GET", path, "bob"), 403)
                self.assertEqual(_request("PATCH", path, "alice", {"status": "SETTLED"}), 403)
                self.assertEqual(_request("PATCH", path, "bob", {"status": "SETTLED"}), 403)

    def test_broadcasts_are_written_only_by_verified_admin(self):
        path = f"broadcasts/broadcast-{uuid.uuid4().hex}"
        self.assertEqual(_request("PATCH", path, "alice", {"message": "test"}), 403)
        self.assertEqual(
            _request("PATCH", path, "auditor", {"message": "test"}, admin=True),
            200,
        )


if __name__ == "__main__":
    unittest.main()
