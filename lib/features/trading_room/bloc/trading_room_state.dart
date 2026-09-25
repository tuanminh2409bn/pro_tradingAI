import 'package:equatable/equatable.dart';
import '../../../data/models/trading_models.dart';

abstract class TradingRoomState extends Equatable {
  const TradingRoomState();

  @override
  List<Object?> get props => [];
}

class TradingRoomInitial extends TradingRoomState {}

class TradingRoomLoading extends TradingRoomState {}

class TradingRoomLoaded extends TradingRoomState {
  final TradingAccount account;
  final TradingSignal? currentSignal;
  final String currentSymbol;
  final String currentTimeframe;
  final List<Candle> candles;

  // New fields for production
  final List<Position> positions;
  final TradingMode tradingMode;
  final RiskConfig? riskConfig;
  final bool isCutoffActive;
  final bool isCutoffStatusAvailable;
  final List<ChatMessage> chatMessages;
  final bool isRiskConfigured;
  final bool isRiskConfigLoaded;
  final double spread;
  final double swap;
  final bool isAIChatLoading;
  final bool isTradeExecuting;
  final double dailyPnL;
  final bool isAnalyzing;
  final bool isLoadingHistory;

  /// Mark prices keyed by symbol — used to MTM positions without chart bleed.
  final Map<String, double> symbolPrices;

  /// Bumps when symbol changes so ExecutionPanel can reset local SL/TP UI.
  final int panelResetNonce;

  /// User-highlighted TP target. TP3 dims TP1/TP2 to 40% on Layer 4.
  final int selectedTakeProfitIndex;

  /// Active scheduled HIGH-impact event with verified time and provenance.
  final RedZoneOverlay? newsRedZone;
  final int actionResultNonce;
  final String actionMessageKey;
  final bool actionSucceeded;
  final bool positionsAvailable;
  final bool positionsStale;

  const TradingRoomLoaded({
    required this.account,
    this.currentSignal,
    required this.currentSymbol,
    this.currentTimeframe = '5',
    this.candles = const [],
    this.positions = const [],
    this.tradingMode = TradingMode.scalping,
    this.riskConfig,
    this.isCutoffActive = false,
    this.isCutoffStatusAvailable = false,
    this.chatMessages = const [],
    this.isRiskConfigured = false,
    this.isRiskConfigLoaded = false,
    this.spread = 0.0,
    this.swap = 0.0,
    this.isAIChatLoading = false,
    this.isTradeExecuting = false,
    this.dailyPnL = 0.0,
    this.isAnalyzing = false,
    this.isLoadingHistory = false,
    this.symbolPrices = const {},
    this.panelResetNonce = 0,
    this.selectedTakeProfitIndex = 2,
    this.newsRedZone,
    this.actionResultNonce = 0,
    this.actionMessageKey = '',
    this.actionSucceeded = false,
    this.positionsAvailable = false,
    this.positionsStale = false,
  });

  TradingRoomLoaded copyWith({
    TradingAccount? account,
    TradingSignal? currentSignal,
    bool clearSignal = false,
    String? currentSymbol,
    String? currentTimeframe,
    List<Candle>? candles,
    List<Position>? positions,
    TradingMode? tradingMode,
    RiskConfig? riskConfig,
    bool? isCutoffActive,
    bool? isCutoffStatusAvailable,
    List<ChatMessage>? chatMessages,
    bool? isRiskConfigured,
    bool? isRiskConfigLoaded,
    double? spread,
    double? swap,
    bool? isAIChatLoading,
    bool? isTradeExecuting,
    double? dailyPnL,
    bool? isAnalyzing,
    bool? isLoadingHistory,
    Map<String, double>? symbolPrices,
    int? panelResetNonce,
    int? selectedTakeProfitIndex,
    RedZoneOverlay? newsRedZone,
    bool clearNewsRedZone = false,
    int? actionResultNonce,
    String? actionMessageKey,
    bool? actionSucceeded,
    bool? positionsAvailable,
    bool? positionsStale,
  }) {
    return TradingRoomLoaded(
      account: account ?? this.account,
      currentSignal: clearSignal ? null : (currentSignal ?? this.currentSignal),
      currentSymbol: currentSymbol ?? this.currentSymbol,
      currentTimeframe: currentTimeframe ?? this.currentTimeframe,
      candles: candles ?? this.candles,
      positions: positions ?? this.positions,
      tradingMode: tradingMode ?? this.tradingMode,
      riskConfig: riskConfig ?? this.riskConfig,
      isCutoffActive: isCutoffActive ?? this.isCutoffActive,
      isCutoffStatusAvailable:
          isCutoffStatusAvailable ?? this.isCutoffStatusAvailable,
      chatMessages: chatMessages ?? this.chatMessages,
      isRiskConfigured: isRiskConfigured ?? this.isRiskConfigured,
      isRiskConfigLoaded: isRiskConfigLoaded ?? this.isRiskConfigLoaded,
      spread: spread ?? this.spread,
      swap: swap ?? this.swap,
      isAIChatLoading: isAIChatLoading ?? this.isAIChatLoading,
      isTradeExecuting: isTradeExecuting ?? this.isTradeExecuting,
      dailyPnL: dailyPnL ?? this.dailyPnL,
      isAnalyzing: isAnalyzing ?? this.isAnalyzing,
      isLoadingHistory: isLoadingHistory ?? this.isLoadingHistory,
      symbolPrices: symbolPrices ?? this.symbolPrices,
      panelResetNonce: panelResetNonce ?? this.panelResetNonce,
      selectedTakeProfitIndex:
          selectedTakeProfitIndex ?? this.selectedTakeProfitIndex,
      newsRedZone: clearNewsRedZone ? null : (newsRedZone ?? this.newsRedZone),
      actionResultNonce: actionResultNonce ?? this.actionResultNonce,
      actionMessageKey: actionMessageKey ?? this.actionMessageKey,
      actionSucceeded: actionSucceeded ?? this.actionSucceeded,
      positionsAvailable: positionsAvailable ?? this.positionsAvailable,
      positionsStale: positionsStale ?? this.positionsStale,
    );
  }

  double get totalPnL => positions.fold(0.0, (sum, p) => sum + p.profit);

  @override
  List<Object?> get props => [
    account,
    currentSignal,
    currentSymbol,
    currentTimeframe,
    candles,
    positions,
    tradingMode,
    riskConfig,
    isCutoffActive,
    isCutoffStatusAvailable,
    chatMessages,
    isRiskConfigured,
    isRiskConfigLoaded,
    spread,
    swap,
    isAIChatLoading,
    isTradeExecuting,
    dailyPnL,
    isAnalyzing,
    isLoadingHistory,
    symbolPrices,
    panelResetNonce,
    selectedTakeProfitIndex,
    newsRedZone,
    actionResultNonce,
    actionMessageKey,
    actionSucceeded,
    positionsAvailable,
    positionsStale,
  ];

  String? get newsRedZoneLabel => newsRedZone?.label;
}

class TradingRoomError extends TradingRoomState {
  final String message;
  const TradingRoomError(this.message);

  @override
  List<Object?> get props => [message];
}
