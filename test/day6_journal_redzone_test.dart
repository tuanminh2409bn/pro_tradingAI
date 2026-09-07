import 'package:flutter_test/flutter_test.dart';
import 'package:protrading_ai/data/models/journal_models.dart';
import 'package:protrading_ai/data/models/trading_models.dart';

void main() {
  group('Day6 journal schema', () {
    test('maps execution close fields to TradeRecord', () {
      final rec = TradeRecord.fromFirestoreMap({
        'symbol': 'XAUUSD',
        'type': 'BUY',
        'lotSize': 0.2,
        'openPrice': 2400.0,
        'closePrice': 2410.0,
        'profit': 20.0,
        'status': 'CLOSED',
        'closeTime': DateTime.utc(2026, 9, 6, 10),
      });
      expect(rec, isNotNull);
      expect(rec!.action, 'LONG');
      expect(rec.entryPrice, 2400.0);
      expect(rec.exitPrice, 2410.0);
      expect(rec.netProfit, 20.0);
    });

    test('skips open trades', () {
      final rec = TradeRecord.fromFirestoreMap({
        'symbol': 'EURUSD',
        'type': 'SELL',
        'status': 'OPEN',
        'openPrice': 1.1,
      });
      expect(rec, isNull);
    });
  });

  group('Day6 news red zone', () {
    test('withNewsRedZone adds layer 5 news_column', () {
      const base = TradingSignal(
        symbol: 'XAUUSD',
        entryPrice: 1,
        slPrice: 0.9,
        tpPrices: [1.1],
        probability: 50,
        type: 'BUY',
        status: 'ACTIVE',
        layers: [],
      );
      final next = base.withNewsRedZone('NEWS Fed rate decision');
      final layer5 = next.layers.firstWhere((l) => l['layer'] == 5);
      final items = (layer5['items'] as List).cast<Map>();
      expect(items.any((i) => i['type'] == 'news_column'), isTrue);
    });

    test('allowsTimeframe lock for scalping', () {
      expect(TradingMode.scalping.allowsTimeframe('5'), isTrue);
      expect(TradingMode.scalping.allowsTimeframe('240'), isFalse);
    });
  });
}
