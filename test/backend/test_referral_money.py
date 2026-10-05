"""Real Firestore transactions using labeled Emulator fixtures, no payment provider."""
from concurrent.futures import ThreadPoolExecutor
from datetime import datetime, timedelta, timezone
import os
import re
import secrets
import unittest
import uuid

from referral_ledger import (
    POLICY_VERSION, LedgerDenied, available, wallet_state,
    commit_receipt, commit_withdrawal, commit_withdrawal_review, commit_receipt_reversal,
)


class MoneyValidationTests(unittest.TestCase):
    def test_wallet_rejects_fabricated_source_fractional_bool_and_inconsistent_reservation(self):
        base = dict(creditsMinor=10000, reversedMinor=0, heldMinor=0, paidMinor=0,
                    currency='USD', source='admin_verified_receipts', policyVersion=POLICY_VERSION)
        self.assertEqual(available(wallet_state(base)), 10000)
        for change in ({'creditsMinor': True}, {'creditsMinor': 1.5}, {'source': 'client'},
                       {'heldMinor': 10001}, {'reversedMinor': 10001}, {'policyVersion': 'unknown'}):
            with self.assertRaises(LedgerDenied):
                wallet_state({**base, **change})


@unittest.skipUnless(re.fullmatch(r'(?:127\.0\.0\.1|localhost):\d+', os.getenv('FIRESTORE_EMULATOR_HOST', '')), 'requires loopback Firestore Emulator')
class ReferralMoneyEmulatorTests(unittest.TestCase):
    def setUp(self):
        from google.auth.credentials import AnonymousCredentials
        from google.cloud import firestore
        self.fs = firestore
        self.db = firestore.Client(project='protrading-ai-2026', credentials=AnonymousCredentials())
        self.now = datetime.now(timezone.utc)
        self.tag = uuid.uuid4().hex
        self.payer, self.f1, self.f2 = ('money-' + self.tag + '-' + name for name in ('payer', 'f1', 'f2'))
        self.codes = ('a' + self.tag[:23], 'b' + self.tag[:23])
        for uid, code, recipient in ((self.payer, self.codes[0], self.f1), (self.f1, self.codes[1], self.f2)):
            self.db.collection('users').document(uid).collection('meta').document('referral_attribution').set({'code': code, 'createdAt': self.now - timedelta(days=30)})
            self.db.collection('referral_codes').document(code).set({'userId': recipient})
        self.receipt = dict(receiptId=self.tag, payerUid=self.payer, netMinor=100000, settledAt=(self.now - timedelta(days=15)).isoformat())

    def txn(self, callback, *args):
        from google.api_core.exceptions import Aborted
        import time
        for attempt in range(4):
            try:
                return self.fs.transactional(callback)(self.db.transaction(max_attempts=10), self.db, *args)
            except (Aborted, ValueError) as error:
                if not isinstance(error, Aborted) and not isinstance(error.__cause__, Aborted):
                    raise
                if attempt == 3:
                    raise
                time.sleep(.1 * (attempt + 1))

    def wallet(self, uid):
        return self.db.collection('users').document(uid).collection('meta').document('referral_wallet').get().to_dict()

    def test_f1_f2_exact_cents_idempotent_receipt_and_refund(self):
        result = self.txn(commit_receipt, self.receipt, 'emulator-admin', self.now)
        self.assertEqual(self.txn(commit_receipt, self.receipt, 'emulator-admin', self.now)['status'], 'restored')
        self.assertEqual(available(self.wallet(self.f1)), 20000)
        self.assertEqual(available(self.wallet(self.f2)), 5000)
        with self.assertRaises(LedgerDenied):
            self.txn(commit_receipt, {**self.receipt, 'netMinor': 99999}, 'emulator-admin', self.now)
        self.txn(commit_receipt_reversal, result['receiptId'], 'emulator-admin', self.now)
        self.assertEqual(available(self.wallet(self.f1)), 0)
        self.assertEqual(self.txn(commit_receipt_reversal, result['receiptId'], 'emulator-admin', self.now)['status'], 'restored')

    def test_withdrawal_replay_approve_paid_and_unique_payment_reference(self):
        self.txn(commit_receipt, self.receipt, 'emulator-admin', self.now)
        request = self.txn(commit_withdrawal, self.f1, self.tag, 5000, self.now)
        self.assertEqual(available(self.wallet(self.f1)), 15000)
        self.assertEqual(self.txn(commit_withdrawal, self.f1, self.tag, 5000, self.now), request)
        with self.assertRaises(LedgerDenied):
            self.txn(commit_withdrawal_review, request['requestId'], 'paid', self.tag, 'emulator-admin', self.now)
        self.txn(commit_withdrawal_review, request['requestId'], 'approve', None, 'emulator-admin', self.now)
        self.txn(commit_withdrawal_review, request['requestId'], 'paid', self.tag, 'emulator-admin', self.now)
        self.assertEqual(self.wallet(self.f1)['paidMinor'], 5000)
        self.assertEqual(self.wallet(self.f1)['heldMinor'], 0)
        self.assertEqual(self.txn(commit_withdrawal_review, request['requestId'], 'paid', self.tag, 'emulator-admin', self.now), {'status': 'PAID'})
        other = self.txn(commit_withdrawal, self.f1, self.tag + '-other', 5000, self.now)
        self.txn(commit_withdrawal_review, other['requestId'], 'approve', None, 'emulator-admin', self.now)
        with self.assertRaises(LedgerDenied):
            self.txn(commit_withdrawal_review, other['requestId'], 'paid', self.tag, 'emulator-admin', self.now)

    def test_reject_releases_once_and_refund_blocks_funded_payout(self):
        receipt = self.txn(commit_receipt, self.receipt, 'emulator-admin', self.now)
        req = self.txn(commit_withdrawal, self.f1, self.tag, 10000, self.now)
        self.txn(commit_withdrawal_review, req['requestId'], 'reject', None, 'emulator-admin', self.now)
        self.txn(commit_withdrawal_review, req['requestId'], 'reject', None, 'emulator-admin', self.now)
        self.assertEqual(available(self.wallet(self.f1)), 20000)
        next_req = self.txn(commit_withdrawal, self.f1, self.tag + '-next', 10000, self.now)
        self.txn(commit_withdrawal_review, next_req['requestId'], 'approve', None, 'emulator-admin', self.now)
        self.txn(commit_receipt_reversal, receipt['receiptId'], 'emulator-admin', self.now)
        with self.assertRaises(LedgerDenied):
            self.txn(commit_withdrawal_review, next_req['requestId'], 'paid', self.tag, 'emulator-admin', self.now)
        self.assertEqual(available(self.wallet(self.f1)), -10000)

    def test_parallel_withdrawals_cannot_exceed_verified_balance(self):
        self.txn(commit_receipt, self.receipt, 'emulator-admin', self.now)
        def reserve(index):
            try:
                return self.txn(commit_withdrawal, self.f1, self.tag + '-' + str(index), 2000, self.now)['status']
            except LedgerDenied:
                return 'denied'
        with ThreadPoolExecutor(max_workers=8) as pool:
            result = list(pool.map(reserve, range(30)))
        self.assertEqual(result.count('PENDING'), 1)
        self.assertEqual(result.count('denied'), 29)
        self.assertEqual(available(self.wallet(self.f1)), 18000)

    def test_young_or_pre_attribution_receipt_and_cycle_are_rejected(self):
        for days in (0, 13, 40):
            with self.assertRaises(LedgerDenied):
                self.txn(commit_receipt, {**self.receipt, 'settledAt': (self.now - timedelta(days=days)).isoformat()}, 'emulator-admin', self.now)
        self.db.collection('referral_codes').document(self.codes[1]).set({'userId': self.payer})
        with self.assertRaises(LedgerDenied):
            self.txn(commit_receipt, self.receipt, 'emulator-admin', self.now)

    def tearDown(self):
        for uid in (self.payer, self.f1, self.f2):
            user = self.db.collection('users').document(uid)
            for collection in user.collections():
                for doc in collection.stream(): doc.reference.delete()
            user.delete()
        for code in self.codes: self.db.collection('referral_codes').document(code).delete()
        # Remove only fixture-owned admin and receipt records.
        for collection in (self.db.collection('referral_receipts'), self.db.collection('referral_payout_receipts'), self.db.collection('admin').document('requests').collection('pending')):
            for doc in collection.stream():
                data = doc.to_dict()
                if data.get('payerUid') == self.payer or data.get('userId') == self.f1: doc.reference.delete()
        self.db.close()


