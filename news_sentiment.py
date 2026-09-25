"""Pure V2.1 news normalization.

This module intentionally owns no network or Firestore I/O. Provider adapters must
pass explicit approval and license metadata before an item can be normalized.
"""

from __future__ import annotations

from dataclasses import dataclass
from hashlib import sha256
from math import isfinite
from typing import Any, Iterable, Mapping, Optional


SENTIMENT_BULLISH_MIN = 25
SENTIMENT_BEARISH_MAX = -25
SCORE_METHOD = "(positive_mentions-negative_mentions)/total_mentions*100"
APPROVED_PROVIDER_TYPES = frozenset({"calendar", "x"})


@dataclass(frozen=True)
class NewsNormalizationResult:
    item: Optional[dict[str, Any]]
    rejection_reason: Optional[str] = None


def _non_empty_string(value: Any) -> Optional[str]:
    if not isinstance(value, str):
        return None
    normalized = value.strip()
    return normalized or None


def _non_negative_count(value: Any) -> Optional[int]:
    if isinstance(value, bool) or not isinstance(value, (int, float)):
        return None
    if not isfinite(float(value)) or value < 0 or int(value) != value:
        return None
    return int(value)


def _normalized_codes(value: Any, *, min_length: int, max_length: int) -> list[str]:
    if not isinstance(value, (list, tuple, set)):
        return []
    codes = {
        code.strip().upper()
        for code in value
        if isinstance(code, str)
        and min_length <= len(code.strip()) <= max_length
        and code.strip().isalnum()
    }
    return sorted(codes)


def classify_sentiment(score: int) -> str:
    if score >= SENTIMENT_BULLISH_MIN:
        return "BULLISH"
    if score <= SENTIMENT_BEARISH_MAX:
        return "BEARISH"
    return "NEUTRAL"


def score_mentions(positive: int, negative: int, neutral: int) -> Optional[int]:
    total = positive + negative + neutral
    if total <= 0:
        return None
    score = round(((positive - negative) / total) * 100)
    return max(-100, min(100, int(score)))


def normalize_news_item(
    raw: Mapping[str, Any],
    *,
    now_epoch_seconds: int,
    max_age_seconds: int = 3_600,
) -> NewsNormalizationResult:
    """Validate and normalize one approved provider item, failing closed."""

    if raw.get("license_status") != "approved":
        return NewsNormalizationResult(None, "source_not_approved")

    license_ref = _non_empty_string(raw.get("license_ref"))
    if license_ref is None:
        return NewsNormalizationResult(None, "missing_license_ref")

    provider = _non_empty_string(raw.get("provider"))
    provider_type = _non_empty_string(raw.get("provider_type"))
    provider_event_id = _non_empty_string(raw.get("provider_event_id"))
    if provider is None or provider_event_id is None:
        return NewsNormalizationResult(None, "missing_source_identity")
    if provider_type not in APPROVED_PROVIDER_TYPES:
        return NewsNormalizationResult(None, "unsupported_provider_type")

    title = _non_empty_string(raw.get("title"))
    if title is None:
        return NewsNormalizationResult(None, "missing_title")

    published_at = raw.get("published_at")
    if (
        isinstance(published_at, bool)
        or not isinstance(published_at, (int, float))
        or not isfinite(float(published_at))
        or int(published_at) != published_at
        or published_at <= 0
        or published_at > now_epoch_seconds + 300
    ):
        return NewsNormalizationResult(None, "invalid_published_at")
    published_at = int(published_at)
    age_seconds = max(0, now_epoch_seconds - published_at)
    if max_age_seconds <= 0 or age_seconds > max_age_seconds:
        return NewsNormalizationResult(None, "stale")

    positive = _non_negative_count(raw.get("positive_mentions"))
    negative = _non_negative_count(raw.get("negative_mentions"))
    neutral = _non_negative_count(raw.get("neutral_mentions"))
    if positive is None or negative is None or neutral is None:
        return NewsNormalizationResult(None, "invalid_mention_counts")
    score = score_mentions(positive, negative, neutral)
    if score is None:
        return NewsNormalizationResult(None, "sentiment_unavailable")

    currencies = _normalized_codes(raw.get("currencies"), min_length=3, max_length=3)
    symbols = _normalized_codes(raw.get("symbols"), min_length=6, max_length=12)
    event_id = sha256(f"{provider}:{provider_event_id}".encode("utf-8")).hexdigest()

    return NewsNormalizationResult(
        {
            "id": event_id,
            "provider_event_id": provider_event_id,
            "title": title,
            "summary": _non_empty_string(raw.get("summary")) or "",
            "impact": (_non_empty_string(raw.get("impact")) or "LOW").upper(),
            "currencies": currencies,
            "symbols": symbols,
            "published_at": published_at,
            "sentiment_score": score,
            "sentiment_class": classify_sentiment(score),
            "score_method": SCORE_METHOD,
            "mention_counts": {
                "positive": positive,
                "negative": negative,
                "neutral": neutral,
            },
            "source": {
                "provider": provider,
                "provider_type": provider_type,
                "license_status": "approved",
                "license_ref": license_ref,
            },
            "freshness": {
                "status": "fresh",
                "observed_at": now_epoch_seconds,
                "age_seconds": age_seconds,
                "max_age_seconds": max_age_seconds,
            },
        }
    )


def deduplicate_news(items: Iterable[Mapping[str, Any]]) -> list[dict[str, Any]]:
    """Keep the newest normalized record for each provider event identity."""

    selected: dict[tuple[str, str], dict[str, Any]] = {}
    for item in items:
        source = item.get("source")
        if not isinstance(source, Mapping):
            continue
        provider = _non_empty_string(source.get("provider"))
        provider_event_id = _non_empty_string(item.get("provider_event_id"))
        published_at = item.get("published_at")
        if (
            provider is None
            or provider_event_id is None
            or isinstance(published_at, bool)
            or not isinstance(published_at, int)
        ):
            continue
        key = (provider, provider_event_id)
        current = selected.get(key)
        if current is None or published_at > current["published_at"]:
            selected[key] = dict(item)

    return sorted(
        selected.values(),
        key=lambda item: (-item["published_at"], item["id"]),
    )


def aggregate_sentiment(items: Iterable[Mapping[str, Any]]) -> dict[str, Any]:
    """Return a mention-weighted pulse or explicit unavailable state."""

    positive = negative = neutral = 0
    article_count = 0
    for item in items:
        counts = item.get("mention_counts")
        if not isinstance(counts, Mapping):
            continue
        values = tuple(
            _non_negative_count(counts.get(name))
            for name in ("positive", "negative", "neutral")
        )
        if any(value is None for value in values):
            continue
        item_positive, item_negative, item_neutral = values
        positive += item_positive
        negative += item_negative
        neutral += item_neutral
        article_count += 1

    score = score_mentions(positive, negative, neutral)
    if score is None or article_count == 0:
        return {"status": "unavailable", "score": None, "article_count": 0}
    return {
        "status": "available",
        "score": score,
        "classification": classify_sentiment(score),
        "article_count": article_count,
        "mention_counts": {
            "positive": positive,
            "negative": negative,
            "neutral": neutral,
        },
        "score_method": SCORE_METHOD,
    }
