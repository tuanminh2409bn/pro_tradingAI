"""Public ranking must never expose legacy/private fields through Firestore."""
from datetime import datetime, timezone, timedelta
import os
import re
import unittest
import uuid
from community_api import verified_leaderboard_entry


class LeaderboardValidationTests(unittest.TestCase):
    def setUp(self):
        self.now = datetime.now(timezone.utc)
        self.public_id = 'a' * 32
        self.valid = dict(schemaVersion=1, source='broker_verified', isServerVerified=True,
            displayName='Public alias', growthPercent=1.25, unitVolume=2.0, asOf=self.now)

    def test_returns_only_public_fields_without_broker_identity_or_money(self):
        result = verified_leaderboard_entry(self.public_id, self.valid, self.now)
        self.assertEqual(set(result), set(self.valid) | {'publicId'})
        self.assertEqual(result['publicId'], self.public_id)
        self.assertEqual(result['asOf'], self.now.isoformat())

    def test_rejects_extra_private_fields_stale_unverified_and_invalid_metrics(self):
        for change in ({'email':'private@example.test'}, {'balance':10000}, {'source':'client'},
            {'isServerVerified':False}, {'schemaVersion':True}, {'growthPercent':float('nan')},
            {'unitVolume':-1}, {'growthPercent':True}, {'unitVolume':float('inf')},
            {'asOf':self.now-timedelta(days=3)}, {'asOf':self.now+timedelta(seconds=1)}):
            self.assertIsNone(verified_leaderboard_entry(self.public_id, {**self.valid, **change}, self.now))
        self.assertIsNone(verified_leaderboard_entry(None, self.valid, self.now))


@unittest.skipUnless(re.fullmatch(r'(?:127\.0\.0\.1|localhost):\d+', os.getenv('FIRESTORE_EMULATOR_HOST', '')), 'requires loopback Firestore Emulator')
class LeaderboardRulesTests(unittest.TestCase):
    def test_source_documents_cannot_be_read_or_written_directly_even_by_admin_clients(self):
        from google.auth.credentials import AnonymousCredentials
        from google.cloud import firestore
        from test.backend.test_v21_firestore_rules import _request, _query
        client = firestore.Client(project='protrading-ai-2026', credentials=AnonymousCredentials())
        tag = uuid.uuid4().hex
        public = client.collection('leaderboard').document(tag)
        unsafe = client.collection('leaderboard').document(tag + 'bad')
        valid = dict(schemaVersion=1, source='broker_verified', isServerVerified=True,
            displayName='Verified alias', growthPercent=1.25, unitVolume=2.0,
            asOf=datetime.now(timezone.utc))
        try:
            public.set(valid)
            self.assertEqual(_request('GET', public.path), 403)
            self.assertEqual(_query('leaderboard', 'rank-reader', {'source':'broker_verified', 'isServerVerified':True}), 403)
            unsafe.set({'email':'private@example.test', 'balance':10000, 'performance':10.0})
            self.assertEqual(_request('GET', unsafe.path), 403)
            unsafe.set({**valid, 'email':'private@example.test', 'accountNumber':'fixture-account'})
            self.assertEqual(_request('GET', unsafe.path), 403)
            self.assertEqual(_query('leaderboard', 'rank-reader', {'source':'broker_verified', 'isServerVerified':True}), 403)
            self.assertEqual(_request('PATCH', public.path, 'rank-reader', valid), 403)
            self.assertEqual(_request('PATCH', public.path, 'rank-admin', valid, admin=True), 403)
            self.assertEqual(_request('DELETE', public.path, 'rank-admin', admin=True), 403)
        finally:
            # Only the two synthetic loopback fixtures created by this test.
            public.delete()
            unsafe.delete()


@unittest.skipUnless(os.getenv('PROTRADING_QA_API_BASE_URL') == 'http://127.0.0.1:8088' and re.fullmatch(r'(?:127\.0\.0\.1|localhost):\d+', os.getenv('FIREBASE_AUTH_EMULATOR_HOST', '')), 'requires local Auth/Firestore/FastAPI QA')
class LeaderboardApiTests(unittest.TestCase):
    def test_authenticated_api_returns_verified_alias_and_never_legacy_pii(self):
        import firebase_admin
        from firebase_admin import auth
        from google.auth.credentials import AnonymousCredentials
        from google.cloud import firestore
        import httpx
        import secrets
        tag = uuid.uuid4().hex
        uid = 'ranking-qa-' + tag
        app = firebase_admin.initialize_app(options={'projectId':'protrading-ai-2026'}, name=uid)
        db = firestore.Client(project='protrading-ai-2026', credentials=AnonymousCredentials())
        refs = [db.collection('leaderboard').document(tag + suffix) for suffix in ('', 'a', 'b')]
        try:
            password = secrets.token_urlsafe(18)
            email = uid + '@example.test'
            auth.create_user(uid=uid, email=email, password=password, app=app)
            auth.set_custom_user_claims(uid, {'role':'standard'}, app=app)
            signed = httpx.post('http://' + os.environ['FIREBASE_AUTH_EMULATOR_HOST'] + '/identitytoolkit.googleapis.com/v1/accounts:signInWithPassword?key=emulator-only', json={'email':email,'password':password,'returnSecureToken':True}, timeout=10)
            self.assertEqual(signed.status_code, 200)
            headers = {'Authorization':'Bearer ' + signed.json()['idToken']}
            # The QA client and API can run on different hosts. Keep a fresh
            # fixture away from the boundary; future timestamps remain denied.
            now = datetime.now(timezone.utc) - timedelta(minutes=1)
            valid = dict(schemaVersion=1, source='broker_verified', isServerVerified=True, displayName='Emulator QA alias', growthPercent=1.25, unitVolume=2.0, asOf=now)
            refs[0].set(valid)
            refs[1].set({**valid, 'email':'private-marker@example.test', 'accountNumber':'private-marker-account', 'balance':10000})
            refs[2].set({**valid, 'asOf':now-timedelta(days=3)})
            url = 'http://127.0.0.1:8088/api/community/leaderboard'
            self.assertEqual(httpx.get(url, timeout=10).status_code, 401)
            response = httpx.get(url, headers=headers, timeout=25)
            self.assertEqual(response.status_code, 200, response.text)
            self.assertEqual([row['publicId'] for row in response.json()['entries']], [tag])
            self.assertEqual(set(response.json()['entries'][0]), set(valid) | {'publicId'})
            self.assertNotIn('private-marker', response.text)
            self.assertNotIn('accountNumber', response.text)
            auth.set_custom_user_claims(uid, {'role':'unknown'}, app=app)
            self.assertEqual(httpx.get(url, headers=headers, timeout=25).status_code, 403)
            auth.set_custom_user_claims(uid, {'role':'standard'}, app=app)
            auth.update_user(uid, disabled=True, app=app)
            self.assertEqual(httpx.get(url, headers=headers, timeout=25).status_code, 403)
        finally:
            for ref in refs:
                ref.delete()
            auth.delete_user(uid, app=app)
            firebase_admin.delete_app(app)
