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

  TradingRoomBloc({required TradingRepository tradingRepository})
      : _tradingRepository = tradingRepository,
        super(TradingRoomInitial()) {
    on<LoadTradingData>(_onLoadTradingData);
    on<UpdateSymbol>(_onUpdateSymbol);
    on<UpdateCandles>(_onUpdateCandles);
    on<UpdateAccount>(_onUpdateAccount);
    on<UpdateSignals>(_onUpdateSignals);
    on<ExecuteTrade>(_onExecuteTrade);
  }

  void _onLoadTradingData(LoadTradingData event, Emitter<TradingRoomState> emit) async {
    emit(TradingRoomLoading());
    try {
      final userId = event.userId;
      
      _candleSubscription?.cancel();
      _accountSubscription?.cancel();
      _signalSubscription?.cancel();

      // Only subscribe to Firestore if we have a real userId and not just a demo
      if (userId != null && userId.isNotEmpty) {
        _accountSubscription = _tradingRepository.getTradingAccount(userId).listen(
          (account) => add(UpdateAccount(account)),
          onError: (e) => print('TradingRoomBloc: Account stream error: $e'),
        );

        _signalSubscription = _tradingRepository.getActiveSignals().listen(
          (signals) => add(UpdateSignals(signals)),
          onError: (e) => print('TradingRoomBloc: Signals stream error: $e'),
        );
      }

      const defaultAccount = TradingAccount(
        balance: 38204.12,
        equity: 42050.00,
        margin: 840,
        leverage: 500,
        status: 'LIVE',
      );

      const defaultSignal = TradingSignal(
        symbol: 'XAUUSD',
        entryPrice: 2038.50,
        slPrice: 2032.10,
        tpPrices: [2055.00],
        probability: 85,
        type: 'BUY',
        status: 'ACTIVE',
      );

      _candleSubscription = _tradingRepository.getCandleStream('XAUUSD').listen(
        (candles) => add(UpdateCandles(candles)),
        onError: (e) => print('TradingRoomBloc: Candles stream error: $e'),
      );

      emit(const TradingRoomLoaded(
        account: defaultAccount,
        currentSignal: defaultSignal,
        currentSymbol: 'XAUUSD',
        candles: [],
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
    if (state is TradingRoomLoaded) {
      emit((state as TradingRoomLoaded).copyWith(candles: event.candles));
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

  void _onExecuteTrade(ExecuteTrade event, Emitter<TradingRoomState> emit) {
    print('Executing ${event.type} trade with lot size ${event.lotSize}');
  }

  @override
  Future<void> close() {
    _candleSubscription?.cancel();
    _accountSubscription?.cancel();
    _signalSubscription?.cancel();
    return super.close();
  }
}