@unittest.skipUnless(os.getenv('PROTRADING_QA_API_BASE_URL') == 'http://127.0.0.1:8088' and re.fullmatch(r'(?:127\.0\.0\.1|localhost):\d+', os.getenv('FIREBASE_AUTH_EMULATOR_HOST', '')), 'requires local Auth/Firestore/FastAPI QA')
class ReferralMoneyApiEmulatorTests(ReferralMoneyEmulatorTests):
    # Inherited transaction cases also run with real Auth identities.
    def setUp(self):
        super().setUp()
        import firebase_admin
        from firebase_admin import auth
        import httpx
        self.auth = auth
        self.app = firebase_admin.initialize_app(options={'projectId': 'protrading-ai-2026'}, name='money-' + self.tag)
        self.admin = 'money-admin-' + self.tag
        self.tokens = {}
        for uid in (self.payer, self.f1, self.f2, self.admin):
            password = secrets.token_urlsafe(18)
            email = uid + '@example.test'
            auth.create_user(uid=uid, email=email, password=password, app=self.app)
            auth.set_custom_user_claims(uid, {'role': 'standard', **({'admin': True} if uid == self.admin else {})}, app=self.app)
            response = httpx.post('http://' + os.environ['FIREBASE_AUTH_EMULATOR_HOST'] + '/identitytoolkit.googleapis.com/v1/accounts:signInWithPassword?key=emulator-only', json={'email': email, 'password': password, 'returnSecureToken': True}, timeout=10)
            self.assertEqual(response.status_code, 200)
            self.tokens[uid] = response.json()['idToken']

    def api(self, path, uid, body):
        import httpx
        return httpx.post('http://127.0.0.1:8088' + path, headers={'Authorization': 'Bearer ' + self.tokens[uid]} if uid else {}, json=body, timeout=25)

    def test_actual_api_permissions_strict_amounts_and_review_lifecycle(self):
        receipts = '/api/admin/referral/receipts'
        withdrawals = '/api/referral/withdrawals'
        review = '/api/admin/referral/withdrawals/review'
        self.assertEqual(self.api(receipts, None, self.receipt).status_code, 401)
        self.assertEqual(self.api(receipts, self.f1, self.receipt).status_code, 403)
        credited = self.api(receipts, self.admin, self.receipt)
        self.assertEqual(credited.status_code, 200, credited.text)
        self.assertEqual(self.api(receipts, self.admin, self.receipt).json()['status'], 'restored')
        intent = {'requestId': self.tag, 'amountMinor': 5000}
        for change in ({'amountMinor': 20.5}, {'amountMinor': True}, {'userId': self.f2}, {'role': 'enterprise'}):
            self.assertEqual(self.api(withdrawals, self.f1, {**intent, **change}).status_code, 422)
        result = self.api(withdrawals, self.f1, intent)
        self.assertEqual(result.status_code, 200, result.text)
        self.assertEqual(self.api(withdrawals, self.f1, intent).json(), result.json())
        request_id = result.json()['requestId']
        action = {'requestId': request_id, 'action': 'approve'}
        self.assertEqual(self.api(review, self.f1, action).status_code, 403)
        self.assertEqual(self.api(review, self.admin, action).json()['status'], 'APPROVED')
        paid = {**action, 'action': 'paid', 'paymentReference': self.tag}
        self.assertEqual(self.api(review, self.admin, paid).json()['status'], 'PAID')
        self.assertEqual(self.api(review, self.admin, paid).json()['status'], 'PAID')
        self.assertEqual(self.wallet(self.f1)['paidMinor'], 5000)
        self.assertEqual(self.wallet(self.f2)['paidMinor'], 0)
        self.assertEqual(self.api('/api/admin/referral/reversals', self.admin, {'receiptId': credited.json()['receiptId']}).status_code, 200)

    def test_fresh_role_and_disabled_account_override_stale_token(self):
        for claims in ({}, {'role': 'reserved_fifth'}, {'role': 'unknown'}, {'role': 'standard', 'admin': 'true'}):
            self.auth.set_custom_user_claims(self.admin, claims, app=self.app)
            self.assertEqual(self.api('/api/admin/referral/receipts', self.admin, self.receipt).status_code, 403)
        self.auth.set_custom_user_claims(self.admin, {'role': 'standard', 'admin': True}, app=self.app)
        self.auth.update_user(self.admin, disabled=True, app=self.app)
        self.assertEqual(self.api('/api/admin/referral/receipts', self.admin, self.receipt).status_code, 403)

    def test_ledger_and_withdrawal_rules_block_forgery_and_cross_owner(self):
        from test.backend.test_v21_firestore_rules import _request
        self.txn(commit_receipt, self.receipt, self.admin, self.now)
        request = self.txn(commit_withdrawal, self.f1, self.tag, 5000, self.now)
        ledger = next(self.db.collection('users').document(self.f1).collection('referral_ledger').stream())
        paths = (ledger.reference.path, 'users/' + self.f1 + '/meta/referral_wallet',
                 'users/' + self.f1 + '/referral_withdrawals/' + request['requestId'])
        for path in paths:
            self.assertEqual(_request('GET', path, self.f1), 200)
            self.assertEqual(_request('GET', path, self.f2), 403)
            for uid, is_admin in ((self.f1, False), (self.admin, True)):
                self.assertEqual(_request('PATCH', path, uid, {'amountMinor': 999999}, admin=is_admin), 403)
                self.assertEqual(_request('DELETE', path, uid, admin=is_admin), 403)
        path = 'admin/requests/pending/' + request['requestId']
        self.assertEqual(_request('PATCH', path, self.admin, {'status': 'PAID'}, admin=True), 403)
        forged_path = 'admin/requests/pending/' + self.tag + '-forged'
        forged = {'userId': self.f1, 'status': 'PENDING', 'type': 'REFERRAL_WITHDRAWAL', 'amountMinor': 5000}
        self.assertEqual(_request('PATCH', forged_path, self.f1, forged), 403)
        ordinary_ref = self.db.document('admin/requests/pending/' + self.tag + '-ordinary')
        ordinary_ref.set({'userId': self.f1, 'status': 'PENDING', 'type': 'OTHER'})
        self.assertEqual(_request('PATCH', ordinary_ref.path, self.admin,
            {'userId': self.f1, 'status': 'APPROVED', 'type': 'OTHER'}, admin=True), 200)
        self.assertEqual(_request('PATCH', ordinary_ref.path, self.admin, forged, admin=True), 403)
        self.assertEqual(_request('GET', 'referral_receipts/' + self.tag, self.f1), 403)

    def tearDown(self):
        import firebase_admin
        for uid in (self.payer, self.f1, self.f2, self.admin):
            self.auth.delete_user(uid, app=self.app)
        firebase_admin.delete_app(self.app)
        super().tearDown()
