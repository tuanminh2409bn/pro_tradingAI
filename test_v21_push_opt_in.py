import unittest

from push_preferences import push_recipient_opted_in


class PushOptInTests(unittest.TestCase):
    def test_push_delivery_requires_explicit_boolean_opt_in(self):
        self.assertFalse(push_recipient_opted_in(None))
        self.assertFalse(push_recipient_opted_in({}))
        self.assertFalse(push_recipient_opted_in({"pushNotificationsEnabled": "true"}))
        self.assertFalse(push_recipient_opted_in({"pushNotificationsEnabled": False}))
        self.assertTrue(push_recipient_opted_in({"pushNotificationsEnabled": True}))


if __name__ == "__main__":
    unittest.main()
