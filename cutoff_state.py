"""UTC daily-loss latch policy shared by backend transaction boundaries."""

from __future__ import annotations

from datetime import date, datetime, timezone
from typing import Mapping


def utc_session(now: datetime) -> str:
    if now.tzinfo is None or now.utcoffset() is None:
        raise ValueError("Cutoff clock must be timezone-aware")
    return now.astimezone(timezone.utc).date().isoformat()


def cutoff_active(state: Mapping | None, now: datetime) -> bool:
    """A tripped latch needs review, acknowledgement and a later UTC day."""
    if not state or state.get("active") is not True:
        return False
    session = state.get("sessionDate")
    try:
        session_date = date.fromisoformat(session)
        if session_date.isoformat() != session:
            return True
    except (TypeError, ValueError):
        return True
    if session_date >= date.fromisoformat(utc_session(now)):
        return True
    return not (state.get("reviewedAt") and state.get("acknowledgedAt"))
