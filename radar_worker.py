"""Provider-neutral two-stage Radar worker contract for V2.1."""

from __future__ import annotations

import hashlib
from dataclasses import dataclass
from decimal import Decimal
from typing import Protocol, Sequence

from admin_controls import AdminConfigurationInvalid, validate_admin_watchlist


class RadarSourceInvalid(ValueError):
    """Raised before model work when market provenance is incomplete."""


class RadarConfirmationInvalid(ValueError):
    """Raised when the model response cannot be traced to source bars."""


@dataclass(frozen=True)
class RadarBar:
    source_bar_id: str
    closed_at: int
    open: Decimal
    high: Decimal
    low: Decimal
    close: Decimal
    volume: Decimal


@dataclass(frozen=True)
class BarrierEvidence:
    kind: str
    source_id: str


@dataclass(frozen=True)
class RadarAssetSnapshot:
    symbol: str
    timeframe: str
    provider: str
    license_ref: str
    bars: tuple[RadarBar, ...]
    barrier: BarrierEvidence | None = None


@dataclass(frozen=True)
class RadarCandidate:
    symbol: str
    timeframe: str
    provider: str
    license_ref: str
    closed_at: int
    reasons: tuple[str, ...]
    source_bar_ids: tuple[str, ...]
    barrier_source_id: str | None


@dataclass(frozen=True)
class RadarModelDecision:
    direction: str
    confidence: Decimal
    rationale: str
    model: str
    cited_bar_ids: tuple[str, ...]


@dataclass(frozen=True)
class RadarDeepLinkTarget:
    symbol: str
    timeframe: str
    closed_at: int


@dataclass(frozen=True)
class RadarConfirmation:
    confirmation_id: str
    direction: str
    confidence: Decimal
    rationale: str
    model: str
    provider: str
    license_ref: str
    cited_bar_ids: tuple[str, ...]
    target: RadarDeepLinkTarget


@dataclass(frozen=True)
class RadarRunResult:
    scanned_count: int
    candidate_count: int
    skipped_duplicate_count: int
    confirmations: tuple[RadarConfirmation, ...]


class RadarConfirmer(Protocol):
    def confirm(self, *, candidate: RadarCandidate) -> RadarModelDecision:
        """Confirm or reject one stage-one candidate using the approved model."""


class RadarWorkStore(Protocol):
    def begin_once(self, *, work_key: str, ttl_seconds: int) -> bool:
        """Atomically claim one closed-bar candidate, or return False."""

    def complete(
        self,
        *,
        work_key: str,
        confirmation: RadarConfirmation | None,
    ) -> None:
        """Persist the deterministic result and finish the claim."""

    def abandon(self, *, work_key: str) -> None:
        """Release a failed claim so an explicit retry can process it."""


