"""Real transaction contention and idempotency, loopback Emulator only."""
import concurrent.futures
import datetime as dt
import os
import re
import unittest
import uuid

from quota_store import FirestoreQuotaStore


@unittest.skipUnless(re.fullmatch(r'(?:127\.0\.0\.1|localhost):[0-9]+',
                                os.environ.get('FIRESTORE_EMULATOR_HOST', '')),
                     'requires loopback Firestore Emulator')
class QuotaStoreEmulatorTests(unittest.TestCase):
    def test_backtest_sessions_and_counters_commit_together_under_contention(self):
        from google.auth.credentials import AnonymousCredentials
        from google.cloud import firestore
        db = firestore.Client(project='protrading-ai-2026', credentials=AnonymousCredentials())
        uid = 'backtest-quota-' + uuid.uuid4().hex
        start = dt.datetime(2026, 9, 28, tzinfo=dt.timezone.utc)
        reset = start + dt.timedelta(days=7)
        meta = db.collection('users').document(uid).collection('meta')
        sessions = [db.collection('backtest_sessions').document(uid + '-' + str(i)) for i in range(80)]
        def allocate(i, balance=1000, window=start):
            return FirestoreQuotaStore(db, operation_id='backtest:' + str(i), session_ref=sessions[i],
                session_data={'userId': uid, 'symbol': 'BTCUSD', 'initialBalance': balance,
                              'createdAt': dt.datetime.now(dt.timezone.utc)}).consume_if_below(
                subject_id=uid, counter_key='standard:backtest:weekly', window_start=window,
                reset_at=window + dt.timedelta(days=7), limit=2)
        try:
            with concurrent.futures.ThreadPoolExecutor(max_workers=16) as pool:
                results = list(pool.map(allocate, range(80)))
            self.assertEqual(sorted(value for value in results if value is not None), [1, 2])
            self.assertEqual(sum(session.get().exists for session in sessions), 2)
            self.assertEqual([allocate(i) for i in range(80)], results)
            accepted = next(i for i, value in enumerate(results) if value is not None)
            with self.assertRaises(ValueError):
                allocate(accepted, balance=999)
            summary = meta.document('quota').get().to_dict()
            self.assertEqual(summary['backtestUsed'], 2)
            self.assertEqual(summary['backtestResetAt'], reset)
            self.assertNotIn('apiUsed', summary)
            rejected = next(i for i, value in enumerate(results) if value is None)
            with self.assertRaises(ValueError):
                allocate(rejected, window=reset)
            # New operation in the next window resets the counter, not an old marker.
            extra = db.collection('backtest_sessions').document(uid + '-next')
            self.assertEqual(FirestoreQuotaStore(db, operation_id='backtest:next', session_ref=extra,
                session_data={'userId': uid, 'symbol': 'BTCUSD', 'initialBalance': 1000}).consume_if_below(
                subject_id=uid, counter_key='standard:backtest:weekly', window_start=reset,
                reset_at=reset + dt.timedelta(days=7), limit=2), 1)
        finally:
            for session in sessions:
                session.delete()
            db.collection('backtest_sessions').document(uid + '-next').delete()
            for document in meta.stream():
                document.reference.delete()
            db.close()

    def test_eighty_requests_allocate_fifty_once_and_reset(self):
        from google.auth.credentials import AnonymousCredentials
        from google.cloud import firestore

        db = firestore.Client(project='protrading-ai-2026', credentials=AnonymousCredentials())
        uid = 'quota-emulator-' + uuid.uuid4().hex
        window = dt.datetime(2026, 10, 3, tzinfo=dt.timezone.utc)
        reset = window + dt.timedelta(days=1)
        meta = db.collection('users').document(uid).collection('meta')
        def consume(operation, start=window, end=reset):
            return FirestoreQuotaStore(db, operation_id=operation).consume_if_below(
                subject_id=uid, counter_key='analysis:day', window_start=start,
                reset_at=end, limit=50)
        try:
            with concurrent.futures.ThreadPoolExecutor(max_workers=80) as pool:
                results = list(pool.map(lambda i: consume('request-' + str(i)), range(80)))
            accepted = [result for result in results if result is not None]
            self.assertEqual(sorted(accepted), list(range(1, 51)))
            self.assertEqual(results.count(None), 30)
            summary = meta.document('quota').get().to_dict()
            self.assertEqual(summary['apiUsed'], 50)
            self.assertEqual(summary['source'], 'server_enforced')
            with concurrent.futures.ThreadPoolExecutor(max_workers=8) as pool:
                repeated = list(pool.map(lambda i: consume('request-' + str(i)), range(80)))
            self.assertEqual(repeated, results, 'Retries must not consume additional allowance')
            self.assertEqual(consume('next-day', reset, reset + dt.timedelta(days=1)), 1)
            self.assertEqual(meta.document('quota').get().to_dict()['apiUsed'], 1)
        finally:
            for document in meta.stream():
                document.reference.delete()
            db.close()


if __name__ == '__main__':
    unittest.main()
