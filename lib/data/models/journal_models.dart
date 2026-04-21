import 'package:equatable/equatable.dart';

class TradeRecord extends Equatable {
  final String symbol;
  final String action; // 'LONG', 'SHORT'
  final double lotSize;
  final double entryPrice;
  final double exitPrice;
  final double netProfit;
  final DateTime closeTime;
  final double swap;
  final double slippage;

  const TradeRecord({
    required this.symbol,
    required this.action,
    required this.lotSize,
    required this.entryPrice,
    required this.exitPrice,
    required this.netProfit,
    required this.closeTime,
    required this.swap,
    required this.slippage,
  });

  @override
  List<Object?> get props => [symbol, action, lotSize, entryPrice, exitPrice, netProfit, closeTime];
}

class JournalStats extends Equatable {
  final double totalProfit;
  final double winRate;
  final double profitFactor;
  final String rrRatio;
  final List<double> equityData;

  const JournalStats({
    required this.totalProfit,
    required this.winRate,
    required this.profitFactor,
    required this.rrRatio,
    required this.equityData,
  });

  @override
  List<Object?> get props => [totalProfit, winRate, profitFactor, rrRatio, equityData];
}
