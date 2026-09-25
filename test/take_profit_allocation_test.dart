import 'package:flutter_test/flutter_test.dart';
import 'package:protrading_ai/data/models/trading_models.dart';
import 'package:protrading_ai/data/repositories/trading_repository.dart';
import 'package:protrading_ai/features/trading_room/web/widgets/kinetic_chart.dart';

void main() {
  test(
    'paper intent key survives an uncertain retry but resets after success',
    () {
      final keys = PaperIntentKeys();
      final payload = <String, dynamic>{'signalId': 's1', 'volume': 0.1};
      var generated = 0;
      String next() => 'intent-${++generated}';

      expect(keys.forPayload(payload, next), 'intent-1');
      expect(keys.forPayload(payload, next), 'intent-1');
      expect(keys.forPayload({...payload, 'volume': 0.2}, next), 'intent-2');
      keys.complete(payload);
      expect(keys.forPayload(payload, next), 'intent-3');
    },
  );

  group('TakeProfitAllocationPlan', () {
    test('splits 1.0 lot into the specified 30/30/40 legs', () {
      final plan = TakeProfitAllocationPlan.create(
        totalVolume: 1,
        targetPrices: const [101, 102, 103],
        percentages: const [30, 30, 40],
        lotStep: 0.01,
        minLot: 0.01,
      );

      expect(plan.legs.map((leg) => leg.volume), [0.3, 0.3, 0.4]);
      expect(plan.legs.map((leg) => leg.targetPrice), [101, 102, 103]);
      expect(plan.allocatedVolume, closeTo(1, 1e-9));
    });

    test('uses deterministic largest remainders without losing volume', () {
      final plan = TakeProfitAllocationPlan.create(
        totalVolume: 0.1,
        targetPrices: const [101, 102, 103],
        percentages: const [33, 33, 34],
        lotStep: 0.01,
        minLot: 0.01,
      );

      expect(plan.legs.map((leg) => leg.volume), [0.03, 0.03, 0.04]);
      expect(plan.allocatedVolume, closeTo(0.1, 1e-9));
    });

    test('rejects percentages that do not total 100', () {
      expect(
        () => TakeProfitAllocationPlan.create(
          totalVolume: 1,
          targetPrices: const [101, 102, 103],
          percentages: const [30, 30, 30],
          lotStep: 0.01,
          minLot: 0.01,
        ),
        throwsArgumentError,
      );
    });

    test('rejects a positive leg below the symbol minimum lot', () {
      expect(
        () => TakeProfitAllocationPlan.create(
          totalVolume: 0.02,
          targetPrices: const [101, 102, 103],
          percentages: const [30, 30, 40],
          lotStep: 0.01,
          minLot: 0.01,
        ),
        throwsArgumentError,
      );
    });
  });

  test('partial TP payloads preserve the existing API contract', () {
    final plan = TakeProfitAllocationPlan.create(
      totalVolume: 1,
      targetPrices: const [101, 102, 103],
      percentages: const [30, 30, 40],
      lotStep: 0.01,
      minLot: 0.01,
    );

    final payloads = buildPartialTradePayloads(
      signalId: 'signal-1',
      signalChartId: 'XAUUSD_5_1800000000',
      symbol: 'XAUUSD',
      type: 'BUY',
      entryPrice: 100,
      slPrice: 98,
      plan: plan,
      userId: 'user-1',
      tradingMode: 'scalping',
    );

    expect(payloads, hasLength(3));
    expect(payloads.map((payload) => payload['volume']), [0.3, 0.3, 0.4]);
    expect(payloads.map((payload) => payload['tpPrices']), [
      [101.0],
      [102.0],
      [103.0],
    ]);
    expect(payloads.every((payload) => payload['action'] == 'BUY'), isTrue);
    expect(payloads.expand((payload) => payload.keys).toSet(), {
      'signalId',
      'signalChartId',
      'userId',
      'action',
      'symbol',
      'volume',
      'entryPrice',
      'slPrice',
      'tpPrices',
      'tradingMode',
    });
  });

  test('selecting TP3 dims only TP1 and TP2 to 40 percent', () {
    expect(takeProfitLineOpacity(selectedTargetIndex: 2, lineIndex: 0), 0.4);
    expect(takeProfitLineOpacity(selectedTargetIndex: 2, lineIndex: 1), 0.4);
    expect(takeProfitLineOpacity(selectedTargetIndex: 2, lineIndex: 2), 1.0);
    expect(takeProfitLineOpacity(selectedTargetIndex: 1, lineIndex: 0), 1.0);
  });
}
