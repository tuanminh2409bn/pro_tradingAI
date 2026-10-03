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
