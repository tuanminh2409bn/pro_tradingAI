import 'package:flutter_test/flutter_test.dart';
import 'package:protrading_ai/data/models/journal_models.dart';
import 'package:protrading_ai/data/models/trading_models.dart';
import 'package:protrading_ai/data/repositories/journal_repository.dart';

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
        'executionMode': 'paper',
        'closeTime': DateTime.utc(2026, 9, 6, 10),
      });
      expect(rec, isNotNull);
      expect(rec!.action, 'LONG');
      expect(rec.entryPrice, 2400.0);
      expect(rec.exitPrice, 2410.0);
      expect(rec.netProfit, 20.0);
      expect(rec.executionMode, 'paper');
      expect(rec.brokerMetrics, isNull);
    });

    test('normalizes broker metrics only with source and currency', () {
      final rec = TradeRecord.fromFirestoreMap({
        'symbol': 'EURUSD',
        'action': 'SHORT',
        'volume': 0.5,
        'entryPrice': 1.09,
        'exitPrice': 1.08,
        'netProfit': 500.0,
        'status': 'CLOSED',
        'closeTime': DateTime.utc(2026, 9, 6, 11),
        'executionMode': 'broker',
        'brokerMetrics': {
          'source': 'metaapi:deal-history',
          'currency': 'USD',
          'swap': -1.25,
          'commission': 0,
          'slippage': 0.00002,
        },
      });

      expect(rec, isNotNull);
      expect(rec!.brokerMetrics, isNotNull);
      expect(rec.swap, -1.25);
      expect(rec.commission, 0);
      expect(rec.slippage, 0.00002);
      expect(rec.metricSource, 'metaapi:deal-history');
      expect(rec.metricCurrency, 'USD');
      expect(rec.executionMode, 'broker');
    });

    test('does not present unproven zero metrics as broker facts', () {
      final rec = TradeRecord.fromFirestoreMap({
        'symbol': 'XAUUSD',
        'type': 'BUY',
        'openPrice': 2400.0,
        'closePrice': 2401.0,
        'profit': 1.0,
        'status': 'CLOSED',
        'swap': 0,
        'commission': 0,
        'slippage': 0,
        'closeTime': DateTime.utc(2026, 9, 6, 12),
      });

      expect(rec, isNotNull);
      expect(rec!.brokerMetrics, isNull);
      expect(rec.swap, isNull);
      expect(rec.commission, isNull);
      expect(rec.slippage, isNull);
      expect(rec.metricSource, isNull);
      expect(rec.metricCurrency, isNull);
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

  group('Journal behavioral insight', () {
    test('cites the measured worst loss time instead of a generic claim', () {
      final trades = [
        TradeRecord(
          symbol: 'XAUUSD',
          action: 'LONG',
          lotSize: 0.1,
          entryPrice: 2400,
          exitPrice: 2390,
          netProfit: -20,
          closeTime: DateTime.utc(2026, 9, 8, 9, 10),
        ),
        TradeRecord(
          symbol: 'EURUSD',
          action: 'SHORT',
          lotSize: 0.2,
          entryPrice: 1.1,
          exitPrice: 1.11,
          netProfit: -15,
          closeTime: DateTime.utc(2026, 9, 8, 9, 45),
        ),
        TradeRecord(
          symbol: 'GBPUSD',
          action: 'LONG',
          lotSize: 0.2,
          entryPrice: 1.3,
          exitPrice: 1.31,
          netProfit: 10,
          closeTime: DateTime.utc(2026, 9, 9, 14),
        ),
      ];

      final insight = buildJournalInsight(
        totalTrades: trades.length,
        winRate: 100 / 3,
        totalProfit: -25,
        bestTrade: 10,
        worstTrade: -20,
        profitFactor: 10 / 35,
        trades: trades,
      );

      expect(insight, contains('Tuesday 09:00 UTC'));
      expect(insight, contains('2 measured losing trades'));
      expect(insight, contains('-35.00 net P&L'));
      expect(insight, isNot(contains(r'$')));
      expect(insight, isNot(contains('Tighten stop losses')));
    });
  });

  group('Day6 news red zone', () {
    test('withNewsRedZone adds a scheduled, evidence-backed item', () {
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
      final next = base.withNewsRedZone(
        const RedZoneOverlay(
          eventId: 'fed-1',
          startTime: 1700000600,
          durationMinutes: 45,
          label: 'Fed rate decision',
          color: '#FF0000',
          currencies: ['USD'],
          evidence: {
            'source': 'licensed-calendar',
            'source_id': 'fed-1',
            'timestamp': 1700002400,
          },
        ),
      );
      final layer5 = next.layers.firstWhere((l) => l['layer'] == 5);
      final items = (layer5['items'] as List).cast<Map>();
      final item = items.singleWhere((i) => i['type'] == 'red_zone');
      expect(item['start_time'], 1700000600);
      expect(item['duration_min'], 45);
      expect(item['evidence']['source'], 'licensed-calendar');
    });

    test('allowsTimeframe lock for scalping', () {
      expect(TradingMode.scalping.allowsTimeframe('5'), isTrue);
      expect(TradingMode.scalping.allowsTimeframe('240'), isFalse);
    });
  });
}
