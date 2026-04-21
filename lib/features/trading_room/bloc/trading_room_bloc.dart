import 'dart:async';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'trading_room_event.dart';
import 'trading_room_state.dart';
import '../../../data/models/trading_models.dart';
import '../../../data/repositories/trading_repository.dart';

class TradingRoomBloc extends Bloc<TradingRoomEvent, TradingRoomState> {
  final TradingRepository _tradingRepository;
  StreamSubscription? _candleSubscription;
  StreamSubscription? _accountSubscription;
  StreamSubscription? _signalSubscription;
  List<Candle> _initialCandles = [];

  TradingRoomBloc({required TradingRepository tradingRepository})
      : _tradingRepository = tradingRepository,
        super(TradingRoomInitial()) {
    on<LoadTradingData>(_onLoadTradingData);
    on<UpdateSymbol>(_onUpdateSymbol);
    on<UpdateCandles>(_onUpdateCandles);
    on<UpdateAccount>(_onUpdateAccount);
    on<UpdateSignals>(_onUpdateSignals);
    on<ExecuteTrade>(_onExecuteTrade);
    on<ChangeTimeframe>(_onChangeTimeframe);
  }

  void _onLoadTradingData(LoadTradingData event, Emitter<TradingRoomState> emit) async {
    emit(TradingRoomLoading());
    try {
      _candleSubscription?.cancel();
      _accountSubscription?.cancel();
      _signalSubscription?.cancel();

      _accountSubscription = _tradingRepository.getTradingAccount(event.userId ?? '').listen(
        (account) => add(UpdateAccount(account)),
      );

      _candleSubscription = _tradingRepository.getCandleStream('XAUUSD').listen(
        (candles) => add(UpdateCandles(candles)),
      );

      _signalSubscription = _tradingRepository.getActiveSignals().listen(
        (signals) => add(UpdateSignals(signals)),
      );

      // Give it a short moment to receive the first batch of candles
      await Future.delayed(const Duration(milliseconds: 500));

      emit(TradingRoomLoaded(
        account: const TradingAccount(
          balance: 38204.12,
          equity: 42050.00,
          margin: 840,
          leverage: 500,
          status: 'LIVE',
        ),
        currentSymbol: 'XAUUSD',
        currentTimeframe: '5',
        candles: _initialCandles,
      ));
    } catch (e) {
      emit(TradingRoomError(e.toString()));
    }
  }

  void _onUpdateAccount(UpdateAccount event, Emitter<TradingRoomState> emit) {
    if (state is TradingRoomLoaded) {
      emit((state as TradingRoomLoaded).copyWith(account: event.account));
    }
  }

  void _onUpdateSignals(UpdateSignals event, Emitter<TradingRoomState> emit) {
    if (state is TradingRoomLoaded) {
      final currentState = state as TradingRoomLoaded;
      final currentSignal = event.signals.isNotEmpty ? event.signals.first : currentState.currentSignal;
      emit(currentState.copyWith(currentSignal: currentSignal));
    }
  }

  void _onUpdateCandles(UpdateCandles event, Emitter<TradingRoomState> emit) {
    print('TradingRoomBloc: Received ${event.candles.length} candles');
    if (state is TradingRoomLoaded) {
      emit((state as TradingRoomLoaded).copyWith(candles: event.candles));
    } else {
      _initialCandles = event.candles;
    }
  }

  void _onChangeTimeframe(ChangeTimeframe event, Emitter<TradingRoomState> emit) {
    if (state is TradingRoomLoaded) {
      _tradingRepository.changeTimeframe(event.timeframe);
      emit((state as TradingRoomLoaded).copyWith(currentTimeframe: event.timeframe));
    }
  }

  void _onUpdateSymbol(UpdateSymbol event, Emitter<TradingRoomState> emit) {
    _candleSubscription?.cancel();
    _candleSubscription = _tradingRepository.getCandleStream(event.symbol).listen(
      (candles) => add(UpdateCandles(candles)),
      onError: (e) => print('TradingRoomBloc: Candles stream error for ${event.symbol}: $e'),
    );

    if (state is TradingRoomLoaded) {
      emit((state as TradingRoomLoaded).copyWith(
        currentSymbol: event.symbol,
        candles: [],
      ));
    }
  }

  void _onExecuteTrade(ExecuteTrade event, Emitter<TradingRoomState> emit) async {
    if (state is TradingRoomLoaded) {
      final currentState = state as TradingRoomLoaded;
      final symbol = currentState.currentSymbol;
      
      final success = await _tradingRepository.executeTrade(symbol, event.type, event.lotSize);
      
      if (success) {
        print('Trade executed successfully: ${event.type} $symbol ${event.lotSize}');
      } else {
        print('Trade execution failed.');
      }
    }
  }

  @override
  Future<void> close() {
    _candleSubscription?.cancel();
    _accountSubscription?.cancel();
    _signalSubscription?.cancel();
    return super.close();
  }
}
