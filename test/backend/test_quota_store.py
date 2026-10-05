import threading
import unittest
from concurrent.futures import ThreadPoolExecutor
from datetime import datetime, timezone

from quota_store import FirestoreQuotaStore
from entitlements import VerifiedQuotaIdentity


class StoreDatabase:
    def __init__(self):
        self.values = {}
        self.lock = threading.Lock()
    def collection(self, path): return Reference(self, path)
    def transaction(self, **options): return self
    def set(self, reference, value, **kwargs):
        if kwargs.get('merge'):
            self.values.setdefault(reference.path, {}).update(value)
        else:
            self.values[reference.path] = dict(value)
    def transactional(self, function):
        def commit(*args, **kwargs):
            with self.lock: return function(*args, **kwargs)
        return commit


class Reference:
    def __init__(self, db, path): self.db, self.path = db, path
    def document(self, path): return Reference(self.db, self.path + '/' + path)
    def collection(self, path): return self.document(path)
    def get(self, transaction):
        class Snapshot:
            exists = self.path in self.db.values
            def to_dict(inner): return self.db.values.get(self.path)
        return Snapshot()


class QuotaStoreTests(unittest.TestCase):
    def test_new_account_summary_is_authoritative_without_consuming_allowance(self):
        db = StoreDatabase()
        store = FirestoreQuotaStore(db, operation_id='onboarding', transactional=db.transactional)
        identity = VerifiedQuotaIdentity.from_decoded_token({'uid': 'qa', 'role': 'standard'})
        now = datetime(2026, 10, 5, 12, tzinfo=timezone.utc)
        store.refresh_summary(identity=identity, now=now, timezone_name='UTC')
        self.assertEqual(set(db.values), {'users/qa/meta/quota'})
        self.assertEqual(db.values['users/qa/meta/quota'], {
            'source': 'server_enforced', 'apiUsed': 0, 'apiLimit': 2,
            'backtestUsed': 0, 'backtestLimit': 2,
            'resetAt': datetime(2026, 10, 12, tzinfo=timezone.utc),
            'backtestResetAt': datetime(2026, 10, 12, tzinfo=timezone.utc),
        })

    def test_refresh_preserves_usage_retries_and_counter_window(self):
        db = StoreDatabase()
        store = FirestoreQuotaStore(db, operation_id='onboarding', transactional=db.transactional)
        identity = VerifiedQuotaIdentity.from_decoded_token({'uid': 'qa', 'role': 'professional'})
        now = datetime(2026, 10, 3, 12, tzinfo=timezone.utc)
        self.assertEqual(self.consume(db, 'request-one'), 1)
        before = {key: dict(value) for key, value in db.values.items() if key != 'users/qa/meta/quota'}
        for _ in range(3):
            store.refresh_summary(identity=identity, now=now, timezone_name='UTC')
        self.assertEqual(db.values['users/qa/meta/quota']['apiUsed'], 1)
        self.assertEqual({key: value for key, value in db.values.items() if key != 'users/qa/meta/quota'}, before)
        self.assertEqual(self.consume(db, 'request-one'), 1)
        store.refresh_summary(identity=identity, now=datetime(2026, 10, 4, tzinfo=timezone.utc), timezone_name='UTC')
        self.assertEqual(db.values['users/qa/meta/quota']['apiUsed'], 0)
        self.assertEqual({key: value for key, value in db.values.items() if key != 'users/qa/meta/quota'}, before)

    def consume(self, db, operation, start=None):
        return FirestoreQuotaStore(db, operation_id=operation, transactional=db.transactional).consume_if_below(
            subject_id='qa', counter_key='professional:analysis:daily',
            window_start=start or datetime(2026, 10, 3, tzinfo=timezone.utc),
            reset_at=datetime(2026, 10, 4, tzinfo=timezone.utc), limit=50)

    def test_eighty_requests_never_exceed_fifty_or_use_client_writable_paths(self):
        db = StoreDatabase()
        with ThreadPoolExecutor(max_workers=12) as pool:
            values = list(pool.map(lambda i: self.consume(db, 'request-' + str(i)), range(80)))
        self.assertEqual(sorted(x for x in values if x is not None), list(range(1, 51)))
        self.assertEqual(values.count(None), 30)
        self.assertTrue(all(path.startswith('users/qa/meta/quota') for path in db.values))
        self.assertEqual(db.values['users/qa/meta/quota']['apiUsed'], 50)
        self.assertEqual(db.values['users/qa/meta/quota']['source'], 'server_enforced')

    def test_delivery_retry_charges_once_and_new_window_resets(self):
        db = StoreDatabase()
        self.assertEqual(self.consume(db, 'same-request'), 1)
        self.assertEqual(self.consume(db, 'same-request'), 1)
        self.assertEqual(self.consume(db, 'new-request'), 2)
        self.assertEqual(self.consume(db, 'next-day', datetime(2026, 10, 4, tzinfo=timezone.utc)), 1)
        with self.assertRaises(ValueError):
            self.consume(db, 'same-request', datetime(2026, 10, 5, tzinfo=timezone.utc))
