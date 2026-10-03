"""Auditable three-specialist consensus tests for V2.1."""

from __future__ import annotations

import unittest

from feature_engine import aggregate_specialist_votes, evaluate_setup_and_veto


class ConsensusTests(unittest.TestCase):
    def test_unanimous_vote_reaches_threshold(self):
        result = aggregate_specialist_votes(
            [
                {"agent": "smc", "decision": "BUY", "confidence": 80, "reason": "structure"},
                {"agent": "vsa", "decision": "BUY", "confidence": 75, "reason": "volume"},
                {"agent": "macro", "decision": "BUY", "confidence": 90, "reason": "risk clear"},
            ]
        )
        self.assertTrue(result["complete"])
        self.assertEqual(result["decision"], "BUY")
        self.assertEqual(result["agreement_percent"], 100.0)

    def test_vote_audit_retains_only_compact_evidence_references(self):
        result = aggregate_specialist_votes(
            [
                {
                    "agent": "smc",
                    "decision": "BUY",
                    "confidence": 80,
                    "reason": "structure",
                    "evidence": ["structure:BOS:1700000000", "invalid evidence with spaces"],
                },
                {
                    "agent": "vsa",
                    "decision": "BUY",
                    "confidence": 80,
                    "reason": "volume",
                    "evidence": ["vsa:climax:1700000000"],
                },
                {
                    "agent": "macro",
                    "decision": "BUY",
                    "confidence": 80,
                    "reason": "risk clear",
                    "evidence": ["macro:event-1:1700000000"],
                },
            ]
        )
        self.assertEqual(
            result["votes"][0]["evidence"], ["structure:BOS:1700000000"]
        )

    def test_two_of_three_stays_below_75_percent(self):
        result = aggregate_specialist_votes(
            [
                {"agent": "smc", "decision": "SELL", "confidence": 90, "reason": "structure"},
                {"agent": "vsa", "decision": "SELL", "confidence": 90, "reason": "volume"},
                {"agent": "macro", "decision": "WAIT", "confidence": 20, "reason": "event"},
            ]
        )
        self.assertEqual(result["decision"], "WAIT")
        self.assertEqual(result["leading_direction"], "SELL")
        self.assertEqual(result["agreement_percent"], 66.67)

    def test_malformed_or_missing_votes_fail_closed(self):
        result = aggregate_specialist_votes(
            [{"agent": "smc", "decision": "MOON", "confidence": 500}]
        )
        self.assertFalse(result["complete"])
        self.assertEqual(result["decision"], "WAIT")
        self.assertEqual(result["votes"][0]["decision"], "WAIT")

    def test_consensus_direction_must_match_execution_bias(self):
        result = evaluate_setup_and_veto(
            {
                "current_price": 100,
                "atr": 1,
                "bias": "BUY",
                "order_blocks": [{"bias": "bullish", "top": 101, "bottom": 99}],
                "confirmation": {
                    "type": "bullish_engulfing",
                    "candle_time": 1_700_000_000,
                },
                "specialist_outputs": [
                    {"agent": name, "decision": "SELL", "confidence": 90, "reason": "x"}
                    for name in ("smc", "vsa", "macro")
                ],
            }
        )
        self.assertFalse(result["consensus_ready"])
        self.assertFalse(result["setup_ready"])

    def test_hard_setup_requires_and_returns_confirmation_evidence(self):
        features = {
            "current_price": 100,
            "atr": 1,
            "bias": "BUY",
            "order_blocks": [{"bias": "bullish", "top": 101, "bottom": 99}],
            "confirmation": {
                "type": "bullish_engulfing",
                "candle_time": 1_700_000_000,
            },
            "specialist_outputs": [
                {
                    "agent": name,
                    "decision": "BUY",
                    "confidence": 90,
                    "reason": "measured evidence",
                    "evidence": [f"{name}:fixture:1700000000"],
                }
                for name in ("smc", "vsa", "macro")
            ],
        }
        first = evaluate_setup_and_veto(features)
        second = evaluate_setup_and_veto(features)
        self.assertTrue(first["setup_ready"])
        self.assertEqual(first["final_decision"], "HARD_SETUP")
        self.assertEqual(
            first["confirmation_evidence"],
            {"type": "bullish_engulfing", "candle_time": 1_700_000_000},
        )
        self.assertEqual(first, second)

    def test_confirmation_without_candle_timestamp_stays_soft(self):
        result = evaluate_setup_and_veto(
            {
                "current_price": 100,
                "atr": 1,
                "bias": "BUY",
                "order_blocks": [{"bias": "bullish", "top": 101, "bottom": 99}],
                "confirmation": {"type": "bullish_engulfing"},
                "specialist_outputs": [
                    {
                        "agent": name,
                        "decision": "BUY",
                        "confidence": 90,
                        "reason": "measured evidence",
                    }
                    for name in ("smc", "vsa", "macro")
                ],
            }
        )
        self.assertFalse(result["confirmation_ready"])
        self.assertFalse(result["setup_ready"])
        self.assertEqual(result["final_decision"], "SOFT_ALERT")


if __name__ == "__main__":
    unittest.main()
