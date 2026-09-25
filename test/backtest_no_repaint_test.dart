import 'package:flutter_test/flutter_test.dart';
import 'package:protrading_ai/data/models/backtest_models.dart';

List<BacktestBar> _pricePath() => [
  const BacktestBar(
    timestamp: 1700000000,
    open: 100,
    high: 101,
    low: 99,
    close: 100,
    volume: 1000,
    isClosed: true,
  ),
  const BacktestBar(
    timestamp: 1700000300,
    open: 100,
    high: 106,
    low: 99,
    close: 105,
    volume: 1100,
    isClosed: true,
  ),
  const BacktestBar(
    timestamp: 1700000600,
    open: 105,
    high: 106,
    low: 99,
    close: 100,
    volume: 1200,
    isClosed: true,
  ),
];

BacktestReplayEngine _replay(List<BacktestBar> bars) => BacktestReplayEngine(
  sessionId: 'session-1',
  symbol: 'XAUUSD',
  sourceId: 'licensed-history-1',
  bars: bars,
);

void main() {
  group('Backtest No-Repaint simulation', () {
    test('analysis receives only bars through the immutable replay cursor', () {
      final source = _pricePath();
      final simulation = BacktestSimulationEngine(
        replay: _replay(source),
        initialBalance: 1000,
        maxLossAmount: 100,
        contractSize: 10,
      );

      final first = simulation.evaluate(
        (bars) => '${bars.length}:${bars.last.timestamp}:${bars.last.close}',
      );
      source[1] = const BacktestBar(
        timestamp: 1700000300,
        open: 100,
        high: 1000,
        low: 1,
        close: 999,
        volume: 9999,
        isClosed: true,
      );
      final repeated = simulation.evaluate(
        (bars) => '${bars.length}:${bars.last.timestamp}:${bars.last.close}',
      );

      expect(first.value, '1:1700000000:100.0');
      expect(repeated, first);
      expect(first.cursor, 0);
      expect(first.candleTimestamp, 1700000000);
    });

    test(
      'BUY and SELL trades reconcile balance and equity at candle close',
      () {
        final replay = _replay(_pricePath())..resume();
        final simulation = BacktestSimulationEngine(
          replay: replay,
          initialBalance: 1000,
          maxLossAmount: 500,
          contractSize: 10,
        );

        simulation.openTrade(id: 'buy-1', side: BacktestSide.buy, volume: 1);
        expect(simulation.advanceTick(), isTrue);
        final buy = simulation.closeTrade('buy-1');
        expect(buy.realizedPnl, 50);
        expect(simulation.balance, 1050);
        expect(simulation.equity, 1050);

        simulation.openTrade(id: 'sell-1', side: BacktestSide.sell, volume: 1);
        replay.resume();
        expect(simulation.advanceTick(), isTrue);
        final sell = simulation.closeTrade('sell-1');
        expect(sell.realizedPnl, 50);
        expect(simulation.balance, 1100);
        expect(simulation.equity, 1100);
        expect(simulation.openTrades, isEmpty);
      },
    );

    test('max-loss lock survives restore until its review is acknowledged', () {
      final fallingBars = _pricePath()
        ..[1] = const BacktestBar(
          timestamp: 1700000300,
          open: 100,
          high: 100,
          low: 89,
          close: 90,
          volume: 1100,
          isClosed: true,
        );
      final replay = _replay(fallingBars)..resume();
      final simulation = BacktestSimulationEngine(
        replay: replay,
        initialBalance: 1000,
        maxLossAmount: 50,
        contractSize: 10,
      );
      simulation.openTrade(id: 'loss-1', side: BacktestSide.buy, volume: 1);

      expect(simulation.advanceTick(), isTrue);
      expect(simulation.equity, 900);
      expect(simulation.isLocked, isTrue);
      expect(simulation.pendingReview?.lossAmount, 100);
      expect(
        () => simulation.openTrade(
          id: 'blocked',
          side: BacktestSide.buy,
          volume: 1,
        ),
        throwsStateError,
      );

      final restored = BacktestSimulationEngine.restore(
        snapshot: BacktestSimulationSnapshot.fromMap(
          simulation.snapshot.toMap(),
        ),
        bars: fallingBars,
        expectedSessionId: 'session-1',
        expectedSymbol: 'XAUUSD',
        expectedSourceId: 'licensed-history-1',
      );
      expect(restored.isLocked, isTrue);
      expect(restored.equity, 900);
      expect(
        () => restored.acknowledgeReview('wrong-review'),
        throwsStateError,
      );

      final reviewId = restored.pendingReview!.id;
      restored.acknowledgeReview(reviewId);
      expect(restored.isLocked, isFalse);
      expect(restored.pendingReview, isNull);
      expect(restored.lastAcknowledgedReview?.id, reviewId);
      expect(restored.lastAcknowledgedReview?.isAcknowledged, isTrue);
    });

    test('invalid execution inputs fail closed', () {
      final simulation = BacktestSimulationEngine(
        replay: _replay(_pricePath()),
        initialBalance: 1000,
        maxLossAmount: 50,
        contractSize: 10,
      );

      expect(
        () => simulation.openTrade(
          id: 'bad-volume',
          side: BacktestSide.buy,
          volume: 0,
        ),
        throwsArgumentError,
      );
      simulation.openTrade(id: 'trade-1', side: BacktestSide.buy, volume: 1);
      expect(
        () => simulation.openTrade(
          id: 'trade-1',
          side: BacktestSide.sell,
          volume: 1,
        ),
        throwsArgumentError,
      );
      expect(() => simulation.closeTrade('missing'), throwsStateError);

      final tamperedSnapshot = simulation.snapshot.toMap()..['balance'] = 999;
      expect(
        () => BacktestSimulationEngine.restore(
          snapshot: BacktestSimulationSnapshot.fromMap(tamperedSnapshot),
          bars: _pricePath(),
          expectedSessionId: 'session-1',
          expectedSymbol: 'XAUUSD',
          expectedSourceId: 'licensed-history-1',
        ),
        throwsFormatException,
      );
    });
  });
}
