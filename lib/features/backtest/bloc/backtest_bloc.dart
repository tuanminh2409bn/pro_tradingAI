import 'dart:async';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'backtest_event.dart';
import 'backtest_state.dart';
import '../../../data/repositories/backtest_repository.dart';
import '../../../data/models/backtest_models.dart';
import '../../../data/models/trading_models.dart';

typedef BacktestHistoryStream = Stream<List<Candle>> Function(String symbol);

class BacktestBloc extends Bloc<BacktestEvent, BacktestState> {
  final BacktestRepository _backtestRepository;
  final BacktestHistoryStream _historyStream;
  final void Function()? _disposeHistory;
  Timer? _replayTimer;
  int? _timerSpeed;
  List<BacktestBar> _bars = const [];
  BacktestSimulationEngine? _simulation;
  BacktestSession? _session;
  bool _historySaved = false;
  bool _closing = false;

  BacktestBloc({
    required BacktestRepository backtestRepository,
    required BacktestHistoryStream historyStream,
    void Function()? disposeHistory,
  }) : _backtestRepository = backtestRepository,
       _historyStream = historyStream,
       _disposeHistory = disposeHistory,
       super(BacktestInitial()) {
    // All event types share one queue, including writes and timer ticks.
    on<BacktestEvent>(
      _onEvent,
      transformer: (events, mapper) => events.asyncExpand(mapper),
    );
  }

  Future<void> _onEvent(
    BacktestEvent event,
    Emitter<BacktestState> emit,
  ) async {
    if (_closing) return;
    if (event is StartBacktestSession) {
      await _start(event, emit);
      return;
    }
    if (event is OpenBacktestSetup) {
      if (_simulation?.isLocked == true) return;
      _simulation?.replay.pause();
      _syncReplayTimer();
      if (_simulation != null && !await _persist(emit)) return;
      emit(BacktestInitial());
      return;
    }
    final current = state;
    final simulation = _simulation;
    if (current is! BacktestLoaded || simulation == null) return;
    if (event is RetryBacktestSave) {
      await _persist(emit);
      return;
    }
    if (!current.isSaved) return;
    if (simulation.isLocked && event is! AcknowledgeBacktestReview) return;
    final replay = simulation.replay;
    try {
      if (event is TogglePlayback) {
        if (simulation.isLocked) return;
        replay.isPlaying ? replay.pause() : replay.resume();
      } else if (event is UpdateSpeed) {
        replay.setSpeed(event.speed);
      } else if (event is ExecuteBacktestTrade) {
        if ((event.type != 'BUY' && event.type != 'SELL') ||
            !event.lotSize.isFinite ||
            event.lotSize <= 0) {
          throw ArgumentError('Invalid training order');
        }
        replay.pause();
        simulation.openTrade(
          id: '${replay.sessionId}:trade:${simulation.trades.length + 1}',
          side: event.type == 'BUY' ? BacktestSide.buy : BacktestSide.sell,
          volume: event.lotSize,
        );
      } else if (event is CloseBacktestTrade) {
        if (!simulation.openTrades.any((trade) => trade.id == event.tradeId)) {
          throw StateError('Open training order required');
        }
        replay.pause();
        simulation.closeTrade(event.tradeId);
      } else if (event is AcknowledgeBacktestReview) {
        simulation.acknowledgeReview(event.reviewId);
      } else if (event is SeekReplayCursor) {
        if (!current.canRewind) return;
        replay.seek(event.cursor);
      } else if (event is StepReplayCursor) {
        if (simulation.isLocked) return;
        if (event.direction < 0) {
          if (!current.canRewind) return;
          replay.stepBackward();
        } else if (event.direction > 0) {
          replay.resume();
          simulation.advanceTick();
          replay.pause();
        } else {
          return;
        }
      } else if (event is ReplayTick) {
        if (simulation.isLocked || !simulation.advanceTick()) {
          _syncReplayTimer();
          return;
        }
      } else {
        return;
      }
      await _persist(emit);
    } on ArgumentError {
      emit(_loadedState(errorKey: 'backtest_invalid_action'));
    } on StateError {
      emit(_loadedState(errorKey: 'backtest_invalid_action'));
    } finally {
      _syncReplayTimer();
    }
  }

