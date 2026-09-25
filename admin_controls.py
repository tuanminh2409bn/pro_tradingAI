"""Deterministic, fail-closed Admin runtime control contracts for V2.1."""

from __future__ import annotations

import re
import threading
import time
from enum import Enum
from typing import Callable, Sequence

from entitlements import AccountRole, VerifiedQuotaIdentity


class AdminAccessDenied(PermissionError):
    """Raised when a verified identity lacks the Admin claim."""


class AdminConfigurationInvalid(RuntimeError):
    """Raised when an authoritative Admin configuration is unusable."""


class KillSwitchActive(PermissionError):
    """Raised when the global switch disables analysis and execution."""


class BackendOperation(str, Enum):
    ANALYSIS = "analysis"
    EXECUTION = "execution"


def require_admin(identity: VerifiedQuotaIdentity) -> VerifiedQuotaIdentity:
    if identity.is_admin is not True or identity.role == AccountRole.RESERVED_FIFTH:
        raise AdminAccessDenied("Admin access denied")
    return identity


def ensure_backend_operation_allowed(
    *, trading_enabled: bool, operation: BackendOperation
) -> None:
    if not isinstance(operation, BackendOperation):
        raise ValueError("Unknown backend operation")
    if not isinstance(trading_enabled, bool):
        raise AdminConfigurationInvalid("Global operation state is unavailable")
    if not trading_enabled:
        raise KillSwitchActive(f"{operation.value} disabled by global control")


class MasterPromptCache:
    """Thread-safe five-minute cache backed by one authoritative loader."""

    TTL_SECONDS = 300.0
    MIN_LENGTH = 51
    MAX_LENGTH = 20_000

    def __init__(
        self,
        *,
        loader: Callable[[], str],
        clock: Callable[[], float] = time.monotonic,
    ):
        self._loader = loader
        self._clock = clock
        self._prompt: str | None = None
        self._loaded_at = 0.0
        self._lock = threading.RLock()

    def get(self) -> str:
        with self._lock:
            now = self._clock()
            if (
                self._prompt is not None
                and now - self._loaded_at < self.TTL_SECONDS
            ):
                return self._prompt
            prompt = self._loader()
            if not isinstance(prompt, str):
                raise AdminConfigurationInvalid("AI master prompt is unavailable")
            normalized = prompt.strip()
            if (
                len(normalized) < self.MIN_LENGTH
                or len(normalized) > self.MAX_LENGTH
                or "\x00" in normalized
            ):
                raise AdminConfigurationInvalid("AI master prompt is unavailable")
            self._prompt = normalized
            self._loaded_at = now
            return normalized

    def invalidate(self) -> None:
        with self._lock:
            self._prompt = None
            self._loaded_at = 0.0


_ASSET_PATTERN = re.compile(r"^[A-Z0-9._:-]{2,24}$")


def validate_admin_watchlist(symbols: Sequence[str]) -> tuple[str, ...]:
    if isinstance(symbols, (str, bytes)):
        raise AdminConfigurationInvalid("Radar watchlist is invalid")
    try:
        normalized = tuple(symbols)
    except TypeError as exc:
        raise AdminConfigurationInvalid("Radar watchlist is invalid") from exc
    if not 50 <= len(normalized) <= 100:
        raise AdminConfigurationInvalid("Radar watchlist must contain 50-100 assets")
    if len(set(normalized)) != len(normalized):
        raise AdminConfigurationInvalid("Radar watchlist contains duplicates")
    for symbol in normalized:
        if (
            not isinstance(symbol, str)
            or symbol != symbol.strip().upper()
            or _ASSET_PATTERN.fullmatch(symbol) is None
        ):
            raise AdminConfigurationInvalid("Radar watchlist contains an invalid asset")
    return normalized
