import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:protrading_ai/data/models/backtest_models.dart';
import 'package:protrading_ai/data/models/trading_models.dart';
import 'package:protrading_ai/data/repositories/backtest_repository.dart';
import 'package:protrading_ai/features/backtest/bloc/backtest_bloc.dart';
import 'package:protrading_ai/features/backtest/bloc/backtest_event.dart';
import 'package:protrading_ai/features/backtest/bloc/backtest_state.dart';

class _Repository extends Fake implements BacktestRepository {
  BacktestRecording? saved;
  int failedSaves = 0;
  bool quotaExhausted = false;
  @override
  Future<BacktestRecording?> loadRecording({
    required String userId,
    required String symbol,
  }) async => saved;
  @override
  Future<void> saveRecording(
    BacktestRecording recording, {
    bool includeHistory = false,
  }) async {
    if (failedSaves > 0) {
      failedSaves--;
      throw StateError('offline');
    }
    saved = BacktestRecording.fromMap(
      recording.toMap(),
      sessionId: recording.simulation.replay.sessionId,
    );
  }

  @override
  Future<BacktestSession> createSession({
    required String symbol,
    required DateTime startTime,
    required DateTime endTime,
    required double balance,
    required String userId,
  }) async {
    if (quotaExhausted) {
      throw const BacktestRequestException('backtest_quota_exhausted');
    }
    return BacktestSession(
      id: 'session-1',
      symbol: symbol,
      startTime: startTime,
      endTime: endTime,
      initialBalance: balance,
      currentBalance: balance,
      equity: balance,
      openPL: 0,
      speed: 1,
      isPlaying: false,
    );
  }

  @override
  Stream<List<BacktestTrade>> getActiveTrades(String sessionId) =>
      const Stream.empty();
}

List<Candle> _candles() => [
  for (final (index, price) in [100.0, 105.0, 90.0, 110.0].indexed)
    Candle(
      timestamp: DateTime.fromMillisecondsSinceEpoch(
        (1700000000 + index * 300) * 1000,
      ),
      open: price,
      high: price + 1,
      low: price - 1,
      close: price,
      volume: 100,
    ),
];

