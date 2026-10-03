import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:protrading_ai/data/repositories/news_repository.dart';

void main() {
  final published = DateTime.utc(2026, 10, 2, 20, 45);
  final observed = DateTime.utc(2026, 10, 3, 1);

  test(
    'official release uses publication time and leaves absent score unknown',
    () {
      final article = parseNewsArticle({
        'title': 'Fixture official release',
        'source': 'Federal Reserve Board',
        'type': 'OFFICIAL',
        'impact': 'UNRATED',
        'published_at': published.millisecondsSinceEpoch ~/ 1000,
        'timestamp': Timestamp.fromDate(observed),
        'sentimentScore': null,
        'timeAgo': 'Just now',
      }, now: observed)!;
      expect(article.timeAgo, '4h ago');
      expect(article.sentimentScore, isNull);
      expect(article.impact, 'UNRATED');
      expect(article.scheduledEvent, isNull);
    },
  );

  test(
    'legacy publication timestamp remains supported without unsafe casts',
    () {
      final article = parseNewsArticle({
        'title': 'Fixture legacy headline',
        'timestamp': Timestamp.fromDate(published),
        'sentimentScore': 'not a measurement',
      }, now: observed)!;
      expect(article.timeAgo, '4h ago');
      expect(article.sentimentScore, isNull);
      final unknown = parseNewsArticle({
        'title': 'Fixture unknown date',
        'published_at': 'invalid',
        'timestamp': Timestamp.fromDate(observed),
      }, now: observed)!;
      expect(unknown.timeAgo, '__TIME_UNAVAILABLE__');
      expect(parseNewsArticle({'title': '  '}, now: observed), isNull);
    },
  );
  test('legacy or stale sentiment cannot look like current data', () {
    final values = <String, dynamic>{
      'fearGreedIndex': 60,
      'bearish': 20,
      'neutral': 20,
      'bullish': 60,
      'mood': 'GREED',
      'updatedAt': Timestamp.fromDate(observed),
    };
    expect(parseSentimentPulse(values, now: observed).isAvailable, isFalse);
    final approved = {
      ...values,
      'provenance': {
        'provider': 'qa-fixture',
        'provider_type': 'x',
        'license_status': 'approved',
        'license_ref': 'qa-approved-contract',
      },
    };
    expect(parseSentimentPulse(approved, now: observed).isAvailable, isTrue);
    expect(
      parseSentimentPulse(
        approved,
        now: observed.add(const Duration(hours: 2)),
      ).isAvailable,
      isFalse,
    );
    expect(
      parseSentimentPulse({
        ...approved,
        'fearGreedIndex': double.nan,
      }, now: observed).isAvailable,
      isFalse,
    );
  });
}
