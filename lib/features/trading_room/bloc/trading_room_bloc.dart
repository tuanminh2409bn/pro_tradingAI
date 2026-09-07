import 'dart:async';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'trading_room_event.dart';
import 'trading_room_state.dart';
import '../../../data/models/trading_models.dart';
import '../../../data/repositories/trading_repository.dart';
import 'package:shared_preferences/shared_preferences.dart';

class TradingRoomBloc extends Bloc<TradingRoomEvent, TradingRoomState> {
  final TradingRepository _tradingRepository;
  StreamSubscription? _candleSubscription;
  StreamSubscription? _accountSubscription;
  StreamSubscription? _signalSubscription;
  StreamSubscription? _pricesSubscription;
  String? _userId;
  Timer? _positionRefreshTimer;

  TradingRoomBloc({required TradingRepository tradingRepository})
    : _tradingRepository = tradingRepository,
      super(TradingRoomInitial()) {
    on<LoadTradingData>(_onLoadTradingData);
    on<UpdateSymbol>(_onUpdateSymbol);
    on<UpdateCandles>(_onUpdateCandles);
    on<UpdateSymbolPrices>(_onUpdateSymbolPrices);
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
    on<UpdateRiskConfigLoaded>(_onUpdateRiskConfigLoaded);
    on<LoadChatHistory>(_onLoadChatHistory);
    on<ChatHistoryLoaded>(_onChatHistoryLoaded);
    on<ClearChatHistory>(_onClearChatHistory);
    on<ApplyNewsRedZone>(_onApplyNewsRedZone);
    on<ClearNewsRedZone>(_onClearNewsRedZone);
  }

  List<Position> _markPositions(
    List<Position> positions,
    Map<String, double> prices, {
    String? preferSymbol,
    double? preferPrice,
  }) {
    return positions.map((p) {
      final sym = p.symbol.toUpperCase();
      double? mark;
      if (preferSymbol != null &&
          preferPrice != null &&
          preferPrice > 0 &&
          sym == preferSymbol.toUpperCase()) {
        mark = preferPrice;
      } else {
        mark = prices[sym];
      }
      if (mark == null || mark <= 0) return p;
      return p.markToMarket(mark);
    }).toList();
  }

  void _onLoadTradingData(
    LoadTradingData event,
    Emitter<TradingRoomState> emit,
  ) {
    // ── Clear stale per-account data when user changes ──────────────
    final newUserId = event.userId ?? '';
    if (_userId != null && _userId != newUserId) {
      // Different user: cancel all subscriptions and reset state fully
      _candleSubscription?.cancel();
      _accountSubscription?.cancel();
      _signalSubscription?.cancel();
      _pricesSubscription?.cancel();
      _positionRefreshTimer?.cancel();
      _userId = null;
    }

    emit(TradingRoomLoading());
    _userId = newUserId;
    try {
      _candleSubscription?.cancel();
      _accountSubscription?.cancel();
      _signalSubscription?.cancel();
      _pricesSubscription?.cancel();

      _accountSubscription = _tradingRepository
          .getTradingAccount(newUserId)
          .listen((account) => add(UpdateAccount(account)));

      const defaultSymbol = 'XAUUSD';
      _tradingRepository.changeSymbol(defaultSymbol);

      _candleSubscription = _tradingRepository
          .getCandleStream(defaultSymbol)
          .listen((candles) => add(UpdateCandles(candles)));

      _pricesSubscription = _tradingRepository.priceBookStream.listen(
        (prices) => add(UpdateSymbolPrices(prices)),
      );

      // Pass userId so each account only receives its own signals
      _signalSubscription = _tradingRepository
          .getActiveSignals(newUserId)
          .listen((signals) => add(UpdateSignals(signals)));

      // Emit initial state with null signal — clears previous account's analysis
      emit(
        TradingRoomLoaded(
          account: const TradingAccount(
            balance: 0.0,
            equity: 0.0,
            margin: 0.0,
            leverage: 500,
            status: 'LIVE',
          ),
          currentSymbol: defaultSymbol,
          currentTimeframe: TradingMode.scalping.executionTf,
          candles: const [],
          positions: const [],
          isRiskConfigured: false,
          currentSignal: null,
          symbolPrices: Map<String, double>.from(
            _tradingRepository.symbolPrices,
          ),
        ),
      );

      // Start position refresh timer (every 10 seconds)
      _startPositionRefreshTimer();

      // Restore saved symbol asynchronously
      _restorePersistedSymbol();

      // Fetch risk config and positions in the background
      if (newUserId.isNotEmpty) {
        _loadRiskAndPositionsInBackground(newUserId);
        // Load chat history
        add(const LoadChatHistory());
      }
    } catch (e) {
      emit(TradingRoomError(e.toString()));
    }
  }

