import 'package:equatable/equatable.dart';

class BacktestSession extends Equatable {
  final String symbol;
  final DateTime startTime;
  final DateTime endTime;
  final double initialBalance;
  final double currentBalance;
  final double equity;
  final double openPL;
  final int speed; // 1, 5, 10
  final bool isPlaying;
  final bool isLocked;

  const BacktestSession({
    required this.symbol,
    required this.startTime,
    required this.endTime,
    required this.initialBalance,
    required this.currentBalance,
    required this.equity,
    required this.openPL,
    required this.speed,
    required this.isPlaying,
    this.isLocked = false,
  });

  @override
  List<Object?> get props => [symbol, currentBalance, equity, speed, isPlaying, isLocked];
}

class BacktestTrade extends Equatable {
  final String type; // 'BUY', 'SELL'
  final double openPrice;
  final double lotSize;
  final double? sl;
  final double? tp;
  final double currentProfit;

  const BacktestTrade({
    required this.type,
    required this.openPrice,
    required this.lotSize,
    this.sl,
    this.tp,
    required this.currentProfit,
  });

  @override
  List<Object?> get props => [type, openPrice, currentProfit];
}
