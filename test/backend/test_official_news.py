import unittest

from official_news import APPROVED_NEWS_FEEDS, parse_official_feed


FEED = 'https://www.federalreserve.gov/feeds/press_all.xml'
NOW = 1791057600
LINK = 'https://www.federalreserve.gov/newsevents/pressreleases/orders20261002a.htm'


def xml_item(*, link=LINK, published='Fri, 2 Oct 2026 20:45:00 GMT'):
    return '<rss><channel><item><guid>qa-fixture</guid><title>Fixture policy announcement</title><link>' + link + '</link><description>Fixture &amp; description</description><pubDate>' + published + '</pubDate></item></channel></rss>'


class OfficialNewsTests(unittest.TestCase):
    def test_publication_time_and_provenance_do_not_invent_sentiment_or_calendar(self):
        article = parse_official_feed(xml_item(), feed_url=FEED, now_epoch_seconds=NOW)[0]
        self.assertEqual(article['published_at'], 1790973900)
        self.assertEqual(article['source'], 'Federal Reserve Board')
        self.assertEqual(article['provenance']['license_ref'], 'https://www.federalreserve.gov/disclaimer.htm')
        self.assertEqual(article['summary'], 'Fixture & description')
        self.assertEqual(article['type'], 'OFFICIAL')
        self.assertEqual(article['impact'], 'UNRATED')
        self.assertIsNone(article['sentimentScore'])
        self.assertEqual(article['imageUrl'], '')
        self.assertNotIn('scheduledEvent', article)
        self.assertNotIn('mentions', article)

    def test_external_urls_invalid_dates_and_future_publications_are_rejected(self):
        for link in ('http://www.federalreserve.gov/article', 'https://www.federalreserve.gov.evil.test/article', 'https://www.federalreserve.gov@evil.test/article', 'https://www.federalreserve.gov:8443/article'):
            self.assertEqual(parse_official_feed(xml_item(link=link), feed_url=FEED, now_epoch_seconds=NOW), [])
        for date in ('unknown', 'Fri, 2 Oct 2099 20:45:00 GMT', ''):
            self.assertEqual(parse_official_feed(xml_item(published=date), feed_url=FEED, now_epoch_seconds=NOW), [])
        self.assertEqual(parse_official_feed(xml_item(), feed_url='https://evil.test/feed.xml', now_epoch_seconds=NOW), [])

    def test_malformed_oversized_and_entity_documents_fail_closed(self):
        for document in ('<rss>', ' ' * 300001, '<!DOCTYPE rss [<!ENTITY x "private">]>' + xml_item()):
            self.assertEqual(parse_official_feed(document, feed_url=FEED, now_epoch_seconds=NOW), [])

    def test_repeated_items_have_stable_identity_and_old_headlines_are_not_fresh(self):
        article = '<item><title>Fixture old announcement</title><link>' + LINK + '</link><pubDate>Wed, 16 Sep 2026 18:00:00 GMT</pubDate></item>'
        articles = parse_official_feed('<rss><channel>' + article * 2 + '</channel></rss>', feed_url=FEED, now_epoch_seconds=NOW)
        self.assertEqual(len(articles), 1)
        self.assertEqual(articles[0]['freshness']['status'], 'historical')
        self.assertEqual(articles[0]['id'], parse_official_feed('<rss><channel>' + article + '</channel></rss>', feed_url=FEED, now_epoch_seconds=NOW + 60)[0]['id'])
        self.assertTrue(all(feed['license_status'] == 'approved' and feed['license_ref'] for feed in APPROVED_NEWS_FEEDS))


if __name__ == '__main__':
    unittest.main()
