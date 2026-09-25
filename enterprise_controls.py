"""Fail-closed Enterprise membership and aggregate-risk contracts for V2.1.

The store boundary represents authoritative server data. This module does not
accept membership or account snapshots from an API client and deliberately has
no broker credential fields.
"""

from __future__ import annotations

from dataclasses import dataclass
from decimal import Decimal
from typing import Protocol, Sequence

from entitlements import AccountRole, VerifiedQuotaIdentity


class EnterpriseAccessDenied(PermissionError):
    """Raised when an identity cannot manage the requested subaccount."""


class EnterpriseStateInvalid(RuntimeError):
    """Raised when authoritative membership or risk state is incomplete."""


@dataclass(frozen=True)
class EnterpriseRiskLimits:
    max_team_open_risk_pct: Decimal
    max_team_daily_loss_pct: Decimal
    max_subaccount_open_risk_pct: Decimal

    def __post_init__(self) -> None:
        for value in (
            self.max_team_open_risk_pct,
            self.max_team_daily_loss_pct,
            self.max_subaccount_open_risk_pct,
        ):
            if not isinstance(value, Decimal) or not value.is_finite():
                raise ValueError("Enterprise risk limits must be finite decimals")
            if value <= 0 or value > 100:
                raise ValueError("Enterprise risk limits must be within 0..100")


@dataclass(frozen=True)
class EnterpriseRiskSnapshot:
    subaccount_uid: str
    equity: Decimal
    open_risk: Decimal
    daily_loss: Decimal


@dataclass(frozen=True)
class EnterpriseRiskDecision:
    allowed: bool
    reason: str
    team_equity: Decimal
    team_open_risk: Decimal
    team_daily_loss: Decimal
    team_open_risk_pct: Decimal
    team_daily_loss_pct: Decimal
    subaccount_open_risk_pct: Decimal


class EnterpriseControlStore(Protocol):
    def list_assigned_subaccounts(self, *, master_uid: str) -> Sequence[str]:
        """Return authoritative subaccount assignments for one master."""

    def get_risk_snapshots(
        self, *, subaccount_uids: Sequence[str]
    ) -> Sequence[EnterpriseRiskSnapshot]:
        """Return authoritative risk data for every requested subaccount."""


