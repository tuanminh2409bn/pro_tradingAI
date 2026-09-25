"""Server-side manual push selection, delivery, retirement, and audit contract."""

from __future__ import annotations

import re
from dataclasses import dataclass
from enum import Enum
from typing import Mapping, Protocol, Sequence

from admin_controls import AdminAccessDenied, require_admin
from entitlements import AccountRole, VerifiedQuotaIdentity


class PushDeliveryDenied(ValueError):
    """Raised when a manual push cannot be safely delivered."""


class DeviceType(str, Enum):
    WEB = "web"
    IOS = "ios"
    ANDROID = "android"


@dataclass(frozen=True)
class PushRecipient:
    uid: str
    role: AccountRole
    country: str
    device: DeviceType
    opted_in: bool
    token_ref: str


@dataclass(frozen=True)
class PushSegment:
    roles: frozenset[AccountRole] = frozenset()
    countries: frozenset[str] = frozenset()
    devices: frozenset[DeviceType] = frozenset()


@dataclass(frozen=True)
class PushDeepLink:
    tab: str
    symbol: str
    timeframe: str
    closed_at: int


@dataclass(frozen=True)
class ManualPushRequest:
    request_id: str
    title: str
    body: str
    segment: PushSegment
    deep_link: PushDeepLink | None


@dataclass(frozen=True)
class PushPolicy:
    max_title_chars: int
    max_body_chars: int
    max_recipients: int

    def __post_init__(self) -> None:
        if (
            not isinstance(self.max_title_chars, int)
            or not isinstance(self.max_body_chars, int)
            or not isinstance(self.max_recipients, int)
            or self.max_title_chars <= 0
            or self.max_body_chars <= 0
            or self.max_recipients <= 0
        ):
            raise ValueError("Push policy limits must be positive integers")


@dataclass(frozen=True)
class PushProviderResult:
    delivered_token_refs: tuple[str, ...]
    invalid_token_refs: tuple[str, ...]
    failed_token_refs: tuple[str, ...]


@dataclass(frozen=True)
class PushAuditRecord:
    request_id: str
    admin_uid: str
    roles: tuple[str, ...]
    countries: tuple[str, ...]
    devices: tuple[str, ...]
    targeted_count: int
    delivered_count: int
    invalid_count: int
    failed_count: int
    deep_link: PushDeepLink | None


@dataclass(frozen=True)
class PushDeliverySummary:
    audit_id: str
    targeted_count: int
    delivered_count: int
    invalid_count: int
    failed_count: int


class PushRecipientStore(Protocol):
    def list_recipients(self) -> Sequence[PushRecipient]:
        """Load authoritative server-side recipient attributes and token refs."""

    def retire_token_refs(self, *, token_refs: Sequence[str]) -> None:
        """Retire provider-confirmed invalid token references."""


class PushProvider(Protocol):
    def send(
        self,
        *,
        token_refs: Sequence[str],
        title: str,
        body: str,
        data: Mapping[str, str],
    ) -> PushProviderResult:
        """Resolve opaque refs and deliver without returning raw tokens."""


class PushAuditStore(Protocol):
    def append(self, *, record: PushAuditRecord) -> str:
        """Persist an immutable delivery audit and return its identifier."""


_REQUEST_ID_PATTERN = re.compile(r"^[A-Za-z0-9._:-]{8,128}$")
_SYMBOL_PATTERN = re.compile(r"^[A-Z0-9._:-]{2,24}$")
_TIMEFRAMES = frozenset({"M5", "M15", "H1", "H4", "D1"})


