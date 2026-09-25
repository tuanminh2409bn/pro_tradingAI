import 'package:flutter_test/flutter_test.dart';
import 'package:protrading_ai/data/models/trading_models.dart';

void main() {
  test('cutoff status parses persisted review and bounded amounts', () {
    final status = DailyCutoffStatus.fromMap({
      'active': true,
      'reviewed': true,
      'acknowledged': false,
      'sessionDate': '2026-09-24',
      'realizedPnl': -20,
      'floatingPnl': -30.5,
      'lossLimit': double.nan,
    });
    expect(status.active, isTrue);
    expect(status.reviewed, isTrue);
    expect(status.acknowledged, isFalse);
    expect(status.realizedPnl, -20);
    expect(status.floatingPnl, -30.5);
    expect(status.lossLimit, isNull);
  });

  test('missing active field is rejected instead of unlocking', () {
    expect(
      () => DailyCutoffStatus.fromMap({'sessionDate': '2026-09-24'}),
      throwsFormatException,
    );
  });
}
