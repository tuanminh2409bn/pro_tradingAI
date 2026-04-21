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
  final List<Candle> candles;

  const TradingRoomLoaded({
    required this.account,
    this.currentSignal,
    required this.currentSymbol,
    this.candles = const [],
  });

  TradingRoomLoaded copyWith({
    TradingAccount? account,
    TradingSignal? currentSignal,
    String? currentSymbol,
    List<Candle>? candles,
  }) {
    return TradingRoomLoaded(
      account: account ?? this.account,
      currentSignal: currentSignal ?? this.currentSignal,
      currentSymbol: currentSymbol ?? this.currentSymbol,
      candles: candles ?? this.candles,
    );
  }

  @override
  List<Object?> get props => [account, currentSignal, currentSymbol, candles];
}

class TradingRoomError extends TradingRoomState {
  final String message;
  const TradingRoomError(this.message);

  @override
  List<Object?> get props => [message];
}
