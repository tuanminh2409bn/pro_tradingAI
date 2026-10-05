"""Fresh Auth users run through the actual localhost FastAPI onboarding endpoint."""
from concurrent.futures import ThreadPoolExecutor
import os
import re
import secrets
import unittest
import uuid


LOCAL_HOST = r'(?:127\.0\.0\.1|localhost):\d+'


@unittest.skipUnless(all(re.fullmatch(LOCAL_HOST, os.getenv(k, '')) for k in ('FIREBASE_AUTH_EMULATOR_HOST', 'FIRESTORE_EMULATOR_HOST')) and os.getenv('PROTRADING_QA_API_BASE_URL') == 'http://127.0.0.1:8088', 'requires local Auth/Firestore/FastAPI QA')
class StandardOnboardingEmulatorTests(unittest.TestCase):
    def test_fresh_signup_refresh_claims_concurrency_and_role_preservation(self):
        import firebase_admin
        from firebase_admin import auth
        from google.cloud import firestore
        from google.auth.credentials import AnonymousCredentials
        from datetime import datetime, timezone
        from entitlements import Capability, QuotaEnforcer, VerifiedQuotaIdentity
        from quota_store import FirestoreQuotaStore
        import httpx
        app = firebase_admin.initialize_app(options={'projectId': 'protrading-ai-2026'}, name='onboard-' + uuid.uuid4().hex)
        db = firestore.Client(project='protrading-ai-2026', credentials=AnonymousCredentials())
        created = []
        try:
            for claims, expected in (({}, 200), ({'role': 'professional', 'tenant_id': 'fixture'}, 200),
                                     ({'role': 'verified_partner'}, 200), ({'role': 'enterprise'}, 200),
                                     ({'role': 'reserved_fifth', 'admin': True}, 403), ({'admin': True}, 403), ({'role': 'unknown'}, 403)):
                uid = 'onboard-' + uuid.uuid4().hex
                password = secrets.token_urlsafe(18)
                email = uid + '@example.test'
                auth.create_user(uid=uid, email=email, password=password, app=app)
                created.append(uid)
                auth.set_custom_user_claims(uid, claims, app=app)
                url = 'http://' + os.environ['FIREBASE_AUTH_EMULATOR_HOST'] + '/identitytoolkit.googleapis.com/v1/accounts:signInWithPassword?key=emulator-only'
                def signin():
                    response = httpx.post(url, json={'email': email, 'password': password, 'returnSecureToken': True}, timeout=10)
                    self.assertEqual(response.status_code, 200)
                    return response.json()['idToken']
                token = signin()
                def onboard(_):
                    # The body attempts escalation/another owner; endpoint takes UID only from the token.
                    return httpx.post('http://127.0.0.1:8088/api/auth/onboarding', headers={'Authorization': 'Bearer ' + token}, json={'role': 'enterprise', 'userId': 'other'}, timeout=20).status_code
                with self.subTest(claims=claims):
                    if not claims:
                        with ThreadPoolExecutor(max_workers=8) as pool:
                            self.assertEqual(list(pool.map(onboard, range(24))), [200] * 24)
                        self.assertEqual(auth.get_user(uid, app=app).custom_claims, {'role': 'standard'})
                        self.assertEqual(auth.verify_id_token(signin(), app=app)['role'], 'standard')
                        meta = db.collection('users').document(uid).collection('meta')
                        summary = meta.document('quota').get().to_dict()
                        self.assertEqual((summary['apiUsed'], summary['apiLimit'], summary['backtestUsed'], summary['backtestLimit']), (0, 2, 0, 2))
                        self.assertEqual(summary['source'], 'server_enforced')
                        store = FirestoreQuotaStore(db, operation_id='onboarding-consume-' + uid)
                        window = QuotaEnforcer(store=store, timezone_name='UTC').window_for(
                            identity=VerifiedQuotaIdentity.from_decoded_token({'uid': uid, 'role': 'standard'}),
                            capability=Capability.ANALYSIS, now=datetime.now(timezone.utc))
                        self.assertEqual(store.consume_if_below(subject_id=uid, counter_key=window.counter_key,
                            window_start=window.window_start, reset_at=window.reset_at, limit=window.limit), 1)
                        self.assertEqual(onboard(0), 200)
                        self.assertEqual(meta.document('quota').get().to_dict()['apiUsed'], 1)
                    else:
                        self.assertEqual(onboard(0), expected)
                        self.assertEqual(auth.get_user(uid, app=app).custom_claims, claims)
            self.assertEqual(httpx.post('http://127.0.0.1:8088/api/auth/onboarding', timeout=5).status_code, 401)
        finally:
            for uid in created:
                for document in db.collection('users').document(uid).collection('meta').stream():
                    document.reference.delete()
                auth.delete_user(uid, app=app)
            db.close()
            firebase_admin.delete_app(app)
