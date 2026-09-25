import 'package:flutter_test/flutter_test.dart';
import 'package:protrading_ai/data/models/backtest_models.dart';

List<BacktestBar> _bars() => List.generate(
  5,
  (index) => BacktestBar(
    timestamp: 1700000000 + index * 300,
    open: 100 + index.toDouble(),
    high: 101 + index.toDouble(),
    low: 99 + index.toDouble(),
    close: 100.5 + index.toDouble(),
    volume: 1000 + index.toDouble(),
    isClosed: true,
  ),
);

void main() {
  group('BacktestReplayEngine', () {
    test(
      'reveals exactly one closed candle per tick and never future bars',
      () {
        final engine = BacktestReplayEngine(
          sessionId: 'session-1',
          symbol: 'XAUUSD',
          sourceId: 'licensed-history-1',
          bars: _bars(),
        )..resume();

        expect(engine.visibleBars.map((bar) => bar.timestamp), [1700000000]);
        expect(engine.advanceTick(), isTrue);
        expect(engine.visibleBars.map((bar) => bar.timestamp), [
          1700000000,
          1700000300,
        ]);
        expect(engine.currentBar.timestamp, 1700000300);
        expect(engine.visibleBars, hasLength(2));
      },
    );

    test('x1 x5 x10 change cadence but a tick still advances one bar', () {
      final engine = BacktestReplayEngine(
        sessionId: 'session-1',
        symbol: 'XAUUSD',
        sourceId: 'licensed-history-1',
        bars: _bars(),
      )..resume();

      expect(engine.tickInterval, const Duration(seconds: 1));
      engine.setSpeed(5);
      expect(engine.tickInterval, const Duration(milliseconds: 200));
      expect(engine.advanceTick(), isTrue);
      expect(engine.cursor, 1);
      engine.setSpeed(10);
      expect(engine.tickInterval, const Duration(milliseconds: 100));
      expect(engine.advanceTick(), isTrue);
      expect(engine.cursor, 2);
      expect(() => engine.setSpeed(2), throwsArgumentError);
    });

    test('pause resume and cursor survive a validated snapshot restore', () {
      final original =
          BacktestReplayEngine(
              sessionId: 'session-1',
              symbol: 'XAUUSD',
              sourceId: 'licensed-history-1',
              bars: _bars(),
            )
            ..setSpeed(5)
            ..resume()
            ..advanceTick()
            ..pause();

      expect(original.advanceTick(), isFalse);
      final snapshot = original.snapshot.toMap();
      final restored = BacktestReplayEngine.restore(
        snapshot: BacktestReplaySnapshot.fromMap(snapshot),
        bars: _bars(),
        expectedSessionId: 'session-1',
        expectedSymbol: 'XAUUSD',
        expectedSourceId: 'licensed-history-1',
      );

      expect(restored.cursor, 1);
      expect(restored.speed, 5);
      expect(restored.isPlaying, isFalse);
      restored.resume();
      expect(restored.advanceTick(), isTrue);
      expect(restored.cursor, 2);
    });

    test('seek and manual steps remain inside the trusted history', () {
      final engine = BacktestReplayEngine(
        sessionId: 'session-1',
        symbol: 'XAUUSD',
        sourceId: 'licensed-history-1',
        bars: _bars(),
      )..resume();

      engine.seek(3);
      expect(engine.cursor, 3);
      expect(engine.isPlaying, isFalse);
      expect(engine.visibleBars, hasLength(4));
      expect(engine.stepBackward(), isTrue);
      expect(engine.cursor, 2);
      expect(engine.stepForward(), isTrue);
      expect(engine.cursor, 3);
      expect(() => engine.seek(5), throwsRangeError);
    });

    test('copies input and rejects forming, unordered, or mismatched data', () {
      final input = _bars();
      final engine = BacktestReplayEngine(
        sessionId: 'session-1',
        symbol: 'XAUUSD',
        sourceId: 'licensed-history-1',
        bars: input,
      );
      input.clear();
      expect(engine.visibleBars, hasLength(1));

      final forming = _bars()..[2] = _bars()[2].copyWith(isClosed: false);
      expect(
        () => BacktestReplayEngine(
          sessionId: 'session-1',
          symbol: 'XAUUSD',
          sourceId: 'licensed-history-1',
          bars: forming,
        ),
        throwsArgumentError,
      );
      expect(
        () => BacktestReplayEngine(
          sessionId: 'session-1',
          symbol: 'XAUUSD',
          sourceId: 'licensed-history-1',
          bars: _bars().reversed.toList(),
        ),
        throwsArgumentError,
      );

      final snapshot = BacktestReplaySnapshot(
        sessionId: 'other-session',
        symbol: 'XAUUSD',
        sourceId: 'licensed-history-1',
        cursor: 1,
        speed: 1,
        isPlaying: false,
      );
      expect(
        () => BacktestReplayEngine.restore(
          snapshot: snapshot,
          bars: _bars(),
          expectedSessionId: 'session-1',
          expectedSymbol: 'XAUUSD',
          expectedSourceId: 'licensed-history-1',
        ),
        throwsArgumentError,
      );
    });
  });
}