class RadarWorker:
    WORK_TTL_SECONDS = 600
    _TIMEFRAMES = frozenset({"M5", "M15", "H1", "H4", "D1"})

    def __init__(self, *, confirmer: RadarConfirmer, work_store: RadarWorkStore):
        self._confirmer = confirmer
        self._work_store = work_store

    def scan(
        self,
        *,
        watchlist: Sequence[str],
        snapshots: Sequence[RadarAssetSnapshot],
    ) -> RadarRunResult:
        try:
            approved_symbols = validate_admin_watchlist(watchlist)
        except AdminConfigurationInvalid as exc:
            raise RadarSourceInvalid("Radar watchlist is unavailable") from exc
        if isinstance(snapshots, (str, bytes)):
            raise RadarSourceInvalid("Radar snapshots are unavailable")
        try:
            snapshot_items = tuple(snapshots)
        except TypeError as exc:
            raise RadarSourceInvalid("Radar snapshots are unavailable") from exc
        normalized: dict[str, RadarAssetSnapshot] = {}
        for snapshot in snapshot_items:
            self._validate_snapshot(snapshot)
            if snapshot.symbol in normalized:
                raise RadarSourceInvalid("Radar snapshot symbols are duplicated")
            normalized[snapshot.symbol] = snapshot
        if set(normalized) != set(approved_symbols):
            raise RadarSourceInvalid("Radar snapshots do not match the watchlist")

        candidates = tuple(
            candidate
            for symbol in approved_symbols
            if (candidate := self._stage_one(normalized[symbol])) is not None
        )
        confirmations: list[RadarConfirmation] = []
        skipped_duplicates = 0
        for candidate in candidates:
            work_key = self._work_key(candidate)
            claimed = self._work_store.begin_once(
                work_key=work_key,
                ttl_seconds=self.WORK_TTL_SECONDS,
            )
            if not isinstance(claimed, bool):
                raise RadarSourceInvalid("Radar work store returned invalid state")
            if not claimed:
                skipped_duplicates += 1
                continue
            try:
                decision = self._confirmer.confirm(candidate=candidate)
                confirmation = self._validate_decision(
                    candidate=candidate,
                    decision=decision,
                    work_key=work_key,
                )
                self._work_store.complete(
                    work_key=work_key,
                    confirmation=confirmation,
                )
            except Exception:
                self._work_store.abandon(work_key=work_key)
                raise
            if confirmation is not None:
                confirmations.append(confirmation)

        return RadarRunResult(
            scanned_count=len(approved_symbols),
            candidate_count=len(candidates),
            skipped_duplicate_count=skipped_duplicates,
            confirmations=tuple(confirmations),
        )

    @classmethod
    def _validate_snapshot(cls, snapshot: RadarAssetSnapshot) -> None:
        if not isinstance(snapshot, RadarAssetSnapshot):
            raise RadarSourceInvalid("Radar snapshot is invalid")
        if (
            not snapshot.symbol
            or snapshot.symbol != snapshot.symbol.strip().upper()
            or snapshot.timeframe not in cls._TIMEFRAMES
            or not isinstance(snapshot.provider, str)
            or not snapshot.provider.strip()
            or not isinstance(snapshot.license_ref, str)
            or not snapshot.license_ref.strip()
            or len(snapshot.bars) != 21
        ):
            raise RadarSourceInvalid("Radar snapshot is invalid")
        prior_timestamp = 0
        bar_ids: set[str] = set()
        for bar in snapshot.bars:
            if not isinstance(bar, RadarBar):
                raise RadarSourceInvalid("Radar bar is invalid")
            values = (bar.open, bar.high, bar.low, bar.close, bar.volume)
            if any(
                not isinstance(value, Decimal) or not value.is_finite()
                for value in values
            ):
                raise RadarSourceInvalid("Radar bar is invalid")
            if (
                not isinstance(bar.source_bar_id, str)
                or not bar.source_bar_id.strip()
                or bar.source_bar_id in bar_ids
                or not isinstance(bar.closed_at, int)
                or bar.closed_at <= prior_timestamp
                or bar.low > min(bar.open, bar.close)
                or bar.high < max(bar.open, bar.close)
                or bar.low > bar.high
                or bar.volume < 0
            ):
                raise RadarSourceInvalid("Radar bar is invalid")
            prior_timestamp = bar.closed_at
            bar_ids.add(bar.source_bar_id)
        if snapshot.barrier is not None and (
            not isinstance(snapshot.barrier, BarrierEvidence)
            or not isinstance(snapshot.barrier.kind, str)
            or not snapshot.barrier.kind.strip()
            or not isinstance(snapshot.barrier.source_id, str)
            or not snapshot.barrier.source_id.strip()
        ):
            raise RadarSourceInvalid("Radar barrier evidence is invalid")

    @staticmethod
    def _stage_one(snapshot: RadarAssetSnapshot) -> RadarCandidate | None:
        current = snapshot.bars[-1]
        prior = snapshot.bars[:-1]
        baseline = sum((bar.volume for bar in prior), Decimal("0")) / Decimal(
            len(prior)
        )
        reasons: list[str] = []
        if baseline > 0 and current.volume >= baseline * Decimal("3"):
            reasons.append("volume_3x")
        if snapshot.barrier is not None:
            reasons.append("structural_barrier")
        if not reasons:
            return None
        return RadarCandidate(
            symbol=snapshot.symbol,
            timeframe=snapshot.timeframe,
            provider=snapshot.provider.strip(),
            license_ref=snapshot.license_ref.strip(),
            closed_at=current.closed_at,
            reasons=tuple(reasons),
            source_bar_ids=tuple(bar.source_bar_id for bar in snapshot.bars),
            barrier_source_id=(
                snapshot.barrier.source_id if snapshot.barrier is not None else None
            ),
        )

    @staticmethod
    def _work_key(candidate: RadarCandidate) -> str:
        return (
            f"radar:{candidate.symbol}:{candidate.timeframe}:"
            f"{candidate.closed_at}"
        )

    @staticmethod
    def _validate_decision(
        *,
        candidate: RadarCandidate,
        decision: RadarModelDecision,
        work_key: str,
    ) -> RadarConfirmation | None:
        if not isinstance(decision, RadarModelDecision):
            raise RadarConfirmationInvalid("Radar confirmation is invalid")
        if not isinstance(decision.direction, str):
            raise RadarConfirmationInvalid("Radar confirmation is invalid")
        direction = decision.direction.strip().upper()
        if direction not in {"BUY", "SELL", "NONE"}:
            raise RadarConfirmationInvalid("Radar confirmation is invalid")
        if (
            not isinstance(decision.confidence, Decimal)
            or not decision.confidence.is_finite()
            or decision.confidence < 0
            or decision.confidence > 100
            or not isinstance(decision.rationale, str)
            or not decision.rationale.strip()
            or len(decision.rationale) > 1000
            or not isinstance(decision.model, str)
            or not decision.model.strip()
        ):
            raise RadarConfirmationInvalid("Radar confirmation is invalid")
        try:
            cited = tuple(decision.cited_bar_ids)
        except TypeError as exc:
            raise RadarConfirmationInvalid(
                "Radar confirmation is invalid"
            ) from exc
        if (
            not cited
            or len(cited) != len(set(cited))
            or not set(cited).issubset(candidate.source_bar_ids)
        ):
            raise RadarConfirmationInvalid("Radar confirmation is untraceable")
        if direction == "NONE":
            return None
        digest = hashlib.sha256(
            (
                f"{work_key}|{direction}|{decision.model.strip()}|"
                f"{'|'.join(cited)}"
            ).encode("utf-8")
        ).hexdigest()[:24]
        return RadarConfirmation(
            confirmation_id=f"radar-{digest}",
            direction=direction,
            confidence=decision.confidence,
            rationale=decision.rationale.strip(),
            model=decision.model.strip(),
            provider=candidate.provider,
            license_ref=candidate.license_ref,
            cited_bar_ids=cited,
            target=RadarDeepLinkTarget(
                symbol=candidate.symbol,
                timeframe=candidate.timeframe,
                closed_at=candidate.closed_at,
            ),
        )
