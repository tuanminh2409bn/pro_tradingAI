import 'dart:async';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'trading_room_event.dart';
import 'trading_room_state.dart';
import '../../../data/models/trading_models.dart';
import '../../../data/repositories/trading_repository.dart';
import 'package:shared_preferences/shared_preferences.dart';

List<Position> markPositionsBySymbol(
  List<Position> positions,
  Map<String, double> prices, {
  String? preferSymbol,
  double? preferPrice,
}) {
  return positions
      .map((position) {
        final symbol = position.symbol.toUpperCase();
        final mark =
            preferSymbol != null &&
                preferPrice != null &&
                preferPrice > 0 &&
                symbol == preferSymbol.toUpperCase()
            ? preferPrice
            : prices[symbol];
        if (mark == null || mark <= 0) return position;
        return position.markToMarket(mark);
      })
      .toList(growable: false);
}

TradingRoomLoaded stateAfterSymbolChange(
  TradingRoomLoaded current,
  String symbol,
) {
  final signalMatches =
      current.currentSignal?.symbol.toUpperCase() == symbol.toUpperCase();
  return current.copyWith(
    currentSymbol: symbol,
    isAnalyzing: false,
    candles: const [],
    clearSignal: !signalMatches,
    positions: markPositionsBySymbol(current.positions, current.symbolPrices),
    panelResetNonce: current.panelResetNonce + 1,
    selectedTakeProfitIndex: 2,
  );
}

TradingRoomLoaded stateAfterTimeframeChange(
  TradingRoomLoaded current,
  String timeframe,
) {
  if (current.tradingMode.normalizeTimeframe(current.currentTimeframe) ==
      current.tradingMode.normalizeTimeframe(timeframe)) {
    return current;
  }
  return current.copyWith(
    currentTimeframe: timeframe,
    clearSignal: true,
    isAnalyzing: false,
  );
}

double dailyPnLIncludingFloating(
  double realizedPnL,
  List<Position> openPositions,
) => openPositions.fold<double>(realizedPnL, (sum, item) => sum + item.profit);

bool shouldActivateDailyLossCutoff({
  required bool alreadyActive,
  required double realizedPnL,
  required List<Position> openPositions,
  required RiskConfig? riskConfig,
}) {
  if (alreadyActive) return true;
  if (riskConfig == null || riskConfig.maxDailyLossAmount <= 0) return false;
  final total = dailyPnLIncludingFloating(realizedPnL, openPositions);
  return total < 0 && total.abs() >= riskConfig.maxDailyLossAmount;
}

bool isSignalForCurrentChart(TradingRoomLoaded state, TradingSignal? signal) {
  if (signal == null ||
      signal.symbol.toUpperCase() != state.currentSymbol.toUpperCase()) {
    return false;
  }
  final chartId = signal.chartId;
  final timestampSeparator = chartId?.lastIndexOf('_') ?? -1;
  final timeframeSeparator = timestampSeparator > 0
      ? chartId!.lastIndexOf('_', timestampSeparator - 1)
      : -1;
  final chartSymbol = timeframeSeparator > 0
      ? chartId!.substring(0, timeframeSeparator)
      : null;
  final chartTimeframe = timeframeSeparator > 0
      ? chartId!.substring(timeframeSeparator + 1, timestampSeparator)
      : null;
  return chartSymbol?.toUpperCase() == state.currentSymbol.toUpperCase() &&
      chartTimeframe != null &&
      state.tradingMode.normalizeTimeframe(chartTimeframe) ==
          state.tradingMode.normalizeTimeframe(state.currentTimeframe);
}

/// Local consistency guard; server authorization must still validate each order.
bool isClientTradeRequestAllowed(TradingRoomLoaded state, ExecuteTrade event) {
  final signal = state.currentSignal;
  if (state.isCutoffActive ||
      state.isTradeExecuting ||
      signal == null ||
      !signal.canExecute ||
      signal.contractError != null ||
      !isSignalForCurrentChart(state, signal) ||
      event.signalChartId != signal.chartId ||
      event.type != signal.type ||
      !event.lotSize.isFinite ||
      event.lotSize <= 0 ||
      !event.entryPrice.isFinite ||
      !event.slPrice.isFinite ||
      event.entryPrice != signal.entryPrice ||
      event.slPrice != signal.slPrice) {
    return false;
  }
  final plan = event.takeProfitPlan;
  final targets = plan == null
      ? signal.tpPrices
      : plan.legs.map((leg) => signal.tpPrices[leg.targetIndex]).toList();
  if (plan != null && (plan.totalVolume - event.lotSize).abs() > 1e-8) {
    return false;
  }
  if (event.tpPrices.length != targets.length) return false;
  for (var i = 0; i < targets.length; i++) {
    if (!event.tpPrices[i].isFinite ||
        event.tpPrices[i] != targets[i] ||
        (plan != null && plan.legs[i].targetPrice != targets[i])) {
      return false;
    }
  }
  return true;
}

