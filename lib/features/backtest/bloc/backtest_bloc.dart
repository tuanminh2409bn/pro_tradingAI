import 'dart:async';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'backtest_event.dart';
import 'backtest_state.dart';
import '../../../data/repositories/backtest_repository.dart';
import '../../../data/models/backtest_models.dart';

class BacktestBloc extends Bloc<BacktestEvent, BacktestState> {
  final BacktestRepository _backtestRepository;
  StreamSubscription? _tradesSubscription;

  BacktestBloc({required BacktestRepository backtestRepository})
      : _backtestRepository = backtestRepository,
        super(BacktestInitial()) {
    on<StartBacktestSession>(_onStartSession);
    on<TogglePlayback>(_onTogglePlayback);
    on<UpdateSpeed>(_onUpdateSpeed);
    on<ExecuteBacktestTrade>(_onExecuteTrade);
    on<UpdateBacktestTrades>(_onUpdateTrades);
  }

  Future<void> _onStartSession(StartBacktestSession event, Emitter<BacktestState> emit) async {
    emit(BacktestLoading());
    try {
      final session = await _backtestRepository.createSession(
        symbol: event.symbol,
        startTime: DateTime.now().subtract(const Duration(days: 30)),
        endTime: DateTime.now(),
        balance: event.initialBalance,
      );

      _tradesSubscription?.cancel();
      _tradesSubscription = _backtestRepository.getActiveTrades('current').listen(
        (trades) => add(UpdateBacktestTrades(trades)),
      );

      emit(BacktestLoaded(session: session));
    } catch (e) {
      emit(BacktestError(e.toString()));
    }
  }

  void _onTogglePlayback(TogglePlayback event, Emitter<BacktestState> emit) {
    if (state is BacktestLoaded) {
      final current = state as BacktestLoaded;
      final updatedSession = BacktestSession(
        symbol: current.session.symbol,
        startTime: current.session.startTime,
        endTime: current.session.endTime,
        initialBalance: current.session.initialBalance,
        currentBalance: current.session.currentBalance,
        equity: current.session.equity,
        openPL: current.session.openPL,
        speed: current.session.speed,
        isPlaying: !current.session.isPlaying,
        isLocked: current.session.isLocked,
      );
      emit(current.copyWith(session: updatedSession));
    }
  }

  void _onUpdateSpeed(UpdateSpeed event, Emitter<BacktestState> emit) {
    if (state is BacktestLoaded) {
      final current = state as BacktestLoaded;
      final updatedSession = BacktestSession(
        symbol: current.session.symbol,
        startTime: current.session.startTime,
        endTime: current.session.endTime,
        initialBalance: current.session.initialBalance,
        currentBalance: current.session.currentBalance,
        equity: current.session.equity,
        openPL: current.session.openPL,
        speed: event.speed,
        isPlaying: current.session.isPlaying,
        isLocked: current.session.isLocked,
      );
      emit(current.copyWith(session: updatedSession));
    }
  }

  void _onExecuteTrade(ExecuteBacktestTrade event, Emitter<BacktestState> emit) {
    // Logic to open trade in simulation
  }

  void _onUpdateTrades(UpdateBacktestTrades event, Emitter<BacktestState> emit) {
    if (state is BacktestLoaded) {
      emit((state as BacktestLoaded).copyWith(activeTrades: event.trades));
    }
  }

  @override
  Future<void> close() {
    _tradesSubscription?.cancel();
    return super.close();
  }
}
