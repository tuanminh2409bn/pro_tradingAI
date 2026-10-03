"""Pure parser for attributed public-domain Federal Reserve press releases.

The feed is news, not a release calendar or a sentiment measurement.
Rights: https://www.federalreserve.gov/disclaimer.htm (text only; no logos/images).
Feed index: https://www.federalreserve.gov/feeds/feeds.htm
"""

import hashlib
import html
import re
from datetime import datetime, timezone
from email.utils import parsedate_to_datetime
from urllib.parse import urlsplit
from xml.etree import ElementTree


LICENSE_REF = 'https://www.federalreserve.gov/disclaimer.htm'
APPROVED_NEWS_FEEDS = tuple({
    'url': 'https://www.federalreserve.gov/feeds/press_' + kind + '.xml',
    'source': 'Federal Reserve Board',
    'category': 'OFFICIAL',
    'license_status': 'approved',
    'license_ref': LICENSE_REF,
} for kind in ('all', 'monetary'))
_FEED_URLS = frozenset(feed['url'] for feed in APPROVED_NEWS_FEEDS)
MAX_BYTES = 300000
MAX_HISTORY_SECONDS = 30 * 86400
FRESH_SECONDS = 48 * 3600


def _plain_text(value, limit):
    return re.sub(r'\s+', ' ', re.sub(r'<[^>]*>', '', html.unescape(value or ''))).strip()[:limit]


def _official_article_url(value):
    try:
        parsed = urlsplit(value)
        return (parsed.scheme == 'https' and parsed.hostname == 'www.federalreserve.gov'
                and parsed.port in (None, 443) and parsed.username is None
                and parsed.password is None and not parsed.query and not parsed.fragment
                and parsed.path.startswith('/newsevents/pressreleases/'))
    except ValueError:
        return False


def parse_official_feed(xml_text, *, feed_url, now_epoch_seconds):
    if (feed_url not in _FEED_URLS or not isinstance(xml_text, str)
            or len(xml_text.encode('utf-8')) > MAX_BYTES
            or re.search(r'<!\s*(?:DOCTYPE|ENTITY)\b', xml_text, re.IGNORECASE)):
        return []
    try:
        root = ElementTree.fromstring(xml_text)
    except ElementTree.ParseError:
        return []
    articles = {}
    for item in root.findall('./channel/item')[:12]:
        title = _plain_text(item.findtext('title'), 500)
        url = (item.findtext('link') or '').strip()
        if not title or not _official_article_url(url):
            continue
        try:
            date = parsedate_to_datetime(item.findtext('pubDate') or '')
            if date.tzinfo is None:
                continue
            published = int(date.timestamp())
        except (TypeError, ValueError, OverflowError):
            continue
        age = max(0, int(now_epoch_seconds) - published)
        if published <= 0 or published > now_epoch_seconds + 300 or age > MAX_HISTORY_SECONDS:
            continue
        article_id = hashlib.sha256(('Federal Reserve Board:' + url).encode()).hexdigest()
        articles[article_id] = {
            'id': article_id, 'title': title,
            'summary': _plain_text(item.findtext('description'), 700),
            'url': url, 'source': 'Federal Reserve Board', 'category': 'OFFICIAL',
            'type': 'OFFICIAL', 'impact': 'UNRATED', 'sentimentScore': None,
            'imageUrl': '', 'published_at': published,
            'timestamp': datetime.fromtimestamp(published, timezone.utc),
            'provenance': {'provider_type': 'official_release', 'feed_url': feed_url,
                           'license_status': 'approved', 'license_ref': LICENSE_REF},
            'freshness': {'status': 'fresh' if age <= FRESH_SECONDS else 'historical',
                          'observed_at': int(now_epoch_seconds), 'age_seconds': age,
                          'fresh_window_seconds': FRESH_SECONDS},
        }
    return sorted(articles.values(), key=lambda article: (-article['published_at'], article['id']))
