import 'package:equatable/equatable.dart';

class TradingAccount extends Equatable {
  final double balance;
  final double equity;
  final double margin;
  final int leverage;
  final String status; // 'LIVE', 'DEMO'

  const TradingAccount({
    required this.balance,
    required this.equity,
    required this.margin,
    required this.leverage,
    required this.status,
  });

  @override
  List<Object?> get props => [balance, equity, margin, leverage, status];
}

class TradingSignal extends Equatable {
  final String symbol;
  final double entryPrice;
  final double slPrice;
  final List<double> tpPrices;
  final int probability;
  final String type; // 'BUY', 'SELL'
  final String status; // 'ACTIVE', 'PENDING'

  const TradingSignal({
    required this.symbol,
    required this.entryPrice,
    required this.slPrice,
    required this.tpPrices,
    required this.probability,
    required this.type,
    required this.status,
  });

  @override
  List<Object?> get props => [symbol, entryPrice, slPrice, tpPrices, probability, type, status];
}

class Candle extends Equatable {
  final DateTime timestamp;
  final double open;
  final double high;
  final double low;
  final double close;

  const Candle({
    required this.timestamp,
    required this.open,
    required this.high,
    required this.low,
    required this.close,
  });

  @override
  List<Object?> get props => [timestamp, open, high, low, close];
}

class ChartLayerData extends Equatable {
  final List<Map<String, dynamic>> structures; // Resistance/Support levels
  final List<Map<String, dynamic>> traps;      // Liquidity traps
  final List<Map<String, dynamic>> arrows;     // Divergence arrows

  const ChartLayerData({
    required this.structures,
    required this.traps,
    required this.arrows,
  });

  @override
  List<Object?> get props => [structures, traps, arrows];
}
