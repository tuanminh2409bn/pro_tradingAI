import unittest
from dataclasses import fields
from decimal import Decimal

from enterprise_controls import (
    EnterpriseAccessDenied,
    EnterpriseControlService,
    EnterpriseRiskLimits,
    EnterpriseRiskSnapshot,
    EnterpriseStateInvalid,
)
from entitlements import (
    AccountRole,
    Capability,
    VerifiedQuotaIdentity,
    can_use_verified_partner_feature,
)


class StubEnterpriseStore:
    def __init__(self, *, assignments, snapshots):
        self.assignments = assignments
        self.snapshots = snapshots
        self.assignment_calls = []
        self.snapshot_calls = []

    def list_assigned_subaccounts(self, *, master_uid):
        self.assignment_calls.append(master_uid)
        return self.assignments

    def get_risk_snapshots(self, *, subaccount_uids):
        self.snapshot_calls.append(tuple(subaccount_uids))
        return self.snapshots


class EnterpriseControlTests(unittest.TestCase):
    def setUp(self):
        self.enterprise = VerifiedQuotaIdentity(
            uid="master-1", role=AccountRole.ENTERPRISE
        )
        self.limits = EnterpriseRiskLimits(
            max_team_open_risk_pct=Decimal("5"),
            max_team_daily_loss_pct=Decimal("4"),
            max_subaccount_open_risk_pct=Decimal("6"),
        )

    def test_only_verified_partner_can_use_exclusive_partner_features(self):
        partner_features = (
            Capability.BROKER_SYNC,
            Capability.REALTIME_SIGNAL,
            Capability.MULTI_TIMEFRAME,
        )
        for role in AccountRole:
            identity = VerifiedQuotaIdentity(uid=role.value, role=role)
            for capability in partner_features:
                self.assertEqual(
                    can_use_verified_partner_feature(
                        identity=identity, capability=capability
                    ),
                    role == AccountRole.VERIFIED_PARTNER,
                )
        with self.assertRaises(ValueError):
            can_use_verified_partner_feature(
                identity=self.enterprise, capability=Capability.ANALYSIS
            )

    def test_master_can_manage_only_authoritatively_assigned_subaccounts(self):
        store = StubEnterpriseStore(assignments=("sub-1", "sub-2"), snapshots=())
        service = EnterpriseControlService(store=store)

        service.authorize_management(
            identity=self.enterprise, subaccount_uid="sub-2"
        )
        with self.assertRaises(EnterpriseAccessDenied):
            service.authorize_management(
                identity=self.enterprise, subaccount_uid="other-team-sub"
            )

        non_enterprise = VerifiedQuotaIdentity(
            uid="partner-1", role=AccountRole.VERIFIED_PARTNER
        )
        calls_before = len(store.assignment_calls)
        with self.assertRaises(EnterpriseAccessDenied):
            service.authorize_management(
                identity=non_enterprise, subaccount_uid="sub-1"
            )
        self.assertEqual(len(store.assignment_calls), calls_before)

    def test_aggregate_risk_includes_every_assigned_account_and_proposal(self):
        store = StubEnterpriseStore(
            assignments=("sub-1", "sub-2"),
            snapshots=(
                EnterpriseRiskSnapshot(
                    subaccount_uid="sub-1",
                    equity=Decimal("10000"),
                    open_risk=Decimal("200"),
                    daily_loss=Decimal("100"),
                ),
                EnterpriseRiskSnapshot(
                    subaccount_uid="sub-2",
                    equity=Decimal("5000"),
                    open_risk=Decimal("100"),
                    daily_loss=Decimal("50"),
                ),
            ),
        )
        decision = EnterpriseControlService(store=store).evaluate_proposed_risk(
            identity=self.enterprise,
            subaccount_uid="sub-2",
            proposed_additional_risk=Decimal("100"),
            limits=self.limits,
        )

        self.assertTrue(decision.allowed)
        self.assertEqual(decision.team_equity, Decimal("15000"))
        self.assertEqual(decision.team_open_risk, Decimal("400"))
        self.assertEqual(decision.team_open_risk_pct, Decimal("40000") / Decimal("15000"))
        self.assertEqual(decision.reason, "within_enterprise_limits")
        self.assertEqual(store.snapshot_calls, [("sub-1", "sub-2")])

    def test_individual_team_and_daily_limits_fail_closed(self):
        cases = (
            (
                ("sub-1",),
                (
                    EnterpriseRiskSnapshot(
                        "sub-1", Decimal("1000"), Decimal("50"), Decimal("0")
                    ),
                ),
                Decimal("11"),
                "subaccount_open_risk_limit_exceeded",
            ),
            (
                ("sub-1", "sub-2"),
                (
                    EnterpriseRiskSnapshot(
                        "sub-1", Decimal("1000"), Decimal("0"), Decimal("0")
                    ),
                    EnterpriseRiskSnapshot(
                        "sub-2", Decimal("1000"), Decimal("60"), Decimal("0")
                    ),
                ),
                Decimal("41"),
                "team_open_risk_limit_exceeded",
            ),
            (
                ("sub-1",),
                (
                    EnterpriseRiskSnapshot(
                        "sub-1", Decimal("1000"), Decimal("0"), Decimal("41")
                    ),
                ),
                Decimal("0"),
                "team_daily_loss_limit_exceeded",
            ),
        )
        for assignments, snapshots, proposal, reason in cases:
            store = StubEnterpriseStore(
                assignments=assignments, snapshots=snapshots
            )
            decision = EnterpriseControlService(
                store=store
            ).evaluate_proposed_risk(
                identity=self.enterprise,
                subaccount_uid="sub-1",
                proposed_additional_risk=proposal,
                limits=self.limits,
            )
            self.assertFalse(decision.allowed)
            self.assertEqual(decision.reason, reason)

    def test_incomplete_or_unsafe_authoritative_state_is_rejected(self):
        self.assertEqual(
            {field.name for field in fields(EnterpriseRiskSnapshot)},
            {"subaccount_uid", "equity", "open_risk", "daily_loss"},
        )
        invalid_stores = (
            StubEnterpriseStore(
                assignments=("sub-1", "sub-2"),
                snapshots=(
                    EnterpriseRiskSnapshot(
                        "sub-1", Decimal("1000"), Decimal("0"), Decimal("0")
                    ),
                ),
            ),
            StubEnterpriseStore(
                assignments=("sub-1", "sub-1"), snapshots=()
            ),
            StubEnterpriseStore(
                assignments=("sub-1",),
                snapshots=(
                    EnterpriseRiskSnapshot(
                        "sub-1", Decimal("0"), Decimal("0"), Decimal("0")
                    ),
                ),
            ),
        )
        for store in invalid_stores:
            with self.assertRaises(EnterpriseStateInvalid):
                EnterpriseControlService(store=store).evaluate_proposed_risk(
                    identity=self.enterprise,
                    subaccount_uid="sub-1",
                    proposed_additional_risk=Decimal("0"),
                    limits=self.limits,
                )

        snapshot_fields = {field.name for field in fields(EnterpriseRiskSnapshot)}
        self.assertNotIn("password", snapshot_fields)
        self.assertNotIn("token", snapshot_fields)
        self.assertNotIn("credential", snapshot_fields)


if __name__ == "__main__":
    unittest.main()