  Future<void> _restorePersistedSymbol() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final savedSymbol = prefs.getString('selected_symbol');
      if (savedSymbol != null && savedSymbol != 'XAUUSD') {
        add(UpdateSymbol(savedSymbol));
      }
    } catch (e) {
      print('TradingRoomBloc: Error restoring symbol: $e');
    }
  }

  Future<void> _loadRiskAndPositionsInBackground(String userId) async {
    try {
      final riskConfig = await _tradingRepository.getRiskConfig(userId);
      add(UpdateRiskConfigLoaded(riskConfig));
    } catch (e) {
      print('TradingRoomBloc: Error loading risk config in background: $e');
    }

    try {
      final positions = await _tradingRepository.getOpenPositions(userId);
      add(UpdatePositions(positions));
    } catch (e) {
      print('TradingRoomBloc: Error loading open positions in background: $e');
    }
  }

  void _onUpdateRiskConfigLoaded(
    UpdateRiskConfigLoaded event,
    Emitter<TradingRoomState> emit,
  ) {
    if (state is TradingRoomLoaded) {
      final currentState = state as TradingRoomLoaded;
      emit(
        currentState.copyWith(
          riskConfig: event.config,
          isRiskConfigured: event.config != null,
          isRiskConfigLoaded: true,
        ),
      );
    }
  }

  void _startPositionRefreshTimer() {
    _positionRefreshTimer?.cancel();
    _positionRefreshTimer = Timer.periodic(const Duration(seconds: 10), (
      _,
    ) async {
      if (_userId != null &&
          _userId!.isNotEmpty &&
          state is TradingRoomLoaded) {
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
    print(
      'TradingRoomBloc: Received ${event.signals.length} active signals from Repository',
    );
    if (state is TradingRoomLoaded) {
      final currentState = state as TradingRoomLoaded;
      // Prefer signal matching the chart symbol; ignore foreign-symbol bleed
      TradingSignal? currentSignal;
      for (final s in event.signals) {
        if (s.symbol.toUpperCase() ==
            currentState.currentSymbol.toUpperCase()) {
          currentSignal = s;
          break;
        }
      }
      if (currentSignal != null &&
          currentState.newsRedZoneLabel != null &&
          currentState.newsRedZoneLabel!.isNotEmpty) {
        currentSignal = currentSignal.withNewsRedZone(
          currentState.newsRedZoneLabel!,
        );
      }
      emit(
        currentState.copyWith(
          currentSignal: currentSignal,
          clearSignal: currentSignal == null,
          isAnalyzing: false,
        ),
      );
    }
  }

  void _onApplyNewsRedZone(
    ApplyNewsRedZone event,
    Emitter<TradingRoomState> emit,
  ) {
    if (state is! TradingRoomLoaded) return;
    final current = state as TradingRoomLoaded;
    final signal = current.currentSignal;
    emit(
      current.copyWith(
        newsRedZoneLabel: event.label,
        currentSignal: signal != null
            ? signal.withNewsRedZone(event.label)
            : signal,
      ),
    );
  }

  void _onClearNewsRedZone(
    ClearNewsRedZone event,
    Emitter<TradingRoomState> emit,
  ) {
    if (state is! TradingRoomLoaded) return;
    final current = state as TradingRoomLoaded;
    final signal = current.currentSignal;
    emit(
      current.copyWith(
        clearNewsRedZone: true,
        currentSignal: signal == null
            ? null
            : signal.copyWith(
                layers: TradingSignal.layersWithoutNewsColumn(signal.layers),
              ),
      ),
    );
  }

  void _onUpdateCandles(UpdateCandles event, Emitter<TradingRoomState> emit) {
    print('TradingRoomBloc: Received ${event.candles.length} candles');
    if (state is TradingRoomLoaded) {
      final currentState = state as TradingRoomLoaded;
      final prices = Map<String, double>.from(currentState.symbolPrices);
      double? chartPrice;
      if (event.candles.isNotEmpty) {
        chartPrice = event.candles.last.close;
        prices[currentState.currentSymbol.toUpperCase()] = chartPrice;
      }
      final marked = _markPositions(
        currentState.positions,
        prices,
        preferSymbol: currentState.currentSymbol,
        preferPrice: chartPrice,
      );
      emit(
        currentState.copyWith(
          candles: event.candles,
          symbolPrices: prices,
          positions: marked,
        ),
      );
    }
  }

  void _onUpdateSymbolPrices(
    UpdateSymbolPrices event,
    Emitter<TradingRoomState> emit,
  ) {
    if (state is! TradingRoomLoaded) return;
    final currentState = state as TradingRoomLoaded;
    final prices = Map<String, double>.from(currentState.symbolPrices)
      ..addAll(event.prices);
    final marked = _markPositions(currentState.positions, prices);
    emit(currentState.copyWith(symbolPrices: prices, positions: marked));
  }

  void _onChangeTimeframe(
    ChangeTimeframe event,
    Emitter<TradingRoomState> emit,
  ) {
    if (state is TradingRoomLoaded) {
      final currentState = state as TradingRoomLoaded;
      if (!currentState.tradingMode.allowsTimeframe(event.timeframe)) {
        print(
          'TradingRoomBloc: TF ${event.timeframe} blocked for ${currentState.tradingMode.name}',
        );
        return;
      }
      _tradingRepository.changeTimeframe(event.timeframe);
      emit(currentState.copyWith(currentTimeframe: event.timeframe));
    }
  }

  void _onUpdateSymbol(
    UpdateSymbol event,
    Emitter<TradingRoomState> emit,
  ) async {
    _tradingRepository.changeSymbol(event.symbol);

    // Save persisted symbol
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('selected_symbol', event.symbol);
    } catch (e) {
      print('TradingRoomBloc: Error saving symbol: $e');
    }

    _candleSubscription?.cancel();
    _candleSubscription = _tradingRepository
        .getCandleStream(event.symbol)
        .listen(
          (candles) => add(UpdateCandles(candles)),
          onError: (e) => print(
            'TradingRoomBloc: Candles stream error for ${event.symbol}: $e',
          ),
        );

    if (state is TradingRoomLoaded) {
      final currentState = state as TradingRoomLoaded;
      final signalMatches =
          currentState.currentSignal?.symbol.toUpperCase() ==
          event.symbol.toUpperCase();
      // Keep existing positions; remake MTM from price book (no chart bleed)
      final marked = _markPositions(
        currentState.positions,
        currentState.symbolPrices,
      );
      emit(
        currentState.copyWith(
          currentSymbol: event.symbol,
          candles: [],
          clearSignal: !signalMatches,
          positions: marked,
          panelResetNonce: currentState.panelResetNonce + 1,
        ),
      );
    }
  }

  void _onExecuteTrade(
    ExecuteTrade event,
    Emitter<TradingRoomState> emit,
  ) async {
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
        print(
          'Trade executed successfully: ${event.type} ${currentState.currentSymbol} ${event.lotSize}',
        );
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
      emit(
        currentState.copyWith(
          positions: updatedPositions,
          isTradeExecuting: false,
        ),
      );
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
        shouldCutoff =
            newDailyPnL.abs() >= currentState.riskConfig!.maxDailyLossAmount;
      }

      emit(
        currentState.copyWith(
          positions: updatedPositions,
          dailyPnL: newDailyPnL,
          isCutoffActive: shouldCutoff,
        ),
      );
    }
  }

  void _onClosePosition(
    ClosePosition event,
    Emitter<TradingRoomState> emit,
  ) async {
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

  void _onChangeTradingMode(
    ChangeTradingMode event,
    Emitter<TradingRoomState> emit,
  ) {
    if (state is TradingRoomLoaded) {
      final currentState = state as TradingRoomLoaded;
      // Switch to the first timeframe of the new mode
      final newTimeframe = event.mode.timeframes.first;
      _tradingRepository.changeTimeframe(newTimeframe);
      emit(
        currentState.copyWith(
          tradingMode: event.mode,
          currentTimeframe: newTimeframe,
        ),
      );
    }
  }

  void _onSaveRiskConfig(
    SaveRiskConfig event,
    Emitter<TradingRoomState> emit,
  ) async {
    if (state is TradingRoomLoaded) {
      final currentState = state as TradingRoomLoaded;

      // Save to server
      await _tradingRepository.saveRiskConfig(_userId ?? '', event.config);

      emit(
        currentState.copyWith(
          riskConfig: event.config,
          isRiskConfigured: true,
          isRiskConfigLoaded: true,
        ),
      );
    }
  }

  void _onSendAIMessage(
    SendAIMessage event,
    Emitter<TradingRoomState> emit,
  ) async {
    if (state is TradingRoomLoaded) {
      final currentState = state as TradingRoomLoaded;

      // Add user message
      final userMsg = ChatMessage(
        id: 'user_${DateTime.now().millisecondsSinceEpoch}',
        content: event.message,
        isUser: true,
        timestamp: DateTime.now(),
      );

      emit(
        currentState.copyWith(
          chatMessages: [...currentState.chatMessages, userMsg],
          isAIChatLoading: true,
        ),
      );

      // Persist to Firestore
      if (_userId != null && _userId!.isNotEmpty) {
        _tradingRepository.saveChatMessage(
          userId: _userId!,
          chatType: 'trading_room',
          message: userMsg,
        );
      }

      // Send to AI
      final result = await _tradingRepository.sendAIChat(
        message: event.message,
        symbol: currentState.currentSymbol,
        timeframe: currentState.currentTimeframe,
        userId: _userId ?? '',
      );

      add(ReceiveAIResponse(result.response, isFallback: result.fallback));
    }
  }

  void _onReceiveAIResponse(
    ReceiveAIResponse event,
    Emitter<TradingRoomState> emit,
  ) {
    if (state is TradingRoomLoaded) {
      final currentState = state as TradingRoomLoaded;

      final aiMsg = ChatMessage(
        id: 'ai_${DateTime.now().millisecondsSinceEpoch}',
        content: event.response,
        isUser: false,
        timestamp: DateTime.now(),
        isFallback: event.isFallback,
      );

      emit(
        currentState.copyWith(
          chatMessages: [...currentState.chatMessages, aiMsg],
          isAIChatLoading: false,
        ),
      );

      // Persist to Firestore
      if (_userId != null && _userId!.isNotEmpty) {
        _tradingRepository.saveChatMessage(
          userId: _userId!,
          chatType: 'trading_room',
          message: aiMsg,
        );
      }
    }
  }

  void _onUpdatePositions(
    UpdatePositions event,
    Emitter<TradingRoomState> emit,
  ) {
    if (state is TradingRoomLoaded) {
      final currentState = state as TradingRoomLoaded;
      // Server already returns symbol-bound PnL; still re-apply local price book
      final marked = _markPositions(event.positions, currentState.symbolPrices);
      emit(currentState.copyWith(positions: marked));
    }
  }

  void _onRequestAnalysis(
    RequestAnalysis event,
    Emitter<TradingRoomState> emit,
  ) async {
    if (state is TradingRoomLoaded) {
      final currentState = state as TradingRoomLoaded;
      emit(currentState.copyWith(isAnalyzing: true));
      try {
        // Cap payload size for Firestore (keep newest bars)
        final candles = currentState.candles;
        final slice = candles.length > 180
            ? candles.sublist(candles.length - 180)
            : candles;
        final candlesExecution = slice
            .map(
              (c) => {
                't': c.timestamp.millisecondsSinceEpoch ~/ 1000,
                'o': c.open,
                'h': c.high,
                'l': c.low,
                'c': c.close,
              },
            )
            .toList();
        final risk = currentState.riskConfig;
        final account = currentState.account;
        await _tradingRepository.requestAnalysis(
          currentState.currentSymbol,
          currentState.currentTimeframe,
          userId: _userId ?? '',
          tradingMode: currentState.tradingMode.name,
          candlesExecution: candlesExecution,
          accountContext: {
            'balance': risk?.balance ?? account.balance,
            'equity': account.equity,
            'leverage': account.leverage,
            'risk_per_trade': risk?.riskPerTrade,
            'max_daily_loss': risk?.maxDailyLoss,
            'symbol': currentState.currentSymbol,
            'timeframe': currentState.currentTimeframe,
          },
        );
      } catch (_) {}

      Future.delayed(const Duration(seconds: 12), () {
        if (state is TradingRoomLoaded &&
            (state as TradingRoomLoaded).isAnalyzing) {
          add(const CancelAnalysisSpinner());
        }
      });
    }
  }

  void _onCancelAnalysisSpinner(
    CancelAnalysisSpinner event,
    Emitter<TradingRoomState> emit,
  ) {
    if (state is TradingRoomLoaded) {
      final currentState = state as TradingRoomLoaded;
      if (currentState.isAnalyzing) {
        emit(currentState.copyWith(isAnalyzing: false));
      }
    }
  }

  // ─── Chat History Handlers ───

  Future<void> _onLoadChatHistory(
    LoadChatHistory event,
    Emitter<TradingRoomState> emit,
  ) async {
    if (state is TradingRoomLoaded && _userId != null && _userId!.isNotEmpty) {
      final currentState = state as TradingRoomLoaded;
      emit(currentState.copyWith(isLoadingHistory: true));
      final messages = await _tradingRepository.loadChatHistory(
        userId: _userId!,
        chatType: 'trading_room',
      );
      if (state is TradingRoomLoaded) {
        emit(
          (state as TradingRoomLoaded).copyWith(
            chatMessages: messages,
            isLoadingHistory: false,
          ),
        );
      }
    }
  }

  void _onChatHistoryLoaded(
    ChatHistoryLoaded event,
    Emitter<TradingRoomState> emit,
  ) {
    if (state is TradingRoomLoaded) {
      emit((state as TradingRoomLoaded).copyWith(chatMessages: event.messages));
    }
  }

  Future<void> _onClearChatHistory(
    ClearChatHistory event,
    Emitter<TradingRoomState> emit,
  ) async {
    if (state is TradingRoomLoaded) {
      final currentState = state as TradingRoomLoaded;
      emit(currentState.copyWith(chatMessages: []));
      if (_userId != null && _userId!.isNotEmpty) {
        await _tradingRepository.clearChatHistory(
          userId: _userId!,
          chatType: 'trading_room',
        );
      }
    }
  }

  @override
  Future<void> close() {
    _candleSubscription?.cancel();
    _accountSubscription?.cancel();
    _signalSubscription?.cancel();
    _pricesSubscription?.cancel();
    _positionRefreshTimer?.cancel();
    return super.close();
  }
}
