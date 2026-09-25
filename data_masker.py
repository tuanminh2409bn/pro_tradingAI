"""Consent-aware allowlist boundary for outbound V2.1 Data Lake records."""

from __future__ import annotations

import hashlib
import hmac
import re
from dataclasses import dataclass, field
from datetime import datetime, timedelta
from decimal import Decimal
from typing import Mapping, Protocol


class DataLakeExportDenied(ValueError):
    """Raised when a record is not explicitly safe and authorized to export."""


@dataclass(frozen=True)
class DataLakePolicy:
    pseudonym_key: bytes = field(repr=False)
    pseudonym_key_id: str
    consent_version: str
    retention_days: int
    allowed_event_types: frozenset[str]

    def __post_init__(self) -> None:
        if not isinstance(self.pseudonym_key, bytes) or len(self.pseudonym_key) < 32:
            raise ValueError("Pseudonym key must contain at least 32 bytes")
        if (
            not isinstance(self.pseudonym_key_id, str)
            or not self.pseudonym_key_id.strip()
            or not isinstance(self.consent_version, str)
            or not self.consent_version.strip()
            or not isinstance(self.retention_days, int)
            or self.retention_days <= 0
            or not self.allowed_event_types
            or any(
                not isinstance(event_type, str) or not event_type.strip()
                for event_type in self.allowed_event_types
            )
        ):
            raise ValueError("Data Lake policy is invalid")


@dataclass(frozen=True)
class DataLakeSubject:
    uid: str = field(repr=False)
    consent_granted: bool
    consent_version: str
    deletion_requested_at: datetime | None


@dataclass(frozen=True)
class MaskedDataLakeRecord:
    subject_ref: str
    pseudonym_key_id: str
    event_type: str
    occurred_at: datetime
    expires_at: datetime
    symbol: str
    timeframe: str
    percentage_growth: Decimal
    unit_volume: Decimal
    country: str
    device_type: str
    outcome: str


@dataclass(frozen=True)
class DataLakeDeletionResult:
    subject_ref: str
    deleted_count: int


class DataLakeDeletionStore(Protocol):
    def delete_subject(self, *, subject_ref: str) -> int:
        """Delete every retained record for one pseudonymous subject."""


_EVENT_FIELDS = frozenset(
    {
        "event_type",
        "occurred_at",
        "symbol",
        "timeframe",
        "percentage_growth",
        "unit_volume",
        "country",
        "device_type",
        "outcome",
    }
)
_SYMBOL_PATTERN = re.compile(r"^[A-Z0-9._:-]{2,24}$")
_TIMEFRAMES = frozenset({"M5", "M15", "H1", "H4", "D1"})
_DEVICE_TYPES = frozenset({"web", "ios", "android"})
_OUTCOMES = frozenset({"success", "failure", "unavailable"})


def _subject_reference(*, uid: str, policy: DataLakePolicy) -> str:
    if not isinstance(uid, str) or not uid.strip() or uid != uid.strip():
        raise DataLakeExportDenied("Data Lake subject is invalid")
    digest = hmac.new(
        policy.pseudonym_key,
        f"data-lake-subject:v1:{uid}".encode("utf-8"),
        hashlib.sha256,
    ).hexdigest()
    return f"dl-{digest}"


class DataLakeMasker:
    def __init__(self, *, policy: DataLakePolicy):
        self._policy = policy

    def mask(
        self,
        *,
        subject: DataLakeSubject,
        event: Mapping[str, object],
        now: datetime,
    ) -> MaskedDataLakeRecord:
        self._validate_clock(now)
        self._validate_subject(subject)
        if not isinstance(event, Mapping) or set(event) != _EVENT_FIELDS:
            raise DataLakeExportDenied("Data Lake event fields are not allowlisted")

        event_type = event["event_type"]
        occurred_at = event["occurred_at"]
        symbol = event["symbol"]
        timeframe = event["timeframe"]
        percentage_growth = event["percentage_growth"]
        unit_volume = event["unit_volume"]
        country = event["country"]
        device_type = event["device_type"]
        outcome = event["outcome"]
        if (
            not isinstance(event_type, str)
            or event_type not in self._policy.allowed_event_types
            or not isinstance(occurred_at, datetime)
            or occurred_at.tzinfo is None
            or occurred_at.utcoffset() is None
            or occurred_at > now
            or not isinstance(symbol, str)
            or _SYMBOL_PATTERN.fullmatch(symbol) is None
            or timeframe not in _TIMEFRAMES
            or not isinstance(percentage_growth, Decimal)
            or not percentage_growth.is_finite()
            or not isinstance(unit_volume, Decimal)
            or not unit_volume.is_finite()
            or unit_volume < 0
            or not isinstance(country, str)
            or len(country) != 2
            or country != country.upper()
            or not country.isalpha()
            or device_type not in _DEVICE_TYPES
            or outcome not in _OUTCOMES
        ):
            raise DataLakeExportDenied("Data Lake event is invalid")
        expires_at = occurred_at + timedelta(days=self._policy.retention_days)
        if expires_at <= now:
            raise DataLakeExportDenied("Data Lake event is outside retention")

        return MaskedDataLakeRecord(
            subject_ref=_subject_reference(uid=subject.uid, policy=self._policy),
            pseudonym_key_id=self._policy.pseudonym_key_id,
            event_type=event_type,
            occurred_at=occurred_at,
            expires_at=expires_at,
            symbol=symbol,
            timeframe=timeframe,
            percentage_growth=percentage_growth,
            unit_volume=unit_volume,
            country=country,
            device_type=device_type,
            outcome=outcome,
        )

    @staticmethod
    def _validate_clock(now: datetime) -> None:
        if not isinstance(now, datetime) or now.tzinfo is None or now.utcoffset() is None:
            raise ValueError("Data Lake clock must be timezone-aware")

    def _validate_subject(self, subject: DataLakeSubject) -> None:
        if (
            not isinstance(subject, DataLakeSubject)
            or subject.consent_granted is not True
            or subject.consent_version != self._policy.consent_version
            or subject.deletion_requested_at is not None
        ):
            raise DataLakeExportDenied("Data Lake consent is unavailable")
        _subject_reference(uid=subject.uid, policy=self._policy)


class DataLakeDeletionService:
    def __init__(
        self, *, policy: DataLakePolicy, store: DataLakeDeletionStore
    ):
        self._policy = policy
        self._store = store

    def delete(self, *, subject: DataLakeSubject) -> DataLakeDeletionResult:
        if not isinstance(subject, DataLakeSubject):
            raise DataLakeExportDenied("Data Lake subject is invalid")
        subject_ref = _subject_reference(uid=subject.uid, policy=self._policy)
        deleted_count = self._store.delete_subject(subject_ref=subject_ref)
        if (
            not isinstance(deleted_count, int)
            or isinstance(deleted_count, bool)
            or deleted_count < 0
        ):
            raise RuntimeError("Data Lake deletion result is invalid")
        return DataLakeDeletionResult(
            subject_ref=subject_ref,
            deleted_count=deleted_count,
        )
