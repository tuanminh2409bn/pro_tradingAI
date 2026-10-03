"""Shared analysis cache artifacts must never contain user-specific context."""

from __future__ import annotations

import unittest

from feature_engine import market_analysis_features, strip_user_specific_analysis


class CacheNeutralityTests(unittest.TestCase):
    def test_market_features_drop_identity_and_account_values(self):
        base = {"symbol": "XAUUSD", "atr": 2, "userId": "alice", "balance": 1_000}
        alice = market_analysis_features({**base, "account_context": {"risk": 1}})
        bob = market_analysis_features(
            {**base, "userId": "bob", "balance": 2_000, "account_context": {"risk": 3}}
        )
        self.assertEqual(alice, bob)
        self.assertEqual(alice, {"symbol": "XAUUSD", "atr": 2})

    def test_cached_signal_drops_user_specific_lot_without_mutating_input(self):
        raw = {
            "suggestedLot": 0.7,
            "layers": [{"layer": 4, "suggested_lot": 0.7}, {"layer": 5, "items": []}],
        }
        clean = strip_user_specific_analysis(raw)
        self.assertNotIn("suggestedLot", clean)
        self.assertNotIn("suggested_lot", clean["layers"][0])
        self.assertEqual(raw["suggestedLot"], 0.7)
        self.assertEqual(raw["layers"][0]["suggested_lot"], 0.7)


if __name__ == "__main__":
    unittest.main()