class ManualPushService:
    def __init__(
        self,
        *,
        recipient_store: PushRecipientStore,
        provider: PushProvider,
        audit_store: PushAuditStore,
        policy: PushPolicy,
    ):
        self._recipient_store = recipient_store
        self._provider = provider
        self._audit_store = audit_store
        self._policy = policy

    def send(
        self,
        *,
        identity: VerifiedQuotaIdentity,
        request: ManualPushRequest,
    ) -> PushDeliverySummary:
        try:
            require_admin(identity)
        except AdminAccessDenied as exc:
            raise PushDeliveryDenied("Manual push access denied") from exc
        self._validate_request(request)

        raw_recipients = self._recipient_store.list_recipients()
        if isinstance(raw_recipients, (str, bytes)):
            raise PushDeliveryDenied("Push recipients are unavailable")
        try:
            recipients = tuple(raw_recipients)
        except TypeError as exc:
            raise PushDeliveryDenied("Push recipients are unavailable") from exc
        token_refs: list[str] = []
        seen_token_refs: set[str] = set()
        for recipient in recipients:
            self._validate_recipient(recipient)
            if recipient.token_ref in seen_token_refs:
                raise PushDeliveryDenied("Push recipient state is invalid")
            seen_token_refs.add(recipient.token_ref)
            if not recipient.opted_in or not self._matches(
                recipient, request.segment
            ):
                continue
            token_refs.append(recipient.token_ref)
        if not token_refs:
            raise PushDeliveryDenied("Manual push has no eligible recipients")
        if len(token_refs) > self._policy.max_recipients:
            raise PushDeliveryDenied("Manual push recipient limit exceeded")

        result = self._provider.send(
            token_refs=tuple(token_refs),
            title=request.title.strip(),
            body=request.body.strip(),
            data=self._deep_link_data(request.deep_link),
        )
        delivered, invalid, failed = self._validate_provider_result(
            result=result,
            target_token_refs=tuple(token_refs),
        )
        if invalid:
            self._recipient_store.retire_token_refs(token_refs=invalid)

        audit = PushAuditRecord(
            request_id=request.request_id,
            admin_uid=identity.uid,
            roles=tuple(sorted(role.value for role in request.segment.roles)),
            countries=tuple(sorted(request.segment.countries)),
            devices=tuple(sorted(device.value for device in request.segment.devices)),
            targeted_count=len(token_refs),
            delivered_count=len(delivered),
            invalid_count=len(invalid),
            failed_count=len(failed),
            deep_link=request.deep_link,
        )
        audit_id = self._audit_store.append(record=audit)
        if not isinstance(audit_id, str) or not audit_id.strip():
            raise PushDeliveryDenied("Push delivery audit failed")
        return PushDeliverySummary(
            audit_id=audit_id.strip(),
            targeted_count=len(token_refs),
            delivered_count=len(delivered),
            invalid_count=len(invalid),
            failed_count=len(failed),
        )

    def _validate_request(self, request: ManualPushRequest) -> None:
        if not isinstance(request, ManualPushRequest):
            raise PushDeliveryDenied("Manual push request is invalid")
        if (
            not isinstance(request.request_id, str)
            or _REQUEST_ID_PATTERN.fullmatch(request.request_id) is None
            or not isinstance(request.title, str)
            or not request.title.strip()
            or len(request.title.strip()) > self._policy.max_title_chars
            or not isinstance(request.body, str)
            or not request.body.strip()
            or len(request.body.strip()) > self._policy.max_body_chars
            or not isinstance(request.segment, PushSegment)
        ):
            raise PushDeliveryDenied("Manual push request is invalid")
        if any(not isinstance(role, AccountRole) for role in request.segment.roles):
            raise PushDeliveryDenied("Manual push segment is invalid")
        if any(
            not isinstance(country, str)
            or len(country) != 2
            or country != country.upper()
            or not country.isalpha()
            for country in request.segment.countries
        ):
            raise PushDeliveryDenied("Manual push segment is invalid")
        if any(
            not isinstance(device, DeviceType)
            for device in request.segment.devices
        ):
            raise PushDeliveryDenied("Manual push segment is invalid")
        if request.deep_link is not None:
            link = request.deep_link
            if (
                not isinstance(link, PushDeepLink)
                or link.tab != "trading_room"
                or not isinstance(link.symbol, str)
                or _SYMBOL_PATTERN.fullmatch(link.symbol) is None
                or link.timeframe not in _TIMEFRAMES
                or not isinstance(link.closed_at, int)
                or link.closed_at <= 0
            ):
                raise PushDeliveryDenied("Manual push deep link is invalid")

    @staticmethod
    def _validate_recipient(recipient: PushRecipient) -> None:
        if (
            not isinstance(recipient, PushRecipient)
            or not isinstance(recipient.uid, str)
            or not recipient.uid.strip()
            or not isinstance(recipient.role, AccountRole)
            or not isinstance(recipient.country, str)
            or len(recipient.country) != 2
            or recipient.country != recipient.country.upper()
            or not recipient.country.isalpha()
            or not isinstance(recipient.device, DeviceType)
            or not isinstance(recipient.opted_in, bool)
            or not isinstance(recipient.token_ref, str)
            or not recipient.token_ref.strip()
        ):
            raise PushDeliveryDenied("Push recipient state is invalid")

    @staticmethod
    def _matches(recipient: PushRecipient, segment: PushSegment) -> bool:
        return (
            (not segment.roles or recipient.role in segment.roles)
            and (not segment.countries or recipient.country in segment.countries)
            and (not segment.devices or recipient.device in segment.devices)
        )

    @staticmethod
    def _deep_link_data(link: PushDeepLink | None) -> Mapping[str, str]:
        if link is None:
            return {}
        return {
            "tab": link.tab,
            "symbol": link.symbol,
            "timeframe": link.timeframe,
            "closed_at": str(link.closed_at),
        }

    @staticmethod
    def _validate_provider_result(
        *,
        result: PushProviderResult,
        target_token_refs: tuple[str, ...],
    ) -> tuple[tuple[str, ...], tuple[str, ...], tuple[str, ...]]:
        if not isinstance(result, PushProviderResult):
            raise PushDeliveryDenied("Push provider result is invalid")
        groups = (
            tuple(result.delivered_token_refs),
            tuple(result.invalid_token_refs),
            tuple(result.failed_token_refs),
        )
        flattened = tuple(ref for group in groups for ref in group)
        if (
            any(not isinstance(ref, str) or not ref for ref in flattened)
            or len(flattened) != len(set(flattened))
            or set(flattened) != set(target_token_refs)
        ):
            raise PushDeliveryDenied("Push provider result is invalid")
        return groups
