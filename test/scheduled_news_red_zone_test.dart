import 'package:flutter_test/flutter_test.dart';
import 'package:protrading_ai/data/repositories/news_repository.dart';

void main() {
  test('licensed scheduled event becomes a Red Zone', () {
    final overlay = parseScheduledRedZone({
      'impact': 'HIGH',
      'event_id': 'calendar:cpi-1',
      'start_time': 1700000600,
      'duration_min': 45,
      'label': 'CPI',
      'color': '#FF0000',
      'currencies': ['USD'],
      'evidence': {
        'source': 'licensed-calendar',
        'source_id': 'calendar:cpi-1',
        'timestamp': 1700002400,
      },
    }, nowEpochSeconds: 1700000000);

    expect(overlay, isNotNull);
    final parsed = overlay!;
    expect(parsed.eventId, 'calendar:cpi-1');
    expect(parsed.currencies, ['USD']);
    expect(parsed.startTime, 1700000600);
    expect(parsed.durationMinutes, 45);
    expect(parsed.toLayerItem()['event_id'], 'calendar:cpi-1');
    expect(parsed.toLayerItem()['currencies'], ['USD']);
  });

  test('HIGH-impact RSS headline without schedule is not a Red Zone', () {
    final overlay = parseScheduledRedZone({
      'impact': 'HIGH',
      'title': 'Fed headline',
      'timestamp': 1700000000,
    }, nowEpochSeconds: 1700000000);

    expect(overlay, isNull);
  });

  test('Tab 3 event and Tab 1 overlay keep one identity and timing', () {
    final event = parseScheduledNewsEvent({
      'impact': 'HIGH',
      'event_id': 'calendar:nfp-1',
      'start_time': 1700001200,
      'duration_min': 30,
      'label': 'NFP',
      'color': '#FF0000',
      'currencies': ['usd', 'USD'],
      'evidence': {
        'source': 'licensed-calendar',
        'source_id': 'calendar:nfp-1',
        'timestamp': 1700000000,
      },
    }, nowEpochSeconds: 1700000100);

    expect(event, isNotNull);
    final overlay = redZoneOverlayForEvent(event!);
    expect(overlay.eventId, event.eventId);
    expect(overlay.startTime, event.startTime);
    expect(overlay.durationMinutes, event.durationMinutes);
    expect(overlay.currencies, event.currencies);
  });

  test('deduplicates one event lifecycle and clears it after expiry', () {
    Map<String, dynamic> event(String label, int evidenceTimestamp) => {
      'impact': 'HIGH',
      'event_id': 'calendar:cpi-1',
      'start_time': 1700001200,
      'duration_min': 30,
      'label': label,
      'color': '#FF0000',
      'currencies': ['USD'],
      'evidence': {
        'source': 'licensed-calendar',
        'source_id': 'calendar:cpi-1',
        'timestamp': evidenceTimestamp,
      },
    };

    final active = selectNextScheduledNewsEvent([
      event('old', 1700000000),
      event('updated', 1700000100),
    ], nowEpochSeconds: 1700000200);
    final expired = selectNextScheduledNewsEvent([
      event('updated', 1700000100),
    ], nowEpochSeconds: 1700003001);

    expect(active, isNotNull);
    expect(active!.label, 'updated');
    expect(expired, isNull);
  });
}
