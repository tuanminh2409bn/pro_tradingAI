"""Opaque referral identity; no rewards or monetary policy is inferred here."""
import re
import secrets

REFERRAL_ORIGIN = "https://protrading-ai-2026.web.app/"


class ReferralCodeCollision(Exception):
    pass


def new_referral_code() -> str:
    return secrets.token_urlsafe(18)


def canonical_referral_link(code: str) -> str:
    if not isinstance(code, str) or not re.fullmatch(r"[A-Za-z0-9_-]{24}", code):
        raise ValueError("Invalid referral code")
    return REFERRAL_ORIGIN + "?ref=" + code


def eligible_registration(user_created_ms: int, inviter_created_ms: int, now_ms: int) -> bool:
    for value in (user_created_ms, inviter_created_ms, now_ms):
        if not isinstance(value, int) or isinstance(value, bool) or value < 0:
            raise ValueError("Registration time unavailable")
    return inviter_created_ms < user_created_ms and 0 <= now_ms - user_created_ms <= 86_400_000
