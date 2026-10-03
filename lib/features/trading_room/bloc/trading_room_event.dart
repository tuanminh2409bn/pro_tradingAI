import 'package:equatable/equatable.dart';
import '../../../data/models/trading_models.dart';

abstract class TradingRoomEvent extends Equatable {
  const TradingRoomEvent();

  @override
  List<Object?> get props => [];
}

class LoadTradingData extends TradingRoomEvent {
  final String? userId;
  final String? initialSymbol;
  final String? initialTimeframe;
  const LoadTradingData({
    this.userId,
    this.initialSymbol,
    this.initialTimeframe,
  });

  @override
  List<Object?> get props => [userId, initialSymbol, initialTimeframe];
}

class UpdateSymbol extends TradingRoomEvent {
  final String symbol;
  const UpdateSymbol(this.symbol);

  @override
  List<Object?> get props => [symbol];
}

class UpdateCandles extends TradingRoomEvent {
  final List<Candle> candles;
  const UpdateCandles(this.candles);

  @override
  List<Object?> get props => [candles];
}

class UpdateSymbolPrices extends TradingRoomEvent {
  final Map<String, double> prices;
  const UpdateSymbolPrices(this.prices);

  @override
  List<Object?> get props => [prices];
}

class UpdateAccount extends TradingRoomEvent {
  final TradingAccount account;
  const UpdateAccount(this.account);

  @override
  List<Object?> get props => [account];
}

class UpdateSignals extends TradingRoomEvent {
  final List<TradingSignal> signals;
  const UpdateSignals(this.signals);

  @override
  List<Object?> get props => [signals];
}

class ChangeTimeframe extends TradingRoomEvent {
  final String timeframe;
  const ChangeTimeframe(this.timeframe);

  @override
  List<Object?> get props => [timeframe];
}

class ExecuteTrade extends TradingRoomEvent {
  final String signalChartId;
  final String type; // 'BUY' or 'SELL'
  final double lotSize;
  final double entryPrice;
  final double slPrice;
  final List<double> tpPrices;
  final TakeProfitAllocationPlan? takeProfitPlan;
  const ExecuteTrade({
    this.signalChartId = '',
    required this.type,
    required this.lotSize,
    this.entryPrice = 0.0,
    this.slPrice = 0.0,
    this.tpPrices = const [],
    this.takeProfitPlan,
  });

  @override
  List<Object?> get props => [
    signalChartId,
    type,
    lotSize,
    entryPrice,
    slPrice,
    tpPrices,
    takeProfitPlan,
  ];
}

class SelectTakeProfit extends TradingRoomEvent {
  final int targetIndex;

  const SelectTakeProfit(this.targetIndex);

  @override
  List<Object?> get props => [targetIndex];
}

class RequestAnalysis extends TradingRoomEvent {
  const RequestAnalysis();
}

// ─── New Events for Production ───

class CancelAnalysisSpinner extends TradingRoomEvent {
  const CancelAnalysisSpinner();
}

class ChangeTradingMode extends TradingRoomEvent {
  final TradingMode mode;
  const ChangeTradingMode(this.mode);

  @override
  List<Object?> get props => [mode];
}

class SaveRiskConfig extends TradingRoomEvent {
  final RiskConfig config;
  const SaveRiskConfig(this.config);

  @override
  List<Object?> get props => [config];
}

class UpdateRiskConfigLoaded extends TradingRoomEvent {
  final RiskConfig? config;
  const UpdateRiskConfigLoaded(this.config);

  @override
  List<Object?> get props => [config];
}

class UpdateServerCutoff extends TradingRoomEvent {
  final bool active;
  final bool available;
  const UpdateServerCutoff(this.active, {this.available = true});

  @override
  List<Object?> get props => [active, available];
}

class ClosePosition extends TradingRoomEvent {
  final String positionId;
  const ClosePosition(this.positionId);

  @override
  List<Object?> get props => [positionId];
}

class SendAIMessage extends TradingRoomEvent {
  final String message;
  const SendAIMessage(this.message);

  @override
  List<Object?> get props => [message];
}

class ReceiveAIResponse extends TradingRoomEvent {
  final String response;
  final bool isFallback;
  const ReceiveAIResponse(this.response, {this.isFallback = false});

  @override
  List<Object?> get props => [response, isFallback];
}

class UpdatePositions extends TradingRoomEvent {
  final List<Position> positions;
  const UpdatePositions(this.positions);

  @override
  List<Object?> get props => [positions];
}

class PositionRefreshFailed extends TradingRoomEvent {
  const PositionRefreshFailed();
}

class TradeExecuted extends TradingRoomEvent {
  final Position position;
  const TradeExecuted(this.position);

  @override
  List<Object?> get props => [position];
}

class TradeClosed extends TradingRoomEvent {
  final String positionId;
  final double profit;
  const TradeClosed(this.positionId, this.profit);

  @override
  List<Object?> get props => [positionId, profit];
}

// ─── Chat History Events ───

class LoadChatHistory extends TradingRoomEvent {
  const LoadChatHistory();
}

class ChatHistoryLoaded extends TradingRoomEvent {
  final List<ChatMessage> messages;
  const ChatHistoryLoaded(this.messages);

  @override
  List<Object?> get props => [messages];
}

class ClearChatHistory extends TradingRoomEvent {
  const ClearChatHistory();
}

/// Day 6 — inject Layer-5 news_column Red Zone from HIGH-impact headline.
class ApplyNewsRedZone extends TradingRoomEvent {
  final RedZoneOverlay overlay;
  const ApplyNewsRedZone(this.overlay);

  @override
  List<Object?> get props => [overlay];
}

class ClearNewsRedZone extends TradingRoomEvent {
  const ClearNewsRedZone();
}
