import unittest
from pathlib import Path

from news_sentiment import (
    aggregate_sentiment,
    deduplicate_news,
    normalize_news_item,
)


class NewsSentimentContractTests(unittest.TestCase):
    def _raw(self, **overrides):
        item = {
            "provider": "approved-calendar",
            "provider_type": "calendar",
            "provider_event_id": "event-1",
            "license_status": "approved",
            "license_ref": "contract-2026-01",
            "title": "US CPI release",
            "summary": "Inflation reaction",
            "published_at": 1_700_000_000,
            "positive_mentions": 3,
            "negative_mentions": 1,
            "neutral_mentions": 0,
            "impact": "HIGH",
            "currencies": ["usd", "USD", "eur"],
            "symbols": ["xauusd", "EURUSD"],
        }
        item.update(overrides)
        return item

    def test_score_uses_documented_minus_100_to_100_formula(self):
        bullish = normalize_news_item(
            self._raw(positive_mentions=4, negative_mentions=0),
            now_epoch_seconds=1_700_000_100,
        )
        bearish = normalize_news_item(
            self._raw(
                provider_event_id="event-2",
                positive_mentions=0,
                negative_mentions=4,
            ),
            now_epoch_seconds=1_700_000_100,
        )
        boundary = normalize_news_item(
            self._raw(
                provider_event_id="event-3",
                positive_mentions=5,
                negative_mentions=3,
            ),
            now_epoch_seconds=1_700_000_100,
        )

        self.assertEqual(bullish.item["sentiment_score"], 100)
        self.assertEqual(bullish.item["sentiment_class"], "BULLISH")
        self.assertEqual(bearish.item["sentiment_score"], -100)
        self.assertEqual(bearish.item["sentiment_class"], "BEARISH")
        self.assertEqual(boundary.item["sentiment_score"], 25)
        self.assertEqual(boundary.item["sentiment_class"], "BULLISH")
        self.assertEqual(
            boundary.item["score_method"],
            "(positive_mentions-negative_mentions)/total_mentions*100",
        )

    def test_unapproved_missing_license_and_stale_items_fail_closed(self):
        unapproved = normalize_news_item(
            self._raw(license_status="unknown"),
            now_epoch_seconds=1_700_000_100,
        )
        missing_license = normalize_news_item(
            self._raw(license_ref=""),
            now_epoch_seconds=1_700_000_100,
        )
        stale = normalize_news_item(
            self._raw(published_at=1_699_900_000),
            now_epoch_seconds=1_700_000_100,
            max_age_seconds=3_600,
        )

        self.assertEqual(unapproved.rejection_reason, "source_not_approved")
        self.assertEqual(missing_license.rejection_reason, "missing_license_ref")
        self.assertEqual(stale.rejection_reason, "stale")
        self.assertIsNone(unapproved.item)
        self.assertIsNone(missing_license.item)
        self.assertIsNone(stale.item)

    def test_explicit_currency_symbol_mapping_and_dedup_are_stable(self):
        older = normalize_news_item(
            self._raw(),
            now_epoch_seconds=1_700_000_100,
        ).item
        newer = normalize_news_item(
            self._raw(published_at=1_700_000_050, title="US CPI revised"),
            now_epoch_seconds=1_700_000_100,
        ).item
        other = normalize_news_item(
            self._raw(provider_event_id="event-2", title="ECB decision"),
            now_epoch_seconds=1_700_000_100,
        ).item

        self.assertEqual(newer["currencies"], ["EUR", "USD"])
        self.assertEqual(newer["symbols"], ["EURUSD", "XAUUSD"])
        result = deduplicate_news([older, newer, other])
        self.assertEqual(len(result), 2)
        self.assertEqual(result[0]["title"], "US CPI revised")
        self.assertEqual(result[1]["title"], "ECB decision")

    def test_provider_failure_is_unavailable_not_neutral(self):
        pulse = aggregate_sentiment([])

        self.assertEqual(pulse["status"], "unavailable")
        self.assertIsNone(pulse["score"])
        self.assertEqual(pulse["article_count"], 0)

    def test_unapproved_hardcoded_rss_crawler_cannot_start(self):
        server_source = (Path(__file__).resolve().parents[2] / "server.py").read_text(
            encoding="utf-8"
        )

        self.assertNotIn("RSS_FEEDS = [", server_source)
        from official_news import APPROVED_NEWS_FEEDS, LICENSE_REF
        self.assertTrue(APPROVED_NEWS_FEEDS)
        for feed in APPROVED_NEWS_FEEDS:
            self.assertEqual(feed['license_status'], 'approved')
            self.assertEqual(feed['license_ref'], LICENSE_REF)
            self.assertTrue(feed['url'].startswith('https://www.federalreserve.gov/feeds/'))
        self.assertIn("if APPROVED_NEWS_FEEDS and not LOCAL_QA_MODE:", server_source)
        self.assertIn("items = parse_official_feed", server_source)


if __name__ == "__main__":
    unittest.main()
