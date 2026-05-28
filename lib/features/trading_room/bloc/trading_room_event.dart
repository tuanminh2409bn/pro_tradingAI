import 'package:equatable/equatable.dart';
import '../../../data/models/trading_models.dart';

abstract class TradingRoomEvent extends Equatable {
  const TradingRoomEvent();

  @override
  List<Object?> get props => [];
}

class LoadTradingData extends TradingRoomEvent {
  final String? userId;
  const LoadTradingData({this.userId});
  
  @override
  List<Object?> get props => [userId];
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
  final String type; // 'BUY' or 'SELL'
  final double lotSize;
  final double entryPrice;
  final double slPrice;
  final List<double> tpPrices;
  const ExecuteTrade({
    required this.type, 
    required this.lotSize,
    this.entryPrice = 0.0,
    this.slPrice = 0.0,
    this.tpPrices = const [],
  });
  
  @override
  List<Object?> get props => [type, lotSize, entryPrice, slPrice, tpPrices];
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
  const ReceiveAIResponse(this.response);

  @override
  List<Object?> get props => [response];
}

class UpdatePositions extends TradingRoomEvent {
  final List<Position> positions;
  const UpdatePositions(this.positions);

  @override
  List<Object?> get props => [positions];
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