  Future<void> _start(
    StartBacktestSession event,
    Emitter<BacktestState> emit,
  ) async {
    _replayTimer?.cancel();
    _simulation = null;
    _session = null;
    _historySaved = false;
    emit(BacktestLoading());
    try {
      final userId = event.userId;
      if (userId == null || userId.trim().isEmpty) {
        emit(const BacktestError('backtest_auth_required'));
        return;
      }
      if (!event.initialBalance.isFinite ||
          event.initialBalance <= 0 ||
          !event.maxLossPercent.isFinite ||
          event.maxLossPercent <= 0 ||
          event.maxLossPercent > 100) {
        throw ArgumentError('Invalid simulation settings');
      }
      final recording = event.createNew
          ? null
          : await _backtestRepository.loadRecording(
              userId: userId,
              symbol: event.symbol,
            );
      if (recording != null) {
        _bars = recording.bars;
        _simulation = recording.restore()..replay.pause();
        _historySaved = true;
        final simulation = _simulation!;
        _session = BacktestSession(
          id: simulation.replay.sessionId,
          symbol: simulation.replay.symbol,
          startTime: _date(_bars.first.timestamp),
          endTime: _date(_bars.last.timestamp),
          initialBalance: simulation.initialBalance,
          currentBalance: simulation.balance,
          equity: simulation.equity,
          openPL: simulation.equity - simulation.balance,
          speed: simulation.replay.speed,
          isPlaying: false,
          isLocked: simulation.isLocked,
        );
      } else {
        final candles = await _historyStream(event.symbol)
            .firstWhere((items) => items.length >= 3)
            .timeout(const Duration(seconds: 15));
        _bars = candles
            .take(candles.length - 1)
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
            .toList(growable: false);
        final replay = BacktestReplayEngine(
          sessionId: 'pending',
          symbol: event.symbol,
          sourceId: 'server-websocket:${event.symbol.toUpperCase()}:M5',
          bars: _bars,
        );
        _session = await _backtestRepository.createSession(
          symbol: replay.symbol,
          startTime: _date(_bars.first.timestamp),
          endTime: _date(_bars.last.timestamp),
          balance: event.initialBalance,
          userId: userId,
        );
        _simulation = BacktestSimulationEngine(
          replay: BacktestReplayEngine(
            sessionId: _session!.id!,
            symbol: replay.symbol,
            sourceId: replay.sourceId,
            bars: _bars,
          ),
          initialBalance: event.initialBalance,
          maxLossAmount: event.initialBalance * event.maxLossPercent / 100,
          contractSize: 1,
        );
      }
      await _persist(emit);
    } on BacktestRequestException catch (error) {
      emit(BacktestError(error.errorKey));
    } catch (_) {
      emit(const BacktestError('common_data_unavailable'));
    }
  }

  static DateTime _date(int timestamp) =>
      DateTime.fromMillisecondsSinceEpoch(timestamp * 1000, isUtc: true);

  Future<bool> _persist(Emitter<BacktestState> emit) async {
    final simulation = _simulation!;
    try {
      await _backtestRepository.saveRecording(
        BacktestRecording(bars: _bars, simulation: simulation.snapshot),
        includeHistory: !_historySaved,
      );
      _historySaved = true;
      if (!emit.isDone) emit(_loadedState());
      return true;
    } catch (_) {
      simulation.replay.pause();
      _syncReplayTimer();
      if (!emit.isDone) {
        emit(_loadedState(isSaved: false, errorKey: 'backtest_save_failed'));
      }
      return false;
    }
  }

  BacktestLoaded _loadedState({bool isSaved = true, String? errorKey}) {
    final simulation = _simulation!;
    final replay = simulation.replay;
    final session = _session!;
    return BacktestLoaded(
      session: BacktestSession(
        id: session.id,
        symbol: replay.symbol,
        startTime: session.startTime,
        endTime: session.endTime,
        initialBalance: simulation.initialBalance,
        currentBalance: simulation.balance,
        equity: simulation.equity,
        openPL: simulation.equity - simulation.balance,
        speed: replay.speed,
        isPlaying: replay.isPlaying,
        isLocked: simulation.isLocked,
      ),
      activeTrades: simulation.openTrades
          .map(
            (trade) => BacktestTrade(
              id: trade.id,
              symbol: replay.symbol,
              type: trade.side == BacktestSide.buy ? 'BUY' : 'SELL',
              entryPrice: trade.entryPrice,
              currentPrice: replay.currentBar.close,
              volume: trade.volume,
              profit: trade.floatingPnl(replay.currentBar.close),
              openTime: _date(trade.entryTimestamp),
            ),
          )
          .toList(),
      closedTrades: simulation.trades.where((trade) => !trade.isOpen).toList(),
      pendingReview: simulation.pendingReview,
      visibleBars: replay.visibleBars,
      cursor: replay.cursor,
      totalBars: replay.totalBars,
      historySource: replay.sourceId,
      isSaved: isSaved,
      errorKey: errorKey,
    );
  }

  void _syncReplayTimer() {
    final replay = _simulation?.replay;
    if (replay == null || !replay.isPlaying || _closing) {
      _replayTimer?.cancel();
      _timerSpeed = null;
    } else if (_replayTimer?.isActive != true || _timerSpeed != replay.speed) {
      _replayTimer?.cancel();
      _timerSpeed = replay.speed;
      _replayTimer = Timer.periodic(replay.tickInterval, (_) {
        if (!_closing && !isClosed) add(ReplayTick());
      });
    }
  }

  @override
  Future<void> close() async {
    _closing = true;
    _replayTimer?.cancel();
    try {
      await super.close();
    } finally {
      _simulation?.replay.pause();
      _disposeHistory?.call();
    }
  }
}
