import 'package:equatable/equatable.dart';

class BacktestSession extends Equatable {
  final String? id;
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
    this.id,
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
  List<Object?> get props => [id, symbol, currentBalance, equity, speed, isPlaying, isLocked];
}

class BacktestTrade extends Equatable {
  final String? id;
  final String symbol;
  final String type; // 'BUY', 'SELL'
  final double entryPrice;
  final double currentPrice;
  final double volume;
  final double profit;
  final DateTime openTime;

  // Legacy field aliases for backward compatibility
  double get openPrice => entryPrice;
  double get lotSize => volume;
  double get currentProfit => profit;

  const BacktestTrade({
    this.id,
    this.symbol = '',
    required this.type,
    required this.entryPrice,
    required this.currentPrice,
    required this.volume,
    required this.profit,
    required this.openTime,
  });

  @override
  List<Object?> get props => [id, type, entryPrice, profit];
}
