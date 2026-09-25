"""Pure daily-loss policy used by the authenticated paper-trade boundary."""

from __future__ import annotations

from dataclasses import dataclass
from math import isfinite


class DailyLossPolicyError(ValueError):
    pass


@dataclass(frozen=True)
class DailyLossDecision:
    realized_pnl: float
    floating_pnl: float
    total_pnl: float
    loss_limit: float
    blocked: bool


def evaluate_daily_loss(
    *,
    balance: float,
    max_daily_loss_percent: float,
    realized_pnl: float,
    floating_pnl: float,
) -> DailyLossDecision:
    """Return a deterministic cutoff decision from authoritative values."""
    values = (balance, max_daily_loss_percent, realized_pnl, floating_pnl)
    if not all(isfinite(float(value)) for value in values):
        raise DailyLossPolicyError("Daily-loss inputs must be finite")
    if balance <= 0:
        raise DailyLossPolicyError("Balance must be positive")
    if max_daily_loss_percent <= 0 or max_daily_loss_percent > 100:
        raise DailyLossPolicyError("Daily-loss percent is out of range")

    realized = float(realized_pnl)
    floating = float(floating_pnl)
    total = realized + floating
    limit = float(balance) * float(max_daily_loss_percent) / 100.0
    return DailyLossDecision(
        realized_pnl=realized,
        floating_pnl=floating,
        total_pnl=total,
        loss_limit=limit,
        blocked=total <= -limit,
    )
