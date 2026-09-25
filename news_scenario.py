"""Pure contract for the V2.1 News What-If workflow.

The contract is deliberately separate from generic chat and cannot represent an
order. HTTP, authentication and persistence remain boundary concerns.
"""

from __future__ import annotations

from dataclasses import dataclass
from hashlib import sha256
import re
from typing import Any, Mapping, Optional, Sequence


WORKFLOW = "news_what_if"
_IDENTITY_KEYS = frozenset({"userId", "user_id", "uid"})
_TRADE_KEYS = frozenset(
    {
        "entry",
        "entryprice",
        "sl",
        "stoploss",
        "tp",
        "takeprofit",
        "volume",
        "lot",
        "execute",
        "execution",
        "order",
        "tradeaction",
    }
)


@dataclass(frozen=True)
class ScenarioContractResult:
    value: Optional[dict[str, Any]]
    error: Optional[str] = None


def _text(value: Any, *, max_length: int = 2_000) -> Optional[str]:
    if not isinstance(value, str):
        return None
    normalized = value.strip()
    if not normalized or len(normalized) > max_length:
        return None
    return normalized


def _assets(value: Any) -> list[str]:
    if not isinstance(value, (list, tuple, set)):
        return []
    return sorted(
        {
            item.strip().upper()
            for item in value
            if isinstance(item, str)
            and 3 <= len(item.strip()) <= 20
            and item.strip().isalnum()
        }
    )


def _text_list(value: Any, *, allow_empty: bool = False) -> Optional[list[str]]:
    if not isinstance(value, (list, tuple)):
        return None
    normalized: list[str] = []
    for item in value:
        parsed = _text(item, max_length=500)
        if parsed is None:
            return None
        normalized.append(parsed)
    if not normalized and not allow_empty:
        return None
    return normalized


def _normalized_key(value: Any) -> str:
    return re.sub(r"[^a-z0-9]", "", str(value).lower())


def contains_trade_instruction(value: Any) -> bool:
    if isinstance(value, Mapping):
        for key, child in value.items():
            if _normalized_key(key) in _TRADE_KEYS:
                return True
            if contains_trade_instruction(child):
                return True
    elif isinstance(value, (list, tuple)):
        return any(contains_trade_instruction(child) for child in value)
    return False


def normalize_scenario_request(raw: Mapping[str, Any]) -> ScenarioContractResult:
    if any(key in raw for key in _IDENTITY_KEYS):
        return ScenarioContractResult(None, "identity_must_come_from_token")
    if raw.get("workflow") != WORKFLOW:
        return ScenarioContractResult(None, "invalid_workflow")
    if contains_trade_instruction(raw):
        return ScenarioContractResult(None, "trade_instruction_forbidden")

    event_id = _text(raw.get("event_id"), max_length=200)
    question = _text(raw.get("question"), max_length=1_000)
    if event_id is None or question is None:
        return ScenarioContractResult(None, "invalid_request_text")

    locale = raw.get("locale", "en")
    if locale not in ("en", "vi"):
        return ScenarioContractResult(None, "unsupported_locale")
    save_requested = raw.get("save_requested", False)
    if not isinstance(save_requested, bool):
        return ScenarioContractResult(None, "invalid_save_requested")

    return ScenarioContractResult(
        {
            "workflow": WORKFLOW,
            "event_id": event_id,
            "question": question,
            "locale": locale,
            "save_requested": save_requested,
            "affected_assets": _assets(raw.get("affected_assets", [])),
        }
    )


def _normalize_path(value: Any, *, fallback: bool) -> Optional[dict[str, list[str]]]:
    if not isinstance(value, Mapping):
        return None
    conditions = _text_list(value.get("conditions"), allow_empty=fallback)
    reactions = _text_list(
        value.get("projected_reactions"),
        allow_empty=fallback,
    )
    if conditions is None or reactions is None:
        return None
    return {"conditions": conditions, "projected_reactions": reactions}


def normalize_scenario_response(raw: Mapping[str, Any]) -> ScenarioContractResult:
    if contains_trade_instruction(raw):
        return ScenarioContractResult(None, "trade_instruction_forbidden")

    fallback = raw.get("fallback")
    if not isinstance(fallback, bool):
        return ScenarioContractResult(None, "invalid_fallback_state")

    scenario_id = _text(raw.get("scenario_id"), max_length=200)
    assumptions = _text_list(raw.get("assumptions"), allow_empty=fallback)
    affected_assets = _assets(raw.get("affected_assets"))
    bullish_path = _normalize_path(raw.get("bullish_path"), fallback=fallback)
    bearish_path = _normalize_path(raw.get("bearish_path"), fallback=fallback)
    invalidation = _text_list(raw.get("invalidation"), allow_empty=fallback)
    risk_notice = _text(raw.get("risk_notice"), max_length=1_000)
    if (
        scenario_id is None
        or assumptions is None
        or not affected_assets
        or bullish_path is None
        or bearish_path is None
        or invalidation is None
        or risk_notice is None
    ):
        return ScenarioContractResult(None, "invalid_response_shape")

    return ScenarioContractResult(
        {
            "scenario_id": scenario_id,
            "assumptions": assumptions,
            "affected_assets": affected_assets,
            "bullish_path": bullish_path,
            "bearish_path": bearish_path,
            "invalidation": invalidation,
            "risk_notice": risk_notice,
            "fallback": fallback,
        }
    )


def build_scenario_fallback(
    *,
    event_id: str,
    question: str,
    affected_assets: Sequence[str],
    failure_kind: str,
) -> dict[str, Any]:
    """Build one provider-neutral fallback without exposing failure details."""

    del failure_kind
    normalized_assets = _assets(affected_assets) or ["MARKET"]
    scenario_id = sha256(f"{event_id}:{question}".encode("utf-8")).hexdigest()
    return {
        "scenario_id": scenario_id,
        "assumptions": [],
        "affected_assets": normalized_assets,
        "bullish_path": {"conditions": [], "projected_reactions": []},
        "bearish_path": {"conditions": [], "projected_reactions": []},
        "invalidation": [],
        "risk_notice": (
            "Scenario analysis is temporarily unavailable. Do not make a trade "
            "decision from this fallback; review verified market data and risk."
        ),
        "fallback": True,
    }
