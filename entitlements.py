"""Deterministic V2.1 role and quota contracts.

This module deliberately owns no token verification or persistence. Callers must
pass claims returned by Firebase Admin token verification and a shared store that
implements one atomic compare-and-increment operation.
"""

from __future__ import annotations

from dataclasses import dataclass
from datetime import datetime, timedelta, timezone
from enum import Enum
from typing import AbstractSet, Mapping, Protocol
from zoneinfo import ZoneInfo


class EntitlementDenied(ValueError):
    """Raised when verified identity claims cannot map to an approved role."""


class PurchaseDenied(ValueError):
    """Raised when a store purchase cannot grant a server entitlement."""


class AccountRole(str, Enum):
    STANDARD = "standard"
    VERIFIED_PARTNER = "verified_partner"
    PROFESSIONAL = "professional"
    ENTERPRISE = "enterprise"
    RESERVED_FIFTH = "reserved_fifth"


class Capability(str, Enum):
    ANALYSIS = "analysis"
    BACKTEST = "backtest"
    BROKER_SYNC = "broker_sync"
    REALTIME_SIGNAL = "realtime_signal"
    MULTI_TIMEFRAME = "multi_timeframe"
    PRIVILEGED_OPERATION = "privileged_operation"


_VERIFIED_PARTNER_FEATURES = frozenset(
    {
        Capability.BROKER_SYNC,
        Capability.REALTIME_SIGNAL,
        Capability.MULTI_TIMEFRAME,
    }
)


def can_use_verified_partner_feature(
    *, identity: VerifiedQuotaIdentity, capability: Capability
) -> bool:
    """Authorize only the three explicitly specified partner capabilities."""

    if capability not in _VERIFIED_PARTNER_FEATURES:
        raise ValueError("Capability is not a Verified Partner feature")
    return identity.role == AccountRole.VERIFIED_PARTNER


class QuotaPeriod(str, Enum):
    DAILY = "daily"
    WEEKLY = "weekly"


@dataclass(frozen=True)
class VerifiedQuotaIdentity:
    uid: str
    role: AccountRole
    is_admin: bool = False

    @classmethod
    def from_decoded_token(
        cls, claims: Mapping[str, object]
    ) -> "VerifiedQuotaIdentity":
        uid_claim = claims.get("uid")
        subject_claim = claims.get("sub")
        if uid_claim is not None and subject_claim is not None:
            if uid_claim != subject_claim:
                raise EntitlementDenied("Token subject mismatch")
        uid = uid_claim if uid_claim is not None else subject_claim
        role_claim = claims.get("role")
        if not isinstance(uid, str) or not uid.strip():
            raise EntitlementDenied("Verified token has no subject")
        if not isinstance(role_claim, str):
            raise EntitlementDenied("Verified token has no approved role")
        normalized_role = role_claim.strip().lower().replace("-", "_")
        try:
            role = AccountRole(normalized_role)
        except ValueError as exc:
            raise EntitlementDenied("Verified token has no approved role") from exc
        return cls(
            uid=uid.strip(),
            role=role,
            is_admin=claims.get("admin") is True,
        )


def should_show_standard_ad(
    *,
    identity: VerifiedQuotaIdentity,
    placement_id: str,
    approved_placements: AbstractSet[str],
    ads_consent: bool,
) -> bool:
    """Return whether an approved Standard-only ad placement may be shown."""

    if identity.is_admin or identity.role != AccountRole.STANDARD:
        return False
    if ads_consent is not True or not isinstance(placement_id, str):
        return False
    normalized_placement = placement_id.strip()
    return bool(normalized_placement) and normalized_placement in approved_placements


class PurchaseState(str, Enum):
    ACTIVE = "active"
    REFUNDED = "refunded"
    REVOKED = "revoked"
    EXPIRED = "expired"


@dataclass(frozen=True)
class VerifiedPurchaseReceipt:
    """Normalized purchase data returned only by a trusted server verifier."""

    subject_uid: str
    product_id: str
    transaction_id: str
    state: PurchaseState
    expires_at: datetime


class ReceiptVerifier(Protocol):
    def verify(
        self, *, receipt: str, product_id: str, platform: str
    ) -> VerifiedPurchaseReceipt:
        """Verify an opaque Apple/Google receipt with its authoritative store."""


@dataclass(frozen=True)
class ProfessionalEntitlementGrant:
    subject_uid: str
    role: AccountRole
    product_id: str
    transaction_id: str
    expires_at: datetime
    source: str


