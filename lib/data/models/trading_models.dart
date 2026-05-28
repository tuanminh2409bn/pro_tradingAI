import 'package:equatable/equatable.dart';

// ─── Trading Mode Enum ───
enum TradingMode {
  scalping,
  dayTrading,
  swingTrading;

  String get displayName {
    switch (this) {
      case TradingMode.scalping: return 'Scalping';
      case TradingMode.dayTrading: return 'Day Trading';
      case TradingMode.swingTrading: return 'Swing Trading';
    }
  }

  List<String> get timeframes {
    switch (this) {
      case TradingMode.scalping: return ['1', '5', '15'];
      case TradingMode.dayTrading: return ['15', '60', '240'];
      case TradingMode.swingTrading: return ['240', '1D', '1W'];
    }
  }

  List<String> get timeframeLabels {
    switch (this) {
      case TradingMode.scalping: return ['M1', 'M5', 'M15'];
      case TradingMode.dayTrading: return ['M15', 'H1', 'H4'];
      case TradingMode.swingTrading: return ['H4', 'D1', 'W1'];
    }
  }
}

// ─── Trading Account ───
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

// ─── Trading Signal ───
class TradingSignal extends Equatable {
  final String symbol;
  final double entryPrice;
  final double slPrice;
  final List<double> tpPrices;
  final int probability;
  final String type; // 'BUY', 'SELL'
  final String status; // 'ACTIVE', 'PENDING'
  final List<Map<String, dynamic>> layers; // 5-Layer AI data
  final double suggestedLot;

  const TradingSignal({
    required this.symbol,
    required this.entryPrice,
    required this.slPrice,
    required this.tpPrices,
    required this.probability,
    required this.type,
    required this.status,
    this.layers = const [],
    this.suggestedLot = 0.1,
  });

  @override
  List<Object?> get props => [symbol, entryPrice, slPrice, tpPrices, probability, type, status, layers];
}

// ─── Candle ───
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

// ─── Chart Layer Data ───
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

// ─── Position (Open Trade) ───
class Position extends Equatable {
  final String id;
  final String symbol;
  final String type; // 'BUY', 'SELL'
  final double lotSize;
  final double openPrice;
  final double currentPrice;
  final double sl;
  final double tp;
  final List<double> tpLevels;
  final double profit;
  final String status; // 'OPEN', 'CLOSED'
  final String tradingMode;
  final DateTime? openTime;

  const Position({
    required this.id,
    required this.symbol,
    required this.type,
    required this.lotSize,
    required this.openPrice,
    this.currentPrice = 0.0,
    this.sl = 0.0,
    this.tp = 0.0,
    this.tpLevels = const [],
    this.profit = 0.0,
    this.status = 'OPEN',
    this.tradingMode = 'scalping',
    this.openTime,
  });

  Position copyWith({
    double? currentPrice,
    double? profit,
    String? status,
  }) {
    return Position(
      id: id,
      symbol: symbol,
      type: type,
      lotSize: lotSize,
      openPrice: openPrice,
      currentPrice: currentPrice ?? this.currentPrice,
      sl: sl,
      tp: tp,
      tpLevels: tpLevels,
      profit: profit ?? this.profit,
      status: status ?? this.status,
      tradingMode: tradingMode,
      openTime: openTime,
    );
  }

  factory Position.fromMap(Map<String, dynamic> map) {
    return Position(
      id: map['id'] ?? '',
      symbol: map['symbol'] ?? 'XAUUSD',
      type: map['type'] ?? 'BUY',
      lotSize: (map['lotSize'] as num?)?.toDouble() ?? 0.1,
      openPrice: (map['openPrice'] as num?)?.toDouble() ?? 0.0,
      currentPrice: (map['currentPrice'] as num?)?.toDouble() ?? 0.0,
      sl: (map['sl'] as num?)?.toDouble() ?? 0.0,
      tp: (map['tp'] as num?)?.toDouble() ?? 0.0,
      tpLevels: List<double>.from((map['tpLevels'] ?? []).map((e) => (e as num).toDouble())),
      profit: (map['profit'] as num?)?.toDouble() ?? 0.0,
      status: map['status'] ?? 'OPEN',
      tradingMode: map['tradingMode'] ?? 'scalping',
    );
  }

  @override
  List<Object?> get props => [id, symbol, type, lotSize, openPrice, currentPrice, sl, tp, profit, status];
}

// ─── Risk Configuration ───
class RiskConfig extends Equatable {
  final double balance;
  final double riskPerTrade; // percentage
  final double maxDailyLoss; // percentage

  const RiskConfig({
    required this.balance,
    required this.riskPerTrade,
    required this.maxDailyLoss,
  });

  double get riskAmount => balance * riskPerTrade / 100;
  double get maxDailyLossAmount => balance * maxDailyLoss / 100;

  factory RiskConfig.fromMap(Map<String, dynamic> map) {
    return RiskConfig(
      balance: (map['balance'] as num?)?.toDouble() ?? 0.0,
      riskPerTrade: (map['riskPerTrade'] as num?)?.toDouble() ?? 1.0,
      maxDailyLoss: (map['maxDailyLoss'] as num?)?.toDouble() ?? 5.0,
    );
  }

  Map<String, dynamic> toMap() => {
    'balance': balance,
    'riskPerTrade': riskPerTrade,
    'maxDailyLoss': maxDailyLoss,
  };

  @override
  List<Object?> get props => [balance, riskPerTrade, maxDailyLoss];
}

// ─── Chat Message ───
class ChatMessage extends Equatable {
  final String id;
  final String content;
  final bool isUser;
  final DateTime timestamp;

  const ChatMessage({
    required this.id,
    required this.content,
    required this.isUser,
    required this.timestamp,
  });

  @override
  List<Object?> get props => [id, content, isUser, timestamp];
}