class EnterpriseControlService:
    def __init__(self, *, store: EnterpriseControlStore):
        self._store = store

    def authorize_management(
        self,
        *,
        identity: VerifiedQuotaIdentity,
        subaccount_uid: str,
    ) -> None:
        assignments = self._load_assignments(identity)
        target = self._validate_target(subaccount_uid)
        if target not in assignments:
            raise EnterpriseAccessDenied("Enterprise subaccount access denied")

    def evaluate_proposed_risk(
        self,
        *,
        identity: VerifiedQuotaIdentity,
        subaccount_uid: str,
        proposed_additional_risk: Decimal,
        limits: EnterpriseRiskLimits,
    ) -> EnterpriseRiskDecision:
        assignments = self._load_assignments(identity)
        target = self._validate_target(subaccount_uid)
        if target not in assignments:
            raise EnterpriseAccessDenied("Enterprise subaccount access denied")
        if (
            not isinstance(proposed_additional_risk, Decimal)
            or not proposed_additional_risk.is_finite()
            or proposed_additional_risk < 0
        ):
            raise ValueError("Proposed risk must be a non-negative finite decimal")

        snapshots = self._store.get_risk_snapshots(
            subaccount_uids=assignments
        )
        normalized = self._validate_snapshots(
            assignments=assignments, snapshots=snapshots
        )
        target_snapshot = normalized[target]
        team_equity = sum(
            (snapshot.equity for snapshot in normalized.values()), Decimal("0")
        )
        team_open_risk = (
            sum(
                (snapshot.open_risk for snapshot in normalized.values()),
                Decimal("0"),
            )
            + proposed_additional_risk
        )
        team_daily_loss = sum(
            (snapshot.daily_loss for snapshot in normalized.values()),
            Decimal("0"),
        )
        team_open_risk_pct = team_open_risk * Decimal("100") / team_equity
        team_daily_loss_pct = team_daily_loss * Decimal("100") / team_equity
        subaccount_open_risk_pct = (
            (target_snapshot.open_risk + proposed_additional_risk)
            * Decimal("100")
            / target_snapshot.equity
        )

        if subaccount_open_risk_pct > limits.max_subaccount_open_risk_pct:
            allowed = False
            reason = "subaccount_open_risk_limit_exceeded"
        elif team_open_risk_pct > limits.max_team_open_risk_pct:
            allowed = False
            reason = "team_open_risk_limit_exceeded"
        elif team_daily_loss_pct > limits.max_team_daily_loss_pct:
            allowed = False
            reason = "team_daily_loss_limit_exceeded"
        else:
            allowed = True
            reason = "within_enterprise_limits"

        return EnterpriseRiskDecision(
            allowed=allowed,
            reason=reason,
            team_equity=team_equity,
            team_open_risk=team_open_risk,
            team_daily_loss=team_daily_loss,
            team_open_risk_pct=team_open_risk_pct,
            team_daily_loss_pct=team_daily_loss_pct,
            subaccount_open_risk_pct=subaccount_open_risk_pct,
        )

    def _load_assignments(
        self, identity: VerifiedQuotaIdentity
    ) -> tuple[str, ...]:
        if identity.role != AccountRole.ENTERPRISE:
            raise EnterpriseAccessDenied("Enterprise subaccount access denied")
        raw_assignments = self._store.list_assigned_subaccounts(
            master_uid=identity.uid
        )
        if isinstance(raw_assignments, (str, bytes)):
            raise EnterpriseStateInvalid("Enterprise membership is invalid")
        try:
            assignments = tuple(raw_assignments)
        except TypeError as exc:
            raise EnterpriseStateInvalid(
                "Enterprise membership is invalid"
            ) from exc
        if len(assignments) != len(set(assignments)):
            raise EnterpriseStateInvalid("Enterprise membership is invalid")
        for assigned_uid in assignments:
            if (
                not isinstance(assigned_uid, str)
                or not assigned_uid.strip()
                or assigned_uid != assigned_uid.strip()
                or assigned_uid == identity.uid
            ):
                raise EnterpriseStateInvalid("Enterprise membership is invalid")
        return assignments

    @staticmethod
    def _validate_target(subaccount_uid: str) -> str:
        if (
            not isinstance(subaccount_uid, str)
            or not subaccount_uid.strip()
            or subaccount_uid != subaccount_uid.strip()
        ):
            raise EnterpriseAccessDenied("Enterprise subaccount access denied")
        return subaccount_uid

    @staticmethod
    def _validate_snapshots(
        *,
        assignments: Sequence[str],
        snapshots: Sequence[EnterpriseRiskSnapshot],
    ) -> dict[str, EnterpriseRiskSnapshot]:
        if isinstance(snapshots, (str, bytes)):
            raise EnterpriseStateInvalid("Enterprise risk state is invalid")
        try:
            snapshot_items = tuple(snapshots)
        except TypeError as exc:
            raise EnterpriseStateInvalid(
                "Enterprise risk state is invalid"
            ) from exc
        normalized: dict[str, EnterpriseRiskSnapshot] = {}
        for snapshot in snapshot_items:
            if not isinstance(snapshot, EnterpriseRiskSnapshot):
                raise EnterpriseStateInvalid("Enterprise risk state is invalid")
            if snapshot.subaccount_uid in normalized:
                raise EnterpriseStateInvalid("Enterprise risk state is invalid")
            for value in (snapshot.equity, snapshot.open_risk, snapshot.daily_loss):
                if not isinstance(value, Decimal) or not value.is_finite():
                    raise EnterpriseStateInvalid("Enterprise risk state is invalid")
            if (
                snapshot.equity <= 0
                or snapshot.open_risk < 0
                or snapshot.daily_loss < 0
            ):
                raise EnterpriseStateInvalid("Enterprise risk state is invalid")
            normalized[snapshot.subaccount_uid] = snapshot
        if set(normalized) != set(assignments):
            raise EnterpriseStateInvalid("Enterprise risk state is incomplete")
        return normalized
