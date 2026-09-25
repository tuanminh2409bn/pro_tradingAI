import unittest

from news_scenario import (
    build_scenario_fallback,
    contains_trade_instruction,
    normalize_scenario_request,
    normalize_scenario_response,
)


class NewsScenarioContractTests(unittest.TestCase):
    def test_request_is_distinct_from_chat_and_carries_no_user_identity(self):
        accepted = normalize_scenario_request(
            {
                "workflow": "news_what_if",
                "event_id": "calendar:event-1",
                "question": "What if CPI is above consensus?",
                "locale": "en",
                "save_requested": True,
                "affected_assets": ["xauusd", "EURUSD"],
            }
        )
        generic_chat = normalize_scenario_request(
            {
                "workflow": "chat",
                "event_id": "calendar:event-1",
                "question": "What if CPI is above consensus?",
            }
        )
        spoofed_identity = normalize_scenario_request(
            {
                "workflow": "news_what_if",
                "event_id": "calendar:event-1",
                "question": "What if CPI is above consensus?",
                "userId": "attacker-controlled",
            }
        )

        self.assertIsNotNone(accepted.value)
        self.assertEqual(accepted.value["affected_assets"], ["EURUSD", "XAUUSD"])
        self.assertEqual(generic_chat.error, "invalid_workflow")
        self.assertEqual(spoofed_identity.error, "identity_must_come_from_token")

    def test_structured_response_contains_every_required_section(self):
        result = normalize_scenario_response(
            {
                "scenario_id": "scenario-1",
                "assumptions": ["CPI prints above consensus"],
                "affected_assets": ["XAUUSD", "EURUSD"],
                "bullish_path": {
                    "conditions": ["USD selling follows the release"],
                    "projected_reactions": ["XAUUSD volatility may expand"],
                },
                "bearish_path": {
                    "conditions": ["USD demand strengthens"],
                    "projected_reactions": ["XAUUSD may reject resistance"],
                },
                "invalidation": ["Release is revised or liquidity is abnormal"],
                "risk_notice": "Scenario only; it cannot place an order.",
                "fallback": False,
            }
        )

        self.assertIsNone(result.error)
        self.assertEqual(result.value["scenario_id"], "scenario-1")
        self.assertFalse(contains_trade_instruction(result.value))

    def test_response_rejects_direct_or_nested_trade_instructions(self):
        direct = normalize_scenario_response(
            {
                "scenario_id": "scenario-1",
                "assumptions": ["Measured assumption"],
                "affected_assets": ["XAUUSD"],
                "bullish_path": {
                    "conditions": ["Condition"],
                    "projected_reactions": ["Reaction"],
                },
                "bearish_path": {
                    "conditions": ["Condition"],
                    "projected_reactions": ["Reaction"],
                },
                "invalidation": ["Invalidation"],
                "risk_notice": "Scenario only.",
                "fallback": False,
                "entryPrice": 2400,
            }
        )
        nested = normalize_scenario_response(
            {
                "scenario_id": "scenario-2",
                "assumptions": ["Measured assumption"],
                "affected_assets": ["XAUUSD"],
                "bullish_path": {
                    "conditions": ["Condition"],
                    "projected_reactions": [{"execute": "BUY"}],
                },
                "bearish_path": {
                    "conditions": ["Condition"],
                    "projected_reactions": ["Reaction"],
                },
                "invalidation": ["Invalidation"],
                "risk_notice": "Scenario only.",
                "fallback": False,
            }
        )

        self.assertEqual(direct.error, "trade_instruction_forbidden")
        self.assertEqual(nested.error, "trade_instruction_forbidden")

    def test_402_429_and_timeout_share_one_safe_structured_fallback(self):
        outputs = [
            build_scenario_fallback(
                event_id="calendar:event-1",
                question="What if CPI surprises?",
                affected_assets=["XAUUSD"],
                failure_kind=failure,
            )
            for failure in ("http_402", "http_429", "timeout")
        ]

        self.assertEqual(outputs[0], outputs[1])
        self.assertEqual(outputs[1], outputs[2])
        self.assertTrue(outputs[0]["fallback"])
        self.assertFalse(contains_trade_instruction(outputs[0]))
        self.assertNotIn("402", str(outputs[0]))
        self.assertNotIn("429", str(outputs[0]))


if __name__ == "__main__":
    unittest.main()
