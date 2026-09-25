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
  StreamSubscription? _tradesSubscription;
  Timer? _replayTimer;
  BacktestReplayEngine? _replay;

  BacktestBloc({
    required BacktestRepository backtestRepository,
    required BacktestHistoryStream historyStream,
  }) : _backtestRepository = backtestRepository,
       _historyStream = historyStream,
       super(BacktestInitial()) {
    on<StartBacktestSession>(_onStartSession);
    on<TogglePlayback>(_onTogglePlayback);
    on<UpdateSpeed>(_onUpdateSpeed);
    on<ExecuteBacktestTrade>(_onExecuteTrade);
    on<UpdateBacktestTrades>(_onUpdateTrades);
    on<ReplayTick>(_onReplayTick);
    on<SeekReplayCursor>(_onSeekReplayCursor);
    on<StepReplayCursor>(_onStepReplayCursor);
  }

  Future<void> _onStartSession(
    StartBacktestSession event,
    Emitter<BacktestState> emit,
  ) async {
    emit(BacktestLoading());
    try {
      if (event.userId == null || event.userId!.trim().isEmpty) {
        emit(const BacktestError('backtest_auth_required'));
        return;
      }
      final candles = await _historyStream(event.symbol)
          .firstWhere((items) => items.length >= 3)
          .timeout(const Duration(seconds: 15));
      final closedCandles = candles
          .take(candles.length - 1)
          .toList(growable: false);
      final bars = closedCandles
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
      final session = await _backtestRepository.createSession(
        symbol: event.symbol,
        startTime: closedCandles.first.timestamp,
        endTime: closedCandles.last.timestamp,
        balance: event.initialBalance,
        userId: event.userId!,
      );

      _replay = BacktestReplayEngine(
        sessionId: session.id ?? 'current',
        symbol: event.symbol,
        sourceId: 'server-websocket:${event.symbol.toUpperCase()}:M5',
        bars: bars,
      );

      _tradesSubscription?.cancel();
      _tradesSubscription = _backtestRepository
          .getActiveTrades(session.id ?? 'current')
          .listen((trades) => add(UpdateBacktestTrades(trades)));

      emit(_loadedState(session: session));
    } catch (_) {
      emit(const BacktestError('common_data_unavailable'));
    }
  }

  void _onTogglePlayback(TogglePlayback event, Emitter<BacktestState> emit) {
    if (state is BacktestLoaded) {
      final current = state as BacktestLoaded;
      final replay = _replay;
      if (replay == null) return;
      replay.isPlaying ? replay.pause() : replay.resume();
      _syncReplayTimer();
      emit(
        _loadedState(
          session: current.session,
          activeTrades: current.activeTrades,
        ),
      );
    }
  }

  void _onUpdateSpeed(UpdateSpeed event, Emitter<BacktestState> emit) {
    if (state is BacktestLoaded) {
      final current = state as BacktestLoaded;
      final replay = _replay;
      if (replay == null) return;
      replay.setSpeed(event.speed);
      _syncReplayTimer();
      emit(
        _loadedState(
          session: current.session,
          activeTrades: current.activeTrades,
        ),
      );
    }
  }

  void _onExecuteTrade(
    ExecuteBacktestTrade event,
    Emitter<BacktestState> emit,
  ) {
    // Logic to open trade in simulation
  }

  void _onUpdateTrades(
    UpdateBacktestTrades event,
    Emitter<BacktestState> emit,
  ) {
    if (state is BacktestLoaded) {
      emit((state as BacktestLoaded).copyWith(activeTrades: event.trades));
    }
  }

  void _onReplayTick(ReplayTick event, Emitter<BacktestState> emit) {
    final current = state;
    final replay = _replay;
    if (current is! BacktestLoaded || replay == null) return;
    replay.advanceTick();
    _syncReplayTimer();
    emit(
      _loadedState(
        session: current.session,
        activeTrades: current.activeTrades,
      ),
    );
  }

  void _onSeekReplayCursor(
    SeekReplayCursor event,
    Emitter<BacktestState> emit,
  ) {
    final current = state;
    final replay = _replay;
    if (current is! BacktestLoaded || replay == null) return;
    replay.seek(event.cursor);
    _syncReplayTimer();
    emit(
      _loadedState(
        session: current.session,
        activeTrades: current.activeTrades,
      ),
    );
  }

  void _onStepReplayCursor(
    StepReplayCursor event,
    Emitter<BacktestState> emit,
  ) {
    final current = state;
    final replay = _replay;
    if (current is! BacktestLoaded || replay == null) return;
    if (event.direction < 0) {
      replay.stepBackward();
    } else if (event.direction > 0) {
      replay.stepForward();
    }
    _syncReplayTimer();
    emit(
      _loadedState(
        session: current.session,
        activeTrades: current.activeTrades,
      ),
    );
  }

  BacktestLoaded _loadedState({
    required BacktestSession session,
    List<BacktestTrade> activeTrades = const [],
  }) {
    final replay = _replay!;
    return BacktestLoaded(
      session: BacktestSession(
        id: session.id,
        symbol: session.symbol,
        startTime: session.startTime,
        endTime: session.endTime,
        initialBalance: session.initialBalance,
        currentBalance: session.currentBalance,
        equity: session.equity,
        openPL: session.openPL,
        speed: replay.speed,
        isPlaying: replay.isPlaying,
        isLocked: session.isLocked,
      ),
      activeTrades: activeTrades,
      visibleBars: replay.visibleBars,
      cursor: replay.cursor,
      totalBars: replay.totalBars,
      historySource: replay.sourceId,
    );
  }

  void _syncReplayTimer() {
    _replayTimer?.cancel();
    final replay = _replay;
    if (replay != null && replay.isPlaying) {
      _replayTimer = Timer.periodic(
        replay.tickInterval,
        (_) => add(ReplayTick()),
      );
    }
  }

  @override
  Future<void> close() {
    _replayTimer?.cancel();
    _tradesSubscription?.cancel();
    return super.close();
  }
}
