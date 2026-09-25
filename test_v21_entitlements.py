import threading
import unittest
from concurrent.futures import ThreadPoolExecutor
from datetime import datetime, timezone

from entitlements import (
    AccountRole,
    Capability,
    EntitlementDenied,
    QuotaEnforcer,
    VerifiedQuotaIdentity,
)


class AtomicMemoryStore:
    """Test-only implementation of the production atomic counter boundary."""

    def __init__(self):
        self._lock = threading.Lock()
        self._counts = {}

    def consume_if_below(
        self,
        *,
        subject_id,
        counter_key,
        window_start,
        reset_at,
        limit,
    ):
        del reset_at
        key = (subject_id, counter_key, window_start)
        with self._lock:
            used = self._counts.get(key, 0)
            if used >= limit:
                return None
            used += 1
            self._counts[key] = used
            return used


class EntitlementContractTests(unittest.TestCase):
    def test_role_must_come_from_verified_claim_allowlist(self):
        identity = VerifiedQuotaIdentity.from_decoded_token(
            {"uid": "user-1", "role": "professional"}
        )
        self.assertEqual(identity.uid, "user-1")
        self.assertEqual(identity.role, AccountRole.PROFESSIONAL)

        with self.assertRaises(EntitlementDenied):
            VerifiedQuotaIdentity.from_decoded_token(
                {"uid": "user-1", "role": "super_pro_from_body"}
            )
        with self.assertRaises(EntitlementDenied):
            VerifiedQuotaIdentity.from_decoded_token({"role": "enterprise"})

    def test_exact_numeric_role_limits_and_pending_roles_fail_closed(self):
        now = datetime(2026, 9, 12, 10, tzinfo=timezone.utc)
        store = AtomicMemoryStore()
        enforcer = QuotaEnforcer(store=store, timezone_name="UTC")

        cases = (
            (AccountRole.STANDARD, 2, "weekly"),
            (AccountRole.PROFESSIONAL, 50, "daily"),
            (AccountRole.ENTERPRISE, 300, "daily"),
        )
        for role, limit, period in cases:
            decision = enforcer.consume(
                identity=VerifiedQuotaIdentity(
                    uid=f"user-{role.value}", role=role
                ),
                capability=Capability.ANALYSIS,
                now=now,
            )
            self.assertTrue(decision.allowed)
            self.assertEqual(decision.limit, limit)
            self.assertEqual(decision.period, period)
            self.assertEqual(decision.remaining, limit - 1)

        partner = VerifiedQuotaIdentity(
            uid="partner-1", role=AccountRole.VERIFIED_PARTNER
        )
        realtime = enforcer.consume(
            identity=partner,
            capability=Capability.REALTIME_SIGNAL,
            now=now,
        )
        self.assertTrue(realtime.allowed)
        self.assertIsNone(realtime.limit)
        self.assertEqual(
            realtime.reason, "unlimited_verified_partner_realtime"
        )

        partner_analysis = enforcer.consume(
            identity=partner,
            capability=Capability.ANALYSIS,
            now=now,
        )
        self.assertFalse(partner_analysis.allowed)
        self.assertEqual(partner_analysis.reason, "policy_pending")

        fifth = enforcer.consume(
            identity=VerifiedQuotaIdentity(
                uid="fifth-1", role=AccountRole.RESERVED_FIFTH
            ),
            capability=Capability.ANALYSIS,
            now=now,
        )
        self.assertFalse(fifth.allowed)
        self.assertEqual(fifth.reason, "policy_pending")

    def test_daily_and_weekly_windows_reset_at_explicit_utc_boundaries(self):
        store = AtomicMemoryStore()
        enforcer = QuotaEnforcer(store=store, timezone_name="UTC")
        standard = VerifiedQuotaIdentity(
            uid="standard-1", role=AccountRole.STANDARD
        )
        professional = VerifiedQuotaIdentity(
            uid="professional-1", role=AccountRole.PROFESSIONAL
        )

        saturday = datetime(2026, 9, 12, 23, 59, tzinfo=timezone.utc)
        weekly = enforcer.consume(
            identity=standard,
            capability=Capability.ANALYSIS,
            now=saturday,
        )
        self.assertEqual(
            weekly.reset_at,
            datetime(2026, 9, 14, 0, 0, tzinfo=timezone.utc),
        )

        before_midnight = enforcer.consume(
            identity=professional,
            capability=Capability.ANALYSIS,
            now=saturday,
        )
        after_midnight = enforcer.consume(
            identity=professional,
            capability=Capability.ANALYSIS,
            now=datetime(2026, 9, 13, 0, 0, tzinfo=timezone.utc),
        )
        self.assertEqual(before_midnight.used, 1)
        self.assertEqual(after_midnight.used, 1)
        self.assertEqual(
            before_midnight.reset_at,
            datetime(2026, 9, 13, 0, 0, tzinfo=timezone.utc),
        )

    def test_atomic_boundary_prevents_concurrent_professional_overrun(self):
        store = AtomicMemoryStore()
        enforcer = QuotaEnforcer(store=store, timezone_name="UTC")
        identity = VerifiedQuotaIdentity(
            uid="professional-1", role=AccountRole.PROFESSIONAL
        )
        now = datetime(2026, 9, 12, 10, tzinfo=timezone.utc)

        def consume_once(_):
            return enforcer.consume(
                identity=identity,
                capability=Capability.ANALYSIS,
                now=now,
            )

        with ThreadPoolExecutor(max_workers=16) as executor:
            decisions = list(executor.map(consume_once, range(80)))

        allowed = [decision for decision in decisions if decision.allowed]
        denied = [decision for decision in decisions if not decision.allowed]
        self.assertEqual(len(allowed), 50)
        self.assertEqual(len(denied), 30)
        self.assertTrue(all(item.reason == "quota_exhausted" for item in denied))
        self.assertEqual(min(item.remaining for item in allowed), 0)

    def test_named_timezone_reset_is_stable_and_naive_clock_is_rejected(self):
        store = AtomicMemoryStore()
        enforcer = QuotaEnforcer(
            store=store, timezone_name="Asia/Ho_Chi_Minh"
        )
        identity = VerifiedQuotaIdentity(
            uid="professional-vn", role=AccountRole.PROFESSIONAL
        )
        before_local_midnight = datetime(
            2026, 9, 12, 16, 59, tzinfo=timezone.utc
        )
        decision = enforcer.consume(
            identity=identity,
            capability=Capability.ANALYSIS,
            now=before_local_midnight,
        )
        self.assertEqual(
            decision.reset_at,
            datetime(2026, 9, 12, 17, 0, tzinfo=timezone.utc),
        )
        with self.assertRaises(ValueError):
            enforcer.consume(
                identity=identity,
                capability=Capability.ANALYSIS,
                now=datetime(2026, 9, 12, 17, 0),
            )


if __name__ == "__main__":
    unittest.main()
