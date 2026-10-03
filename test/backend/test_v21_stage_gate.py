"""V2.1 two-stage safety contract."""

from __future__ import annotations

import unittest

from feature_engine import (
    apply_stage_gates,
    evaluate_setup_and_veto,
    is_executable_signal,
)


class StageGateSafetyTests(unittest.TestCase):
    def test_touching_zone_without_confirmation_stays_soft(self):
        features = {
            "current_price": 100.0,
            "atr": 1.0,
            "bias": "BUY",
            "order_blocks": [
                {"bias": "bullish", "top": 100.2, "bottom": 99.8}
            ],
            "fvgs": [],
            "confirmation": None,
            "consensus_percent": 100,
        }

        result = evaluate_setup_and_veto(features)

        self.assertFalse(result["setup_ready"])
        self.assertTrue(result["zone_touched"])
        self.assertFalse(result["confirmation_ready"])

    def test_touch_confirmation_and_consensus_make_hard_setup(self):
        features = {
            "current_price": 100.0,
            "atr": 1.0,
            "bias": "BUY",
            "order_blocks": [
                {"bias": "bullish", "top": 100.2, "bottom": 99.8}
            ],
            "fvgs": [],
            "confirmation": {"type": "bullish_engulfing", "t": 123},
            "consensus_percent": 75,
        }

        result = evaluate_setup_and_veto(features)

        self.assertTrue(result["setup_ready"])
        self.assertTrue(result["zone_touched"])
        self.assertTrue(result["confirmation_ready"])
        self.assertTrue(result["consensus_ready"])

    def test_soft_signal_removes_all_executable_values(self):
        raw = {
            "type": "BUY",
            "entryPrice": 2400.0,
            "slPrice": 2390.0,
            "tpPrices": [2420.0, 2430.0, 2440.0],
            "suggestedLot": 0.4,
            "layers": [
                {"layer": 1, "items": []},
                {"layer": 4, "entry_line": {"price": 2400.0}},
            ],
        }

        result = apply_stage_gates(
            raw,
            {"setup_ready": False, "veto": False, "veto_data": None},
        )

        self.assertFalse(result["setup_ready"])
        self.assertIsNone(result["entryPrice"])
        self.assertIsNone(result["slPrice"])
        self.assertEqual(result["tpPrices"], [])
        self.assertIsNone(result["suggestedLot"])
        self.assertTrue(
            all(layer.get("layer") != 4 for layer in result["layers"])
        )

    def test_veto_signal_removes_all_executable_values(self):
        raw = {
            "type": "SELL",
            "entryPrice": 1.1,
            "slPrice": 1.2,
            "tpPrices": [1.0],
            "layers": [{"layer": 4}],
        }

        result = apply_stage_gates(
            raw,
            {
                "setup_ready": True,
                "veto": True,
                "veto_data": {"reason": "htf_conflict"},
            },
        )

        self.assertFalse(result["setup_ready"])
        self.assertTrue(result["veto"])
        self.assertIsNone(result["entryPrice"])
        self.assertIsNone(result["slPrice"])
        self.assertEqual(result["tpPrices"], [])

    def test_hard_signal_preserves_executable_values(self):
        raw = {
            "type": "BUY",
            "entryPrice": 2400.0,
            "slPrice": 2390.0,
            "tpPrices": [2420.0],
            "suggestedLot": 0.2,
            "layers": [{"layer": 4}],
        }

        result = apply_stage_gates(
            raw,
            {"setup_ready": True, "veto": False, "veto_data": None},
        )

        self.assertTrue(result["setup_ready"])
        self.assertEqual(result["entryPrice"], 2400.0)
        self.assertEqual(result["slPrice"], 2390.0)
        self.assertEqual(result["tpPrices"], [2420.0])

    def test_execution_alert_requires_complete_hard_signal(self):
        self.assertTrue(
            is_executable_signal(
                {
                    "setup_ready": True,
                    "veto": False,
                    "type": "BUY",
                    "entryPrice": 2400.0,
                    "slPrice": 2390.0,
                    "tpPrices": [2420.0, 2430.0, 2440.0],
                }
            )
        )
        self.assertFalse(
            is_executable_signal(
                {
                    "setup_ready": False,
                    "veto": False,
                    "type": "BUY",
                    "entryPrice": 2400.0,
                    "slPrice": 2390.0,
                    "tpPrices": [2420.0],
                }
            )
        )

    def test_unvalidated_htf_history_cannot_trigger_veto(self):
        result = evaluate_setup_and_veto(
            {
                "current_price": 100,
                "atr": 1,
                "bias": "BUY",
                "order_blocks": [],
            },
            {
                "timeframe": "H4",
                "history_valid": False,
                "order_blocks": [{"bias": "bearish", "top": 101, "bottom": 99}],
            },
        )
        self.assertFalse(result["veto"])

    def test_validated_opposing_htf_zone_triggers_auditable_veto(self):
        result = evaluate_setup_and_veto(
            {
                "current_price": 100,
                "atr": 1,
                "bias": "BUY",
                "order_blocks": [],
            },
            {
                "timeframe": "H4",
                "history_valid": True,
                "order_blocks": [{"bias": "bearish", "top": 101, "bottom": 99}],
            },
        )
        self.assertTrue(result["veto"])
        self.assertEqual(result["veto_data"]["htf_tf"], "H4")
        self.assertEqual(result["veto_data"]["conflict_timeframe"], "H4")
        self.assertEqual(result["veto_data"]["reason"], "htf_opposing_order_block")
        self.assertEqual(
            result["veto_data"]["danger_zone"],
            {"top": 101.0, "bottom": 99.0, "bias": "bearish"},
        )
        self.assertFalse(
            is_executable_signal(
                {
                    "setup_ready": True,
                    "veto": False,
                    "entryPrice": None,
                    "slPrice": None,
                    "tpPrices": [],
                }
            )
        )

    def test_same_direction_or_remote_htf_zone_does_not_veto(self):
        base = {"current_price": 100, "atr": 1, "bias": "BUY"}
        same_direction = evaluate_setup_and_veto(
            base,
            {
                "timeframe": "H4",
                "history_valid": True,
                "order_blocks": [{"bias": "bullish", "top": 101, "bottom": 99}],
            },
        )
        remote_opposing = evaluate_setup_and_veto(
            base,
            {
                "timeframe": "D1",
                "history_valid": True,
                "order_blocks": [{"bias": "bearish", "top": 110, "bottom": 108}],
            },
        )
        self.assertFalse(same_direction["veto"])
        self.assertFalse(remote_opposing["veto"])

    def test_sell_signal_is_vetoed_by_validated_bullish_htf_demand(self):
        result = evaluate_setup_and_veto(
            {"current_price": 100, "atr": 1, "bias": "SELL"},
            {
                "timeframe": "H4",
                "history_valid": True,
                "order_blocks": [{"bias": "bullish", "top": 101, "bottom": 99}],
            },
        )
        self.assertTrue(result["veto"])
        self.assertEqual(result["veto_data"]["danger_zone"]["bias"], "bullish")


if __name__ == "__main__":
    unittest.main()
