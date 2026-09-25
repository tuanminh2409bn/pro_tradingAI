import 'package:flutter_test/flutter_test.dart';
import 'package:protrading_ai/data/models/trading_models.dart';

void main() {
  test('Candle retains provider volume', () {
    final candle = Candle(
      timestamp: DateTime.fromMillisecondsSinceEpoch(1700000000000),
      open: 10,
      high: 12,
      low: 9,
      close: 11,
      volume: 1234.5,
    );

    expect(candle.volume, 1234.5);
    expect(candle.props, contains(1234.5));
  });
}
