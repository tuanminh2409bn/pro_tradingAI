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

class ExecuteTrade extends TradingRoomEvent {
  final String type; // 'BUY' or 'SELL'
  final double lotSize;
  const ExecuteTrade({required this.type, required this.lotSize});
  
  @override
  List<Object?> get props => [type, lotSize];
}