void main() {
  test(
    'Backtest quota denial ends loading with a localized error and no recording',
    () async {
      final repository = _Repository()..quotaExhausted = true;
      final bloc = BacktestBloc(
        backtestRepository: repository,
        historyStream: (_) => Stream.value(_candles()),
      );
      addTearDown(bloc.close);
      bloc.add(const StartBacktestSession('BTCUSD', 1000, userId: 'qa-user'));
      final state = await bloc.stream.firstWhere(
        (state) => state is BacktestError,
      );
      expect((state as BacktestError).message, 'backtest_quota_exhausted');
      expect(repository.saved, isNull);
    },
  );
  test(
    'Backtest BUY is executed at the current closed bar, not future history',
    () async {
      final bloc = BacktestBloc(
        backtestRepository: _Repository(),
        historyStream: (_) => Stream.value(_candles()),
      );
      addTearDown(bloc.close);
      bloc.add(const StartBacktestSession('BTCUSD', 1000, userId: 'qa-user'));
      await bloc.stream.firstWhere((state) => state is BacktestLoaded);
      bloc.add(const ExecuteBacktestTrade('BUY', 2));
      await Future<void>.delayed(Duration.zero);
      final state = bloc.state as BacktestLoaded;
      expect(state.activeTrades, hasLength(1));
      expect(state.activeTrades.single.entryPrice, 100);
      expect(state.visibleBars, hasLength(1));
      bloc.add(const StepReplayCursor(1));
      await bloc.stream.firstWhere(
        (state) => state is BacktestLoaded && state.cursor == 1,
      );
      expect((bloc.state as BacktestLoaded).session.equity, 1010);
      bloc.add(CloseBacktestTrade(state.activeTrades.single.id!));
      await bloc.stream.firstWhere(
        (state) => state is BacktestLoaded && state.closedTrades.isNotEmpty,
      );
      expect((bloc.state as BacktestLoaded).session.currentBalance, 1010);
      bloc.add(const SeekReplayCursor(0));
      await Future<void>.delayed(Duration.zero);
      expect((bloc.state as BacktestLoaded).cursor, 1);
    },
  );

  test(
    'loss lock and review survive restore without reading new history',
    () async {
      final repository = _Repository();
      final first = BacktestBloc(
        backtestRepository: repository,
        historyStream: (_) => Stream.value(_candles()),
      );
      first.add(
        const StartBacktestSession(
          'BTCUSD',
          1000,
          userId: 'qa-user',
          maxLossPercent: 1,
        ),
      );
      await first.stream.firstWhere((state) => state is BacktestLoaded);
      first.add(const ExecuteBacktestTrade('BUY', 2));
      await first.stream.firstWhere(
        (state) => state is BacktestLoaded && state.activeTrades.isNotEmpty,
      );
      first.add(const StepReplayCursor(1));
      first.add(const StepReplayCursor(1));
      await first.stream.firstWhere(
        (state) => state is BacktestLoaded && state.session.isLocked,
      );
      final review = (first.state as BacktestLoaded).pendingReview!;
      expect(review.lossAmount, 20);
      await first.close();
      final restored = BacktestBloc(
        backtestRepository: repository,
        historyStream: (_) => throw StateError('Must use saved history'),
      );
      addTearDown(restored.close);
      restored.add(
        const StartBacktestSession('BTCUSD', 9999, userId: 'qa-user'),
      );
      await restored.stream.firstWhere((state) => state is BacktestLoaded);
      final state = restored.state as BacktestLoaded;
      expect(state.cursor, 2);
      expect(state.session.isLocked, isTrue);
      expect(state.session.initialBalance, 1000);
      expect(state.session.equity, 980);
      expect(state.session.isPlaying, isFalse);
      expect(state.pendingReview, review);
      restored.add(CloseBacktestTrade(state.activeTrades.single.id!));
      restored.add(OpenBacktestSetup());
      await Future<void>.delayed(Duration.zero);
      expect((restored.state as BacktestLoaded).activeTrades, hasLength(1));
      expect((restored.state as BacktestLoaded).session.isLocked, isTrue);
      restored.add(const StepReplayCursor(1));
      restored.add(const AcknowledgeBacktestReview('invalid'));
      await restored.stream.firstWhere(
        (state) => state is BacktestLoaded && state.errorKey != null,
      );
      expect((restored.state as BacktestLoaded).cursor, 2);
      expect((restored.state as BacktestLoaded).session.isLocked, isTrue);
      restored.add(AcknowledgeBacktestReview(review.id));
      await restored.stream.firstWhere(
        (state) => state is BacktestLoaded && !state.session.isLocked,
      );
      expect(
        repository.saved!.simulation.lastAcknowledgedReview?.id,
        review.id,
      );
    },
  );

  test(
    'failed persistence pauses replay and blocks mutation until retry',
    () async {
      final repository = _Repository();
      final bloc = BacktestBloc(
        backtestRepository: repository,
        historyStream: (_) => Stream.value(_candles()),
      );
      addTearDown(bloc.close);
      bloc.add(const StartBacktestSession('BTCUSD', 1000, userId: 'qa-user'));
      await bloc.stream.firstWhere((state) => state is BacktestLoaded);
      repository.failedSaves = 1;
      bloc.add(const StepReplayCursor(1));
      await bloc.stream.firstWhere(
        (state) => state is BacktestLoaded && !state.isSaved,
      );
      bloc.add(const ExecuteBacktestTrade('BUY', 1));
      await Future<void>.delayed(Duration.zero);
      expect((bloc.state as BacktestLoaded).activeTrades, isEmpty);
      expect((bloc.state as BacktestLoaded).session.isPlaying, isFalse);
      bloc.add(RetryBacktestSave());
      await bloc.stream.firstWhere(
        (state) => state is BacktestLoaded && state.isSaved,
      );
      expect(repository.saved!.simulation.replay.cursor, 1);
      bloc.add(const ExecuteBacktestTrade('SELL', 1));
      await bloc.stream.firstWhere(
        (state) => state is BacktestLoaded && state.activeTrades.isNotEmpty,
      );
      expect(
        (bloc.state as BacktestLoaded).activeTrades.single.entryPrice,
        105,
      );
    },
  );

  test('restore rejects a trade opened beyond the replay cursor', () {
    final bars = _candles()
        .take(3)
        .map(
          (candle) => BacktestBar(
            timestamp: candle.timestamp.millisecondsSinceEpoch ~/ 1000,
            open: candle.open,
            high: candle.high,
            low: candle.low,
            close: candle.close,
            volume: candle.volume,
            isClosed: true,
          ),
        )
        .toList();
    final replay = BacktestReplayEngine(
      sessionId: 'session-1',
      symbol: 'BTCUSD',
      sourceId: 'test-history',
      bars: bars,
    )..seek(1);
    final simulation = BacktestSimulationEngine(
      replay: replay,
      initialBalance: 1000,
      maxLossAmount: 100,
      contractSize: 1,
    );
    simulation.openTrade(id: 'future', side: BacktestSide.buy, volume: 1);
    replay.seek(0);
    expect(
      () => BacktestSimulationEngine.restore(
        snapshot: simulation.snapshot,
        bars: bars,
        expectedSessionId: 'session-1',
        expectedSymbol: 'BTCUSD',
        expectedSourceId: 'test-history',
      ),
      throwsFormatException,
    );
  });
}
