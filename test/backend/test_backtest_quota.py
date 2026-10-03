"""Backtest allocation is atomic with its quota; no external providers."""
import unittest
from concurrent.futures import ThreadPoolExecutor
from datetime import datetime, timedelta, timezone

from entitlements import AccountRole, Capability, QuotaEnforcer, VerifiedQuotaIdentity
from quota_store import FirestoreQuotaStore
from test.backend.test_quota_store import StoreDatabase


class BacktestQuotaTests(unittest.TestCase):
    def test_role_limits_apply_to_backtest_independently_of_analysis(self):
        for role, limit, period in ((AccountRole.STANDARD, 2, 'weekly'),
                                    (AccountRole.PROFESSIONAL, 50, 'daily'),
                                    (AccountRole.ENTERPRISE, 300, 'daily')):
            db = StoreDatabase()
            identity = VerifiedQuotaIdentity(uid='alice', role=role)
            now = datetime(2026, 10, 3, tzinfo=timezone.utc)
            decisions = []
            for capability in (Capability.ANALYSIS, Capability.BACKTEST):
                decisions.append(QuotaEnforcer(
                    store=FirestoreQuotaStore(db, operation_id=capability.value,
                                              transactional=db.transactional),
                    timezone_name='UTC').consume(identity=identity, capability=capability, now=now))
            for decision in decisions:
                self.assertTrue(decision.allowed)
                self.assertEqual((decision.limit, decision.period, decision.used), (limit, period, 1))
            self.assertEqual(db.values['users/alice/meta/quota']['apiUsed'], 1)
            self.assertEqual(db.values['users/alice/meta/quota']['backtestUsed'], 1)

    def test_concurrent_session_allocation_and_delivery_retry_charge_once(self):
        db = StoreDatabase()
        start = datetime(2026, 9, 28, tzinfo=timezone.utc)
        reset = start + timedelta(days=7)

        def allocate(operation, balance=1000):
            return FirestoreQuotaStore(db, operation_id='backtest:' + operation,
                transactional=db.transactional,
                session_ref=db.collection('backtest_sessions').document(operation),
                session_data={'userId': 'alice', 'symbol': 'BTCUSD', 'initialBalance': balance}
            ).consume_if_below(subject_id='alice', counter_key='standard:backtest:weekly',
                window_start=start, reset_at=reset, limit=2)

        with ThreadPoolExecutor(max_workers=8) as pool:
            results = list(pool.map(lambda i: allocate(str(i)), range(80)))
        self.assertEqual(sorted(x for x in results if x is not None), [1, 2])
        self.assertEqual(len([path for path in db.values if path.startswith('backtest_sessions/')]), 2)
        with ThreadPoolExecutor(max_workers=8) as pool:
            retried = list(pool.map(lambda i: allocate(str(i)), range(80)))
        self.assertEqual(retried, results)
        accepted = str(next(i for i, value in enumerate(results) if value is not None))
        with self.assertRaises(ValueError):
            allocate(accepted, balance=999)
        self.assertEqual(db.values['users/alice/meta/quota']['backtestUsed'], 2)
        self.assertNotIn('apiUsed', db.values['users/alice/meta/quota'])


if __name__ == '__main__':
    unittest.main()
