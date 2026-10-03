"""Server-side daily-loss cutoff policy tests."""

import unittest

from daily_loss_guard import DailyLossPolicyError, evaluate_daily_loss


class DailyLossGuardTests(unittest.TestCase):
    def test_realized_and_floating_losses_are_combined_at_boundary(self):
        decision = evaluate_daily_loss(
            balance=1000,
            max_daily_loss_percent=5,
            realized_pnl=-5,
            floating_pnl=-45,
        )
        self.assertEqual(decision.total_pnl, -50)
        self.assertEqual(decision.loss_limit, 50)
        self.assertTrue(decision.blocked)

    def test_recovery_below_limit_allows_new_paper_trade(self):
        decision = evaluate_daily_loss(
            balance=1000,
            max_daily_loss_percent=5,
            realized_pnl=-20,
            floating_pnl=5,
        )
        self.assertFalse(decision.blocked)

    def test_invalid_or_missing_risk_values_fail_closed(self):
        invalid = (
            dict(balance=0, max_daily_loss_percent=5),
            dict(balance=1000, max_daily_loss_percent=0),
            dict(balance=1000, max_daily_loss_percent=101),
        )
        for values in invalid:
            with self.subTest(values=values), self.assertRaises(DailyLossPolicyError):
                evaluate_daily_loss(**values, realized_pnl=0, floating_pnl=0)


if __name__ == "__main__":
    unittest.main()
