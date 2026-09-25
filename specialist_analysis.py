"""Provider-neutral orchestration for the three V2.1 analysis specialists."""

from __future__ import annotations

import asyncio
import json
import re
from math import isfinite
from typing import Any, Awaitable, Callable


SPECIALIST_AGENTS = ("smc", "vsa", "macro")
_OUTPUT_KEYS = {"agent", "decision", "confidence", "reason", "evidence"}
_CORRELATION_ID = re.compile(r"^[A-Za-z0-9._:-]{1,80}$")
_SENSITIVE_KEYS = {
    "account",
    "accountid",
    "accountcontext",
    "apikey",
    "authorization",
    "balance",
    "credential",
    "email",
    "equity",
    "freemargin",
    "password",
    "refreshtoken",
    "riskpercent",
    "secret",
    "suggestedlot",
    "token",
    "uid",
    "userid",
}
_SENSITIVE_KEY_FRAGMENTS = (
    "account",
    "apikey",
    "auth",
    "balance",
    "credential",
    "email",
    "equity",
    "margin",
    "password",
    "secret",
    "suggestedlot",
    "token",
    "userid",
)
_SENSITIVE_TEXT = re.compile(
    r"(?:bearer\s+|api[_-]?key\s*[:=]|password\s*[:=]|secret\s*[:=]|token\s*[:=]|"
    r"[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,})",
    re.IGNORECASE,
)
_COMMON_FEATURE_KEYS = {
    "symbol",
    "timeframe",
    "last_closed_candle_timestamp",
    "current_price",
    "atr",
    "bias",
}
_SPECIALIST_FEATURE_KEYS = {
    "smc": _COMMON_FEATURE_KEYS
    | {
        "structure",
        "swing_highs",
        "swing_lows",
        "order_blocks",
        "fvgs",
        "htf1",
        "htf2",
        "setup_ready",
        "veto",
        "veto_data",
    },
    "vsa": _COMMON_FEATURE_KEYS
    | {
        "volume_baseline",
        "volume_spike",
        "confirmation",
        "candle_overrides",
        "liquidity_markers",
        "wyckoff_phase",
    },
    "macro": _COMMON_FEATURE_KEYS
    | {
        "macro_events",
        "macro_risk_guard",
        "news_sentiment",
        "sentiment",
        "setup_ready",
        "veto",
        "veto_data",
    },
}
_SYSTEM_PROMPTS = {
    "smc": (
        "You are the SMC/ICT specialist. Judge only the supplied structural "
        "feature summary; never infer missing price action."
    ),
    "vsa": (
        "You are the VSA/Wyckoff specialist. Judge only measured volume, spread, "
        "confirmation, and phase evidence in the supplied feature summary."
    ),
    "macro": (
        "You are the Macro/Risk specialist. Judge only supplied fresh event, "
        "sentiment, veto, and risk evidence; missing data means WAIT."
    ),
}


ProviderCall = Callable[..., Awaitable[dict[str, Any]]]
AuditSink = Callable[[dict[str, str]], None]


class SpecialistProviderError(RuntimeError):
    """A provider failure with a closed, non-sensitive classification."""

    _ALLOWED_CODES = {"rate_limited", "payment_required", "unavailable"}

    def __init__(self, code: str, detail: str = "") -> None:
        super().__init__(detail)
        self.code = code if code in self._ALLOWED_CODES else "unavailable"


def _normalized_key(value: Any) -> str:
    return re.sub(r"[^a-z0-9]", "", str(value).lower())


def _is_sensitive_key(value: Any) -> bool:
    normalized = _normalized_key(value)
    return (
        normalized in _SENSITIVE_KEYS
        or normalized.startswith("user")
        or normalized.endswith("uid")
        or normalized.endswith("key")
        or any(fragment in normalized for fragment in _SENSITIVE_KEY_FRAGMENTS)
    )


def _safe_value(value: Any, *, depth: int = 0) -> Any:
    if depth > 5:
        return None
    if value is None or isinstance(value, bool):
        return value
    if isinstance(value, (int, float)) and not isinstance(value, bool):
        return value if isfinite(float(value)) else None
    if isinstance(value, str):
        text = value[:300]
        return "[REDACTED]" if _SENSITIVE_TEXT.search(text) else text
    if isinstance(value, list):
        return [_safe_value(item, depth=depth + 1) for item in value[:12]]
    if isinstance(value, dict):
        result: dict[str, Any] = {}
        for raw_key in sorted(value, key=lambda item: str(item))[:40]:
            key = str(raw_key)
            if _is_sensitive_key(key):
                continue
            result[key] = _safe_value(value[raw_key], depth=depth + 1)
        return result
    return None