class PurchaseEntitlementService:
    """Validate server receipts before granting the Professional role."""

    _MAX_RECEIPT_LENGTH = 16 * 1024
    _SUPPORTED_PLATFORMS = frozenset({"apple", "google"})

    def __init__(
        self,
        *,
        verifier: ReceiptVerifier,
        professional_product_ids: AbstractSet[str],
    ):
        approved_products = frozenset(
            product_id.strip()
            for product_id in professional_product_ids
            if isinstance(product_id, str) and product_id.strip()
        )
        if not approved_products:
            raise ValueError("At least one Professional product is required")
        self._verifier = verifier
        self._professional_product_ids = approved_products

    def validate_professional_purchase(
        self,
        *,
        identity: VerifiedQuotaIdentity,
        receipt: str,
        product_id: str,
        platform: str,
        now: datetime,
    ) -> ProfessionalEntitlementGrant:
        if now.tzinfo is None or now.utcoffset() is None:
            raise ValueError("Purchase clock must be timezone-aware")
        if not isinstance(receipt, str) or not receipt.strip():
            raise PurchaseDenied("Purchase verification failed")
        if len(receipt) > self._MAX_RECEIPT_LENGTH:
            raise PurchaseDenied("Purchase verification failed")
        if not isinstance(product_id, str):
            raise PurchaseDenied("Purchase verification failed")
        normalized_product = product_id.strip()
        if normalized_product not in self._professional_product_ids:
            raise PurchaseDenied("Purchase verification failed")
        if not isinstance(platform, str):
            raise PurchaseDenied("Purchase verification failed")
        normalized_platform = platform.strip().lower()
        if normalized_platform not in self._SUPPORTED_PLATFORMS:
            raise PurchaseDenied("Purchase verification failed")

        verified = self._verifier.verify(
            receipt=receipt,
            product_id=normalized_product,
            platform=normalized_platform,
        )
        if not isinstance(verified, VerifiedPurchaseReceipt):
            raise PurchaseDenied("Purchase verification failed")
        if (
            verified.subject_uid != identity.uid
            or verified.product_id != normalized_product
            or not isinstance(verified.transaction_id, str)
            or not verified.transaction_id.strip()
            or verified.state != PurchaseState.ACTIVE
            or verified.expires_at.tzinfo is None
            or verified.expires_at.utcoffset() is None
            or verified.expires_at <= now
        ):
            raise PurchaseDenied("Purchase verification failed")

        return ProfessionalEntitlementGrant(
            subject_uid=identity.uid,
            role=AccountRole.PROFESSIONAL,
            product_id=normalized_product,
            transaction_id=verified.transaction_id.strip(),
            expires_at=verified.expires_at,
            source="verified_iap",
        )


@dataclass(frozen=True)
class QuotaPolicy:
    limit: int
    period: QuotaPeriod


ROLE_ANALYSIS_QUOTAS: Mapping[AccountRole, QuotaPolicy] = {
    AccountRole.STANDARD: QuotaPolicy(limit=2, period=QuotaPeriod.WEEKLY),
    AccountRole.PROFESSIONAL: QuotaPolicy(limit=50, period=QuotaPeriod.DAILY),
    AccountRole.ENTERPRISE: QuotaPolicy(limit=300, period=QuotaPeriod.DAILY),
}


class AtomicQuotaStore(Protocol):
    def consume_if_below(
        self,
        *,
        subject_id: str,
        counter_key: str,
        window_start: datetime,
        reset_at: datetime,
        limit: int,
    ) -> int | None:
        """Atomically increment and return used count, or None when exhausted."""


@dataclass(frozen=True)
class QuotaDecision:
    allowed: bool
    role: AccountRole
    capability: Capability
    used: int | None
    limit: int | None
    remaining: int | None
    period: str | None
    reset_at: datetime | None
    reason: str


class QuotaEnforcer:
    def __init__(self, *, store: AtomicQuotaStore, timezone_name: str):
        self._store = store
        self._timezone = ZoneInfo(timezone_name)

    def consume(
        self,
        *,
        identity: VerifiedQuotaIdentity,
        capability: Capability,
        now: datetime,
    ) -> QuotaDecision:
        if now.tzinfo is None or now.utcoffset() is None:
            raise ValueError("Quota clock must be timezone-aware")

        if identity.role == AccountRole.VERIFIED_PARTNER and capability in {
            Capability.REALTIME_SIGNAL,
            Capability.MULTI_TIMEFRAME,
        }:
            return QuotaDecision(
                allowed=True,
                role=identity.role,
                capability=capability,
                used=None,
                limit=None,
                remaining=None,
                period=None,
                reset_at=None,
                reason="unlimited_verified_partner_realtime",
            )

        policy = (
            ROLE_ANALYSIS_QUOTAS.get(identity.role)
            if capability == Capability.ANALYSIS
            else None
        )
        if policy is None:
            return QuotaDecision(
                allowed=False,
                role=identity.role,
                capability=capability,
                used=None,
                limit=None,
                remaining=None,
                period=None,
                reset_at=None,
                reason="policy_pending",
            )

        window_start, reset_at = self._window(now, policy.period)
        counter_key = f"{identity.role.value}:{capability.value}:{policy.period.value}"
        used = self._store.consume_if_below(
            subject_id=identity.uid,
            counter_key=counter_key,
            window_start=window_start,
            reset_at=reset_at,
            limit=policy.limit,
        )
        if used is None:
            return QuotaDecision(
                allowed=False,
                role=identity.role,
                capability=capability,
                used=policy.limit,
                limit=policy.limit,
                remaining=0,
                period=policy.period.value,
                reset_at=reset_at,
                reason="quota_exhausted",
            )
        if used <= 0 or used > policy.limit:
            raise RuntimeError("Atomic quota store returned an invalid count")
        return QuotaDecision(
            allowed=True,
            role=identity.role,
            capability=capability,
            used=used,
            limit=policy.limit,
            remaining=policy.limit - used,
            period=policy.period.value,
            reset_at=reset_at,
            reason="quota_consumed",
        )

    def _window(
        self, now: datetime, period: QuotaPeriod
    ) -> tuple[datetime, datetime]:
        local_now = now.astimezone(self._timezone)
        local_start = local_now.replace(hour=0, minute=0, second=0, microsecond=0)
        if period == QuotaPeriod.WEEKLY:
            local_start -= timedelta(days=local_start.weekday())
            local_reset = local_start + timedelta(days=7)
        else:
            local_reset = local_start + timedelta(days=1)
        return (
            local_start.astimezone(timezone.utc),
            local_reset.astimezone(timezone.utc),
        )
