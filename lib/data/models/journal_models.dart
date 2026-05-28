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

class HeatmapEntry extends Equatable {
  final int dayOfWeek; // 1=Monday, 7=Sunday
  final int hourSlot;  // 0-23
  final double totalPnL;
  final int tradeCount;

  const HeatmapEntry({
    required this.dayOfWeek,
    required this.hourSlot,
    required this.totalPnL,
    required this.tradeCount,
  });

  @override
  List<Object?> get props => [dayOfWeek, hourSlot, totalPnL, tradeCount];
}

class JournalStats extends Equatable {
  final double totalProfit;
  final double winRate;
  final double profitFactor;
  final String rrRatio;
  final List<double> equityData;
  final int totalTrades;
  final double bestTrade;
  final double worstTrade;
  final double avgProfit;
  final String aiInsight;
  final List<HeatmapEntry> heatmapData;

  const JournalStats({
    required this.totalProfit,
    required this.winRate,
    required this.profitFactor,
    required this.rrRatio,
    required this.equityData,
    this.totalTrades = 0,
    this.bestTrade = 0.0,
    this.worstTrade = 0.0,
    this.avgProfit = 0.0,
    this.aiInsight = '',
    this.heatmapData = const [],
  });

  @override
  List<Object?> get props => [totalProfit, winRate, profitFactor, rrRatio, equityData, totalTrades, bestTrade, worstTrade, avgProfit, aiInsight, heatmapData];
}
