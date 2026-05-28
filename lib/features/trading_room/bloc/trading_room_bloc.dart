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
  String? _userId;
  Timer? _positionRefreshTimer;

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
    on<RequestAnalysis>(_onRequestAnalysis);
    on<CancelAnalysisSpinner>(_onCancelAnalysisSpinner);
    // New event handlers
    on<ChangeTradingMode>(_onChangeTradingMode);
    on<SaveRiskConfig>(_onSaveRiskConfig);
    on<ClosePosition>(_onClosePosition);
    on<SendAIMessage>(_onSendAIMessage);
    on<ReceiveAIResponse>(_onReceiveAIResponse);
    on<UpdatePositions>(_onUpdatePositions);
    on<TradeExecuted>(_onTradeExecuted);
    on<TradeClosed>(_onTradeClosed);
  }

  void _onLoadTradingData(LoadTradingData event, Emitter<TradingRoomState> emit) async {
    emit(TradingRoomLoading());
    _userId = event.userId;
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

      // Load risk config
      RiskConfig? riskConfig;
      bool isRiskConfigured = false;
      if (event.userId != null && event.userId!.isNotEmpty) {
        riskConfig = await _tradingRepository.getRiskConfig(event.userId!);
        isRiskConfigured = riskConfig != null;
      }

      // Load open positions
      List<Position> positions = [];
      if (event.userId != null && event.userId!.isNotEmpty) {
        positions = await _tradingRepository.getOpenPositions(event.userId!);
      }

      // Give it a short moment to receive the first batch of candles
      await Future.delayed(const Duration(milliseconds: 500));

      emit(TradingRoomLoaded(
        account: const TradingAccount(
          balance: 0.0,
          equity: 0.0,
          margin: 0.0,
          leverage: 500,
          status: 'LIVE',
        ),
        currentSymbol: 'XAUUSD',
        currentTimeframe: '5',
        candles: _initialCandles,
        riskConfig: riskConfig,
        isRiskConfigured: isRiskConfigured,
        positions: positions,
      ));

      // Start position refresh timer (every 10 seconds)
      _startPositionRefreshTimer();
    } catch (e) {
      emit(TradingRoomError(e.toString()));
    }
  }

  void _startPositionRefreshTimer() {
    _positionRefreshTimer?.cancel();
    _positionRefreshTimer = Timer.periodic(const Duration(seconds: 10), (_) async {
      if (_userId != null && _userId!.isNotEmpty && state is TradingRoomLoaded) {
        final positions = await _tradingRepository.getOpenPositions(_userId!);
        add(UpdatePositions(positions));
      }
    });
  }

  void _onUpdateAccount(UpdateAccount event, Emitter<TradingRoomState> emit) {
    if (state is TradingRoomLoaded) {
      emit((state as TradingRoomLoaded).copyWith(account: event.account));
    }
  }

  void _onUpdateSignals(UpdateSignals event, Emitter<TradingRoomState> emit) {
    print('TradingRoomBloc: Received ${event.signals.length} active signals from Repository');
    if (state is TradingRoomLoaded) {
      final currentState = state as TradingRoomLoaded;
      final currentSignal = event.signals.isNotEmpty ? event.signals.first : null;
      emit(currentState.copyWith(
        currentSignal: currentSignal,
        isAnalyzing: false,
      ));
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
    _tradingRepository.changeSymbol(event.symbol);
    
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
      
      // Check circuit breaker
      if (currentState.isCutoffActive) {
        print('TradingRoomBloc: Trade blocked by circuit breaker');
        return;
      }

      emit(currentState.copyWith(isTradeExecuting: true));
      
      final position = await _tradingRepository.executeTrade(
        symbol: currentState.currentSymbol,
        type: event.type,
        lotSize: event.lotSize,
        entryPrice: event.entryPrice,
        slPrice: event.slPrice,
        tpPrices: event.tpPrices,
        userId: _userId ?? '',
        tradingMode: currentState.tradingMode.name,
      );
      
      if (position != null) {
        print('Trade executed successfully: ${event.type} ${currentState.currentSymbol} ${event.lotSize}');
        add(TradeExecuted(position));
      } else {
        print('Trade execution failed.');
        emit(currentState.copyWith(isTradeExecuting: false));
      }
    }
  }

  void _onTradeExecuted(TradeExecuted event, Emitter<TradingRoomState> emit) {
    if (state is TradingRoomLoaded) {
      final currentState = state as TradingRoomLoaded;
      final updatedPositions = [...currentState.positions, event.position];
      emit(currentState.copyWith(
        positions: updatedPositions,
        isTradeExecuting: false,
      ));
    }
  }

  void _onTradeClosed(TradeClosed event, Emitter<TradingRoomState> emit) {
    if (state is TradingRoomLoaded) {
      final currentState = state as TradingRoomLoaded;
      final updatedPositions = currentState.positions
          .where((p) => p.id != event.positionId)
          .toList();
      final newDailyPnL = currentState.dailyPnL + event.profit;
      
      // Check circuit breaker: if daily PnL exceeds max daily loss
      bool shouldCutoff = false;
      if (currentState.riskConfig != null && newDailyPnL < 0) {
        shouldCutoff = newDailyPnL.abs() >= currentState.riskConfig!.maxDailyLossAmount;
      }
      
      emit(currentState.copyWith(
        positions: updatedPositions,
        dailyPnL: newDailyPnL,
        isCutoffActive: shouldCutoff,
      ));
    }
  }

  void _onClosePosition(ClosePosition event, Emitter<TradingRoomState> emit) async {
    if (state is TradingRoomLoaded) {
      final profit = await _tradingRepository.closeTrade(
        event.positionId, 
        userId: _userId ?? '',
      );
      
      if (profit != null) {
        add(TradeClosed(event.positionId, profit));
      }
    }
  }

  void _onChangeTradingMode(ChangeTradingMode event, Emitter<TradingRoomState> emit) {
    if (state is TradingRoomLoaded) {
      final currentState = state as TradingRoomLoaded;
      // Switch to the first timeframe of the new mode
      final newTimeframe = event.mode.timeframes.first;
      _tradingRepository.changeTimeframe(newTimeframe);
      emit(currentState.copyWith(
        tradingMode: event.mode,
        currentTimeframe: newTimeframe,
      ));
    }
  }

  void _onSaveRiskConfig(SaveRiskConfig event, Emitter<TradingRoomState> emit) async {
    if (state is TradingRoomLoaded) {
      final currentState = state as TradingRoomLoaded;
      
      // Save to server
      await _tradingRepository.saveRiskConfig(_userId ?? '', event.config);
      
      emit(currentState.copyWith(
        riskConfig: event.config,
        isRiskConfigured: true,
      ));
    }
  }

  void _onSendAIMessage(SendAIMessage event, Emitter<TradingRoomState> emit) async {
    if (state is TradingRoomLoaded) {
      final currentState = state as TradingRoomLoaded;
      
      // Add user message
      final userMsg = ChatMessage(
        id: 'user_${DateTime.now().millisecondsSinceEpoch}',
        content: event.message,
        isUser: true,
        timestamp: DateTime.now(),
      );
      
      emit(currentState.copyWith(
        chatMessages: [...currentState.chatMessages, userMsg],
        isAIChatLoading: true,
      ));
      
      // Send to AI
      final response = await _tradingRepository.sendAIChat(
        message: event.message,
        symbol: currentState.currentSymbol,
        timeframe: currentState.currentTimeframe,
        userId: _userId ?? '',
      );
      
      add(ReceiveAIResponse(response));
    }
  }

  void _onReceiveAIResponse(ReceiveAIResponse event, Emitter<TradingRoomState> emit) {
    if (state is TradingRoomLoaded) {
      final currentState = state as TradingRoomLoaded;
      
      final aiMsg = ChatMessage(
        id: 'ai_${DateTime.now().millisecondsSinceEpoch}',
        content: event.response,
        isUser: false,
        timestamp: DateTime.now(),
      );
      
      emit(currentState.copyWith(
        chatMessages: [...currentState.chatMessages, aiMsg],
        isAIChatLoading: false,
      ));
    }
  }

  void _onUpdatePositions(UpdatePositions event, Emitter<TradingRoomState> emit) {
    if (state is TradingRoomLoaded) {
      emit((state as TradingRoomLoaded).copyWith(positions: event.positions));
    }
  }

  void _onRequestAnalysis(RequestAnalysis event, Emitter<TradingRoomState> emit) async {
    if (state is TradingRoomLoaded) {
      final currentState = state as TradingRoomLoaded;
      // Show analyzing spinner
      emit(currentState.copyWith(isAnalyzing: true));
      try {
        await _tradingRepository.requestAnalysis(
          currentState.currentSymbol,
          currentState.currentTimeframe
        );
      } catch (_) {}
      
      // Auto-timeout after 12 seconds in case signals don't update
      Future.delayed(const Duration(seconds: 12), () {
        if (state is TradingRoomLoaded && (state as TradingRoomLoaded).isAnalyzing) {
          add(const CancelAnalysisSpinner());
        }
      });
    }
  }

  void _onCancelAnalysisSpinner(CancelAnalysisSpinner event, Emitter<TradingRoomState> emit) {
    if (state is TradingRoomLoaded) {
      final currentState = state as TradingRoomLoaded;
      if (currentState.isAnalyzing) {
        emit(currentState.copyWith(isAnalyzing: false));
      }
    }
  }

  @override
  Future<void> close() {
    _candleSubscription?.cancel();
    _accountSubscription?.cancel();
    _signalSubscription?.cancel();
    _positionRefreshTimer?.cancel();
    return super.close();
  }
}
