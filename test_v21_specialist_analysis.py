"""Provider-independent T16 specialist orchestration tests."""

from __future__ import annotations

import asyncio
import unittest

from specialist_analysis import (
    SpecialistProviderError,
    run_specialist_analysis,
    validate_specialist_output,
)


class RecordingProvider:
    def __init__(self, responses=None):
        self.calls = []
        self.responses = responses or {}

    async def __call__(self, **kwargs):
        self.calls.append(kwargs)
        response = self.responses.get(kwargs["agent"])
        if isinstance(response, BaseException):
            raise response
        return response or {
            "agent": kwargs["agent"],
            "decision": "WAIT",
            "confidence": 50,
            "reason": f"{kwargs['agent']} evidence is inconclusive",
            "evidence": [f"{kwargs['agent']}:fixture"],
        }


class SpecialistAnalysisTests(unittest.IsolatedAsyncioTestCase):
    async def test_calls_exactly_three_specialists_with_safe_bounded_prompts(self):
        provider = RecordingProvider()
        audits = []
        result = await run_specialist_analysis(
            {
                "symbol": "XAUUSD",
                "timeframe": "5",
                "last_closed_candle_timestamp": 1_700_000_000,
                "current_price": 2300.5,
                "atr": 4.2,
                "bias": "BUY",
                "structure": {
                    "trend": "Bullish",
                    "brokerAccountId": "private-account",
                    "ownerUid": "private-owner",
                    "note": "token=nested-secret",
                },
                "volume_baseline": 1000,
                "volume_spike": True,
                "macro_risk_guard": {"available": True, "veto": False},
                "candles_execution": [{"o": 1, "h": 2, "l": 0, "c": 1.5}],
                "userId": "private-user",
                "equity": 50_000,
                "token": "secret-token",
            },
            provider=provider,
            correlation_id="analysis-1700000000",
            audit_sink=audits.append,
        )

        self.assertEqual([call["agent"] for call in provider.calls], ["smc", "vsa", "macro"])
        self.assertTrue(result["complete"])
        self.assertEqual(len(result["outputs"]), 3)
        self.assertEqual(len(audits), 3)
        for call in provider.calls:
            self.assertEqual(call["temperature"], 0.0)
            self.assertEqual(call["response_format"], {"type": "json_object"})
            prompt = call["messages"][1]["content"]
            self.assertLessEqual(len(prompt), 12_000)
            self.assertNotIn("candles_execution", prompt)
            self.assertNotIn("private-user", prompt)
            self.assertNotIn("50000", prompt)
            self.assertNotIn("secret-token", prompt)
            self.assertNotIn("private-account", prompt)
            self.assertNotIn("private-owner", prompt)
            self.assertNotIn("nested-secret", prompt)
        self.assertEqual(
            {tuple(sorted(audit.keys())) for audit in audits},
            {("agent", "correlation_id", "outcome")},
        )

    async def test_timeout_and_provider_statuses_fail_closed_without_leaking_errors(self):
        async def provider(**kwargs):
            if kwargs["agent"] == "smc":
                await asyncio.sleep(0.05)
            if kwargs["agent"] == "vsa":
                raise SpecialistProviderError("rate_limited", "token=do-not-log")
            if kwargs["agent"] == "macro":
                raise SpecialistProviderError("payment_required", "key=do-not-log")

        audits = []
        result = await run_specialist_analysis(
            {"symbol": "EURUSD", "timeframe": "15"},
            provider=provider,
            correlation_id="corr-safe-1",
            timeout_seconds=0.01,
            audit_sink=audits.append,
        )

        self.assertFalse(result["complete"])
        self.assertEqual([item["decision"] for item in result["outputs"]], ["WAIT"] * 3)
        self.assertEqual(
            [item["reason"] for item in result["outputs"]],
            ["provider_timeout", "provider_rate_limited", "provider_payment_required"],
        )
        serialized = repr({"result": result, "audits": audits})
        self.assertNotIn("do-not-log", serialized)
        self.assertNotIn("token=", serialized)
        self.assertNotIn("key=", serialized)

    async def test_malformed_or_cross_agent_output_is_replaced_by_wait(self):
        provider = RecordingProvider(
            {
                "smc": {
                    "agent": "macro",
                    "decision": "BUY",
                    "confidence": 90,
                    "reason": "wrong agent",
                    "evidence": ["fixture"],
                },
                "vsa": "not-json",
            }
        )
        result = await run_specialist_analysis(
            {"symbol": "XAUUSD", "timeframe": "5"},
            provider=provider,
            correlation_id="corr-safe-2",
        )

        self.assertFalse(result["complete"])
        self.assertEqual(result["outputs"][0]["reason"], "invalid_response")
        self.assertEqual(result["outputs"][1]["reason"], "invalid_response")
        self.assertEqual(result["outputs"][2]["agent"], "macro")

    def test_closed_output_schema_rejects_unknown_or_unsafe_values(self):
        valid = {
            "agent": "smc",
            "decision": "SELL",
            "confidence": 75,
            "reason": "bearish break of structure",
            "evidence": ["structure:BOS:1700000000"],
        }
        self.assertEqual(validate_specialist_output(valid, "smc"), [])
        self.assertTrue(validate_specialist_output({**valid, "raw_prompt": "secret"}, "smc"))
        self.assertTrue(validate_specialist_output({**valid, "confidence": 101}, "smc"))
        self.assertTrue(validate_specialist_output({**valid, "decision": "MOON"}, "smc"))
        self.assertTrue(
            validate_specialist_output(
                {**valid, "reason": "provider token=must-not-survive"}, "smc"
            )
        )


if __name__ == "__main__":
    unittest.main()