def build_specialist_prompt(agent: str, features: dict[str, Any]) -> str:
    """Build a bounded allowlist-only feature prompt without raw candles or PII."""
    if agent not in SPECIALIST_AGENTS:
        raise ValueError("unsupported specialist")
    allowed = _SPECIALIST_FEATURE_KEYS[agent]
    summary = {
        key: _safe_value(features[key])
        for key in sorted(allowed)
        if key in features and not _is_sensitive_key(key)
    }
    summary_json = json.dumps(summary, sort_keys=True, separators=(",", ":"))
    if len(summary_json) > 9_000:
        summary_json = json.dumps(
            {
                key: summary.get(key)
                for key in (
                    "symbol",
                    "timeframe",
                    "last_closed_candle_timestamp",
                    "bias",
                )
                if key in summary
            }
            | {"summary_truncated": True},
            sort_keys=True,
            separators=(",", ":"),
        )
    return (
        f"SPECIALIST: {agent}\n"
        f"FEATURE_SUMMARY_JSON: {summary_json}\n"
        "Return one JSON object with exactly: agent, decision, confidence, "
        "reason, evidence. decision must be BUY, SELL, or WAIT; confidence is "
        "0..100; evidence is a list of compact source references."
    )


def validate_specialist_output(payload: Any, expected_agent: str) -> list[str]:
    """Validate the closed specialist-vote contract."""
    if expected_agent not in SPECIALIST_AGENTS:
        return ["expected agent is invalid"]
    if not isinstance(payload, dict):
        return ["output must be an object"]
    errors: list[str] = []
    if set(payload) != _OUTPUT_KEYS:
        errors.append("output keys are invalid")
    if payload.get("agent") != expected_agent:
        errors.append("agent does not match request")
    if payload.get("decision") not in {"BUY", "SELL", "WAIT"}:
        errors.append("decision is invalid")
    confidence = payload.get("confidence")
    if (
        not isinstance(confidence, (int, float))
        or isinstance(confidence, bool)
        or not isfinite(float(confidence))
        or not 0 <= float(confidence) <= 100
    ):
        errors.append("confidence is invalid")
    reason = payload.get("reason")
    if not isinstance(reason, str) or not reason.strip() or len(reason) > 500:
        errors.append("reason is invalid")
    elif _SENSITIVE_TEXT.search(reason):
        errors.append("reason contains sensitive text")
    evidence = payload.get("evidence")
    if not isinstance(evidence, list) or len(evidence) > 8:
        errors.append("evidence is invalid")
    elif any(
        not isinstance(item, str) or not item.strip() or len(item) > 160
        for item in evidence
    ):
        errors.append("evidence item is invalid")
    elif any(_SENSITIVE_TEXT.search(item) for item in evidence):
        errors.append("evidence contains sensitive text")
    return errors


def _wait_output(agent: str, reason: str) -> dict[str, Any]:
    return {
        "agent": agent,
        "decision": "WAIT",
        "confidence": 0.0,
        "reason": reason,
        "evidence": [],
    }


async def run_specialist_analysis(
    features: dict[str, Any],
    *,
    provider: ProviderCall,
    correlation_id: str,
    timeout_seconds: float = 15.0,
    audit_sink: AuditSink | None = None,
    model: str = "deepseek-chat",
) -> dict[str, Any]:
    """Run the three independent specialists concurrently and fail closed."""
    if not isinstance(features, dict):
        raise TypeError("features must be an object")
    if _CORRELATION_ID.fullmatch(correlation_id) is None:
        raise ValueError("correlation_id must be opaque and bounded")
    if (
        not isinstance(timeout_seconds, (int, float))
        or isinstance(timeout_seconds, bool)
        or not isfinite(float(timeout_seconds))
        or not 0 < float(timeout_seconds) <= 60
    ):
        raise ValueError("timeout_seconds must be within 0..60")

    async def run_one(agent: str) -> tuple[dict[str, Any], bool]:
        outcome = "success"
        success = False
        try:
            response = await asyncio.wait_for(
                provider(
                    agent=agent,
                    model=model,
                    messages=[
                        {"role": "system", "content": _SYSTEM_PROMPTS[agent]},
                        {
                            "role": "user",
                            "content": build_specialist_prompt(agent, features),
                        },
                    ],
                    response_format={"type": "json_object"},
                    temperature=0.0,
                    correlation_id=correlation_id,
                ),
                timeout=float(timeout_seconds),
            )
            errors = validate_specialist_output(response, agent)
            if errors:
                outcome = "invalid_response"
                output = _wait_output(agent, outcome)
            else:
                output = {
                    "agent": agent,
                    "decision": response["decision"],
                    "confidence": float(response["confidence"]),
                    "reason": response["reason"].strip(),
                    "evidence": list(response["evidence"]),
                }
                success = True
        except asyncio.TimeoutError:
            outcome = "timeout"
            output = _wait_output(agent, "provider_timeout")
        except SpecialistProviderError as exc:
            outcome = exc.code
            output = _wait_output(agent, f"provider_{exc.code}")
        except Exception:
            outcome = "unavailable"
            output = _wait_output(agent, "provider_unavailable")

        if audit_sink is not None:
            audit_sink(
                {
                    "correlation_id": correlation_id,
                    "agent": agent,
                    "outcome": outcome,
                }
            )
        return output, success

    results = await asyncio.gather(*(run_one(agent) for agent in SPECIALIST_AGENTS))
    return {
        "complete": all(success for _, success in results),
        "outputs": [output for output, _ in results],
    }
