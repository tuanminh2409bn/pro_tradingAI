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
  final List<ChatMessage> chatMessages;
  final bool isRiskConfigured;
  final double spread;
  final double swap;
  final bool isAIChatLoading;
  final bool isTradeExecuting;
  final double dailyPnL;
  final bool isAnalyzing;

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
    this.chatMessages = const [],
    this.isRiskConfigured = false,
    this.spread = 0.0,
    this.swap = 0.0,
    this.isAIChatLoading = false,
    this.isTradeExecuting = false,
    this.dailyPnL = 0.0,
    this.isAnalyzing = false,
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
    List<ChatMessage>? chatMessages,
    bool? isRiskConfigured,
    double? spread,
    double? swap,
    bool? isAIChatLoading,
    bool? isTradeExecuting,
    double? dailyPnL,
    bool? isAnalyzing,
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
      chatMessages: chatMessages ?? this.chatMessages,
      isRiskConfigured: isRiskConfigured ?? this.isRiskConfigured,
      spread: spread ?? this.spread,
      swap: swap ?? this.swap,
      isAIChatLoading: isAIChatLoading ?? this.isAIChatLoading,
      isTradeExecuting: isTradeExecuting ?? this.isTradeExecuting,
      dailyPnL: dailyPnL ?? this.dailyPnL,
      isAnalyzing: isAnalyzing ?? this.isAnalyzing,
    );
  }

  double get totalPnL => positions.fold(0.0, (sum, p) => sum + p.profit);

  @override
  List<Object?> get props => [
    account, currentSignal, currentSymbol, currentTimeframe, candles,
    positions, tradingMode, riskConfig, isCutoffActive, chatMessages,
    isRiskConfigured, spread, swap, isAIChatLoading, isTradeExecuting, dailyPnL,
    isAnalyzing,
  ];
}

class TradingRoomError extends TradingRoomState {
  final String message;
  const TradingRoomError(this.message);

  @override
  List<Object?> get props => [message];
}
