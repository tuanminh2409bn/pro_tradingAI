"""AI chat must never present the active chart as another market."""

import unittest

from market_history import symbol_bound_chat_context


class ChatMarketContextTests(unittest.TestCase):
    def test_uses_price_only_for_matching_symbol_and_timeframe(self):
        context = symbol_bound_chat_context(
            requested_symbol="XAUUSD", requested_timeframe="5",
            chart_symbol="XAUUSD", chart_timeframe="5", chart_price=3050.5,
        )
        self.assertIn("3050.5", context)
        self.assertIn("Display stream", context)

    def test_rejects_foreign_or_missing_chart_price(self):
        for symbol, timeframe, price in (
            ("EURUSD", "5", 3050.5),
            ("XAUUSD", "15", 3050.5),
            ("XAUUSD", "5", 0),
        ):
            with self.subTest(symbol=symbol, timeframe=timeframe, price=price):
                context = symbol_bound_chat_context(
                    requested_symbol=symbol, requested_timeframe=timeframe,
                    chart_symbol="XAUUSD", chart_timeframe="5",
                    chart_price=price,
                )
                self.assertIn("unavailable", context)
                self.assertNotIn("3050.5", context)


if __name__ == "__main__":
    unittest.main()