class TradingRoomBloc extends Bloc<TradingRoomEvent, TradingRoomState> {
  final TradingRepository _tradingRepository;
  StreamSubscription? _candleSubscription;
  StreamSubscription? _accountSubscription;
  StreamSubscription? _signalSubscription;
  StreamSubscription? _pricesSubscription;
  String? _userId;
  bool _serverCutoffLoaded = false;
  Timer? _positionRefreshTimer;
  int _analysisRequestNonce = 0;

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
    on<SelectTakeProfit>(_onSelectTakeProfit);
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
    on<PositionRefreshFailed>(_onPositionRefreshFailed);
    on<TradeExecuted>(_onTradeExecuted);
    on<TradeClosed>(_onTradeClosed);
    on<UpdateRiskConfigLoaded>(_onUpdateRiskConfigLoaded);
    on<UpdateServerCutoff>(_onUpdateServerCutoff);
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
    return markPositionsBySymbol(
      positions,
      prices,
      preferSymbol: preferSymbol,
      preferPrice: preferPrice,
    );
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
    _analysisRequestNonce++;
    _userId = newUserId;
    _serverCutoffLoaded = false;
    try {
      _candleSubscription?.cancel();
      _accountSubscription?.cancel();
      _signalSubscription?.cancel();
      _pricesSubscription?.cancel();

      _accountSubscription = _tradingRepository
          .getTradingAccount(newUserId)
          .listen((account) => add(UpdateAccount(account)));

      final requestedSymbol = event.initialSymbol?.trim().toUpperCase();
      final hasChartTarget =
          requestedSymbol != null &&
          RegExp(r'^[A-Z0-9]{3,16}$').hasMatch(requestedSymbol);
      final defaultSymbol = hasChartTarget ? requestedSymbol : 'XAUUSD';
      final requestedTimeframe = TradingMode.scalping.normalizeTimeframe(
        event.initialTimeframe?.trim().toUpperCase() ?? '5',
      );
      final initialMode = TradingMode.values.firstWhere(
        (mode) => mode.allowsTimeframe(requestedTimeframe),
        orElse: () => TradingMode.scalping,
      );
      final initialTimeframe = initialMode.allowsTimeframe(requestedTimeframe)
          ? requestedTimeframe
          : initialMode.executionTf;
      _tradingRepository.changeSymbol(defaultSymbol);
      _tradingRepository.changeTimeframe(initialTimeframe);

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
            leverage: 0,
            status: 'UNAVAILABLE',
            source: 'unavailable',
          ),
          currentSymbol: defaultSymbol,
          currentTimeframe: initialTimeframe,
          tradingMode: initialMode,
          candles: const [],
          positions: const [],
          isRiskConfigured: false,
          isCutoffActive: newUserId.isNotEmpty,
          currentSignal: null,
          symbolPrices: Map<String, double>.from(
            _tradingRepository.symbolPrices,
          ),
        ),
      );

      // Start position refresh timer (every 10 seconds)
      _startPositionRefreshTimer();

      // Restore saved symbol asynchronously
      if (!hasChartTarget) {
        _restorePersistedSymbol();
      }

      // Fetch risk config and positions in the background
      if (newUserId.isNotEmpty) {
        _loadRiskAndPositionsInBackground(newUserId);
        // Load chat history
        add(const LoadChatHistory());
      }
    } catch (_) {
      emit(const TradingRoomError('common_data_unavailable'));
    }
  }

  Future<void> _restorePersistedSymbol() async {
    try {
      final nonce = _analysisRequestNonce;
      final prefs = await SharedPreferences.getInstance();
      if (isClosed || nonce != _analysisRequestNonce) return;
      final savedSymbol = prefs.getString('selected_symbol');
      if (savedSymbol != null && savedSymbol != 'XAUUSD') {
        add(UpdateSymbol(savedSymbol));
      }
    } catch (_) {}
  }

  Future<void> _loadRiskAndPositionsInBackground(String userId) async {
    try {
      final cutoff = await _tradingRepository.getDailyCutoffStatus(userId);
      add(UpdateServerCutoff(cutoff.active));
    } catch (_) {
      add(const UpdateServerCutoff(true, available: false));
    }

    try {
      final riskConfig = await _tradingRepository.getRiskConfig(userId);
      add(UpdateRiskConfigLoaded(riskConfig));
    } catch (_) {}

    try {
      final positions = await _tradingRepository.getOpenPositions(userId);
      add(UpdatePositions(positions));
    } catch (_) {
      add(const PositionRefreshFailed());
    }
  }

  void _onUpdateServerCutoff(
    UpdateServerCutoff event,
    Emitter<TradingRoomState> emit,
  ) {
    final current = state;
    if (current is! TradingRoomLoaded) return;
    final active =
        event.active ||
        shouldActivateDailyLossCutoff(
          alreadyActive: _serverCutoffLoaded && current.isCutoffActive,
          realizedPnL: current.dailyPnL,
          openPositions: current.positions,
          riskConfig: current.riskConfig,
        );
    _serverCutoffLoaded = event.available;
    emit(
      current.copyWith(
        isCutoffActive: active,
        isCutoffStatusAvailable: event.available,
      ),
    );
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
        try {
          final positions = await _tradingRepository.getOpenPositions(_userId!);
          add(UpdatePositions(positions));
        } catch (_) {
          add(const PositionRefreshFailed());
        }
      }
    });
  }

  void _onUpdateAccount(UpdateAccount event, Emitter<TradingRoomState> emit) {
    if (state is TradingRoomLoaded) {
      emit((state as TradingRoomLoaded).copyWith(account: event.account));
    }
  }

  void _onUpdateSignals(UpdateSignals event, Emitter<TradingRoomState> emit) {
    if (state is TradingRoomLoaded) {
      final currentState = state as TradingRoomLoaded;
      // Prefer signal matching the chart symbol; ignore foreign-symbol bleed
      TradingSignal? currentSignal;
      for (final s in event.signals) {
        if (isSignalForCurrentChart(currentState, s)) {
          currentSignal = s;
          break;
        }
      }
      if (currentSignal != null && currentState.newsRedZone != null) {
        currentSignal = currentSignal.withNewsRedZone(
          currentState.newsRedZone!,
        );
      }
      emit(
        currentState.copyWith(
          currentSignal: currentSignal,
          clearSignal: currentSignal == null,
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
        newsRedZone: event.overlay,
        currentSignal: signal != null
            ? signal.withNewsRedZone(event.overlay)
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
        currentSignal: signal?.copyWith(
          layers: TradingSignal.layersWithoutNewsColumn(
            signal.layers,
            sourceId: current.newsRedZone?.evidence['source_id'] as String?,
          ),
        ),
      ),
    );
  }

  void _onUpdateCandles(UpdateCandles event, Emitter<TradingRoomState> emit) {
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
          positionsAvailable: true,
          positionsStale: false,
          isCutoffActive: shouldActivateDailyLossCutoff(
            alreadyActive: currentState.isCutoffActive,
            realizedPnL: currentState.dailyPnL,
            openPositions: marked,
            riskConfig: currentState.riskConfig,
          ),
        ),
      );
    }
  }

  void _onPositionRefreshFailed(
    PositionRefreshFailed event,
    Emitter<TradingRoomState> emit,
  ) {
    final current = state;
    if (current is TradingRoomLoaded) {
      emit(current.copyWith(positionsStale: true));
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
    emit(
      currentState.copyWith(
        symbolPrices: prices,
        positions: marked,
        isCutoffActive: shouldActivateDailyLossCutoff(
          alreadyActive: currentState.isCutoffActive,
          realizedPnL: currentState.dailyPnL,
          openPositions: marked,
          riskConfig: currentState.riskConfig,
        ),
      ),
    );
  }

  void _onChangeTimeframe(
    ChangeTimeframe event,
    Emitter<TradingRoomState> emit,
  ) {
    if (state is TradingRoomLoaded) {
      final currentState = state as TradingRoomLoaded;
      if (!currentState.tradingMode.allowsTimeframe(event.timeframe)) {
        return;
      }
      final normalized = currentState.tradingMode.normalizeTimeframe(
        event.timeframe,
      );
      final nextState = stateAfterTimeframeChange(currentState, normalized);
      if (identical(nextState, currentState)) return;
      _tradingRepository.changeTimeframe(normalized);
      emit(nextState);
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
    } catch (_) {}

    _candleSubscription?.cancel();
    _candleSubscription = _tradingRepository
        .getCandleStream(event.symbol)
        .listen((candles) => add(UpdateCandles(candles)), onError: (_) {});

    if (state is TradingRoomLoaded) {
      final currentState = state as TradingRoomLoaded;
      emit(stateAfterSymbolChange(currentState, event.symbol));
    }
  }

  void _onExecuteTrade(
    ExecuteTrade event,
    Emitter<TradingRoomState> emit,
  ) async {
    if (state is TradingRoomLoaded) {
      final currentState = state as TradingRoomLoaded;

      if (!isClientTradeRequestAllowed(currentState, event)) {
        return;
      }

      emit(currentState.copyWith(isTradeExecuting: true));
      try {
        if (event.takeProfitPlan != null) {
          final positions = await _tradingRepository
              .executePartialTakeProfitTrade(
                signalId: currentState.currentSignal?.signalId ?? '',
                signalChartId: event.signalChartId,
                symbol: currentState.currentSymbol,
                type: event.type,
                entryPrice: event.entryPrice,
                slPrice: event.slPrice,
                plan: event.takeProfitPlan!,
                userId: _userId ?? '',
                tradingMode: currentState.tradingMode.wireName,
              );
          final current = state;
          if (current is! TradingRoomLoaded) return;
          final isComplete =
              positions.length == event.takeProfitPlan!.legs.length;
          emit(
            current.copyWith(
              positions: [...current.positions, ...positions],
              isTradeExecuting: false,
              actionResultNonce: current.actionResultNonce + 1,
              actionMessageKey: positions.isEmpty
                  ? 'tr_trade_failed'
                  : isComplete
                  ? 'tr_trade_executed'
                  : 'tr_trade_partial',
              actionSucceeded: isComplete,
            ),
          );
          return;
        }

        final position = await _tradingRepository.executeTrade(
          signalId: currentState.currentSignal?.signalId ?? '',
          signalChartId: event.signalChartId,
          symbol: currentState.currentSymbol,
          type: event.type,
          lotSize: event.lotSize,
          entryPrice: event.entryPrice,
          slPrice: event.slPrice,
          tpPrices: event.tpPrices,
          userId: _userId ?? '',
          tradingMode: currentState.tradingMode.wireName,
        );

        if (position != null) {
          add(TradeExecuted(position));
        } else {
          _emitActionResult(
            emit,
            succeeded: false,
            messageKey: 'tr_trade_failed',
            isTradeExecuting: false,
          );
        }
      } catch (_) {
        _emitActionResult(
          emit,
          succeeded: false,
          messageKey: 'tr_trade_failed',
          isTradeExecuting: false,
        );
      }
    }
  }

  void _onSelectTakeProfit(
    SelectTakeProfit event,
    Emitter<TradingRoomState> emit,
  ) {
    if (state is! TradingRoomLoaded ||
        event.targetIndex < 0 ||
        event.targetIndex > 2) {
      return;
    }
    emit(
      (state as TradingRoomLoaded).copyWith(
        selectedTakeProfitIndex: event.targetIndex,
      ),
    );
  }

  void _onTradeExecuted(TradeExecuted event, Emitter<TradingRoomState> emit) {
    if (state is TradingRoomLoaded) {
      final currentState = state as TradingRoomLoaded;
      final updatedPositions = [...currentState.positions, event.position];
      emit(
        currentState.copyWith(
          positions: updatedPositions,
          isTradeExecuting: false,
          actionResultNonce: currentState.actionResultNonce + 1,
          actionMessageKey: 'tr_trade_executed',
          actionSucceeded: true,
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

      emit(
        currentState.copyWith(
          positions: updatedPositions,
          dailyPnL: newDailyPnL,
          isCutoffActive: shouldActivateDailyLossCutoff(
            alreadyActive: currentState.isCutoffActive,
            realizedPnL: newDailyPnL,
            openPositions: updatedPositions,
            riskConfig: currentState.riskConfig,
          ),
          actionResultNonce: currentState.actionResultNonce + 1,
          actionMessageKey: 'tr_trade_closed',
          actionSucceeded: true,
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
      } else {
        _emitActionResult(
          emit,
          succeeded: false,
          messageKey: 'tr_trade_close_failed',
        );
      }
    }
  }

  void _emitActionResult(
    Emitter<TradingRoomState> emit, {
    required bool succeeded,
    required String messageKey,
    bool? isTradeExecuting,
  }) {
    final current = state;
    if (current is! TradingRoomLoaded) return;
    emit(
      current.copyWith(
        isTradeExecuting: isTradeExecuting,
        actionResultNonce: current.actionResultNonce + 1,
        actionMessageKey: messageKey,
        actionSucceeded: succeeded,
      ),
    );
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
          isAnalyzing: false,
          clearSignal: true,
        ),
      );
    }
  }

  void _onSaveRiskConfig(
    SaveRiskConfig event,
    Emitter<TradingRoomState> emit,
  ) async {
    if (state is TradingRoomLoaded) {
      try {
        await _tradingRepository.saveRiskConfig(_userId ?? '', event.config);
        final current = state;
        if (current is! TradingRoomLoaded) return;
        emit(
          current.copyWith(
            riskConfig: event.config,
            isRiskConfigured: true,
            isRiskConfigLoaded: true,
            actionResultNonce: current.actionResultNonce + 1,
            actionMessageKey: 'tr_risk_saved',
            actionSucceeded: true,
          ),
        );
        try {
          final cutoff = await _tradingRepository.getDailyCutoffStatus(
            _userId ?? '',
          );
          add(UpdateServerCutoff(cutoff.active));
        } catch (_) {
          add(const UpdateServerCutoff(true, available: false));
        }
      } catch (_) {
        final current = state;
        if (current is! TradingRoomLoaded) return;
        emit(
          current.copyWith(
            actionResultNonce: current.actionResultNonce + 1,
            actionMessageKey: 'tr_risk_save_failed',
            actionSucceeded: false,
          ),
        );
      }
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
        unawaited(
          _saveChatMessageBestEffort(userId: _userId!, message: userMsg),
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
        unawaited(_saveChatMessageBestEffort(userId: _userId!, message: aiMsg));
      }
    }
  }

  Future<void> _saveChatMessageBestEffort({
    required String userId,
    required ChatMessage message,
  }) async {
    try {
      await _tradingRepository.saveChatMessage(
        userId: userId,
        chatType: 'trading_room',
        message: message,
      );
    } catch (_) {
      // The current response remains useful if history persistence fails.
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
      emit(
        currentState.copyWith(
          positions: marked,
          isCutoffActive: shouldActivateDailyLossCutoff(
            alreadyActive: currentState.isCutoffActive,
            realizedPnL: currentState.dailyPnL,
            openPositions: marked,
            riskConfig: currentState.riskConfig,
          ),
        ),
      );
    }
  }

  void _onRequestAnalysis(
    RequestAnalysis event,
    Emitter<TradingRoomState> emit,
  ) async {
    if (state is TradingRoomLoaded) {
      final currentState = state as TradingRoomLoaded;
      if (currentState.isCutoffActive || currentState.isAnalyzing) return;
      final requestNonce = ++_analysisRequestNonce;
      bool isCurrentRequest() {
        final current = state;
        return !emit.isDone &&
            requestNonce == _analysisRequestNonce &&
            current is TradingRoomLoaded &&
            current.currentSymbol == currentState.currentSymbol &&
            current.currentTimeframe == currentState.currentTimeframe &&
            current.tradingMode == currentState.tradingMode;
      }

      emit(currentState.copyWith(isAnalyzing: true));
      try {
        await _tradingRepository.requestAnalysis(
          currentState.currentSymbol,
          currentState.currentTimeframe,
          userId: _userId ?? '',
          tradingMode: currentState.tradingMode.wireName,
        );
        final current = state;
        if (current is TradingRoomLoaded && isCurrentRequest()) {
          emit(
            current.copyWith(
              isAnalyzing: false,
              actionResultNonce: current.actionResultNonce + 1,
              actionMessageKey: 'tr_analysis_requested',
              actionSucceeded: true,
            ),
          );
        }
      } catch (error) {
        final current = state;
        if (current is TradingRoomLoaded && isCurrentRequest()) {
          emit(
            current.copyWith(
              isAnalyzing: false,
              actionResultNonce: current.actionResultNonce + 1,
              actionMessageKey: error is AnalysisRequestFailure
                  ? error.messageKey
                  : 'tr_analysis_request_failed',
              actionSucceeded: false,
            ),
          );
        }
        return;
      }
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
      List<ChatMessage> messages;
      try {
        messages = await _tradingRepository.loadChatHistory(
          userId: _userId!,
          chatType: 'trading_room',
        );
      } catch (_) {
        final current = state;
        if (current is TradingRoomLoaded) {
          emit(current.copyWith(isLoadingHistory: false));
        }
        return;
      }
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
      if (_userId != null && _userId!.isNotEmpty) {
        try {
          await _tradingRepository.clearChatHistory(
            userId: _userId!,
            chatType: 'trading_room',
          );
        } catch (_) {
          return;
        }
      }
      final current = state;
      if (current is TradingRoomLoaded) {
        emit(current.copyWith(chatMessages: []));
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
