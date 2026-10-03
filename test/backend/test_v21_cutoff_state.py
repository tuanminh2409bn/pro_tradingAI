import unittest
from datetime import datetime, timezone

from cutoff_state import cutoff_active, utc_session


class CutoffStateTests(unittest.TestCase):
    def test_latch_survives_recovery_refresh_and_utc_day_until_review_and_ack(self):
        day = datetime(2026, 9, 24, 23, 59, tzinfo=timezone.utc)
        next_day = datetime(2026, 9, 25, 0, 0, tzinfo=timezone.utc)
        state = {"active": True, "sessionDate": utc_session(day)}
        self.assertTrue(cutoff_active(state, day))
        self.assertTrue(cutoff_active(state, next_day))
        state["reviewedAt"] = day
        self.assertTrue(cutoff_active(state, next_day))
        state["acknowledgedAt"] = next_day
        self.assertTrue(cutoff_active(state, day))
        self.assertFalse(cutoff_active(state, next_day))

    def test_invalid_session_and_naive_clock_fail_closed(self):
        now = datetime(2026, 9, 25, tzinfo=timezone.utc)
        self.assertTrue(cutoff_active({"active": True}, now))
        self.assertTrue(cutoff_active({"active": True, "sessionDate": "bad", "reviewedAt": 1, "acknowledgedAt": 1}, now))
        self.assertFalse(cutoff_active(None, now))
        with self.assertRaises(ValueError):
            utc_session(datetime(2026, 9, 25))


if __name__ == "__main__":
    unittest.main()
