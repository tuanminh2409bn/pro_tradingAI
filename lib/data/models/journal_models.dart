import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:equatable/equatable.dart';

class BrokerTradeMetrics extends Equatable {
  final double? swap;
  final double? commission;
  final double? slippage;
  final String source;
  final String currency;

  const BrokerTradeMetrics({
    required this.swap,
    required this.commission,
    required this.slippage,
    required this.source,
    required this.currency,
  });

  static BrokerTradeMetrics? fromFirestoreMap(Map<String, dynamic> data) {
    final rawEnvelope = data['brokerMetrics'];
    final envelope = rawEnvelope is Map
        ? Map<String, dynamic>.fromEntries(
            rawEnvelope.entries
                .where((entry) => entry.key is String)
                .map((entry) => MapEntry(entry.key as String, entry.value)),
          )
        : const <String, dynamic>{};

    String? nonEmptyString(Object? value) {
      if (value is! String) return null;
      final normalized = value.trim();
      return normalized.isEmpty ? null : normalized;
    }

    double? finiteNumber(Object? value) {
      if (value is! num) return null;
      final normalized = value.toDouble();
      return normalized.isFinite ? normalized : null;
    }

    final source = nonEmptyString(
      envelope['source'] ?? data['metricsSource'] ?? data['metricSource'],
    );
    final currency = nonEmptyString(
      envelope['currency'] ?? data['metricsCurrency'] ?? data['metricCurrency'],
    )?.toUpperCase();
    if (source == null || currency == null) return null;

    final swap = finiteNumber(envelope['swap'] ?? data['swap']);
    final commission = finiteNumber(
      envelope['commission'] ?? data['commission'],
    );
    final slippage = finiteNumber(envelope['slippage'] ?? data['slippage']);
    if (swap == null && commission == null && slippage == null) return null;

    return BrokerTradeMetrics(
      swap: swap,
      commission: commission,
      slippage: slippage,
      source: source,
      currency: currency,
    );
  }

  @override
  List<Object?> get props => [swap, commission, slippage, source, currency];
}

class TradeRecord extends Equatable {
  final String symbol;
  final String action; // 'LONG', 'SHORT'
  final double lotSize;
  final double entryPrice;
  final double exitPrice;
  final double netProfit;
  final DateTime closeTime;
  final BrokerTradeMetrics? brokerMetrics;
  final String? executionMode;

  double? get swap => brokerMetrics?.swap;
  double? get commission => brokerMetrics?.commission;
  double? get slippage => brokerMetrics?.slippage;
  String? get metricSource => brokerMetrics?.source;
  String? get metricCurrency => brokerMetrics?.currency;
  bool get isPaperTrade => executionMode == 'paper';

  const TradeRecord({
    required this.symbol,
    required this.action,
    required this.lotSize,
    required this.entryPrice,
    required this.exitPrice,
    required this.netProfit,
    required this.closeTime,
    this.brokerMetrics,
    this.executionMode,
  });

  /// Day 6 — normalize trade docs written by `/api/trade` + `/api/trade/close`.
  /// Accepts both journal fields (`action`/`entryPrice`/`netProfit`) and
  /// execution fields (`type`/`openPrice`/`profit`). Skips still-OPEN trades.
  static TradeRecord? fromFirestoreMap(Map<String, dynamic> data) {
    final status = (data['status'] ?? '').toString().toUpperCase();
    final hasClose =
        data['closeTime'] != null ||
        data['exitPrice'] != null ||
        data['closePrice'] != null;
    if (status == 'OPEN') return null;
    if (status.isNotEmpty && status != 'CLOSED' && !hasClose) return null;
    if (!hasClose && status != 'CLOSED') return null;

    final rawAction = (data['action'] ?? data['type'] ?? 'BUY')
        .toString()
        .toUpperCase();
    final action = (rawAction == 'BUY' || rawAction == 'LONG')
        ? 'LONG'
        : (rawAction == 'SELL' || rawAction == 'SHORT')
        ? 'SHORT'
        : rawAction;

    DateTime closeTime = DateTime.now();
    final ct = data['closeTime'];
    if (ct is Timestamp) {
      closeTime = ct.toDate();
    } else if (ct is DateTime) {
      closeTime = ct;
    } else {
      final ot = data['openTime'];
      if (ot is Timestamp) closeTime = ot.toDate();
    }

    final rawExecutionMode = data['executionMode'] ?? data['tradeMode'];
    final executionMode = rawExecutionMode is String
        ? rawExecutionMode.trim().toLowerCase()
        : data['isPaperTrade'] == true
        ? 'paper'
        : null;

    return TradeRecord(
      symbol: (data['symbol'] ?? '').toString(),
      action: action,
      lotSize: (data['lotSize'] ?? data['volume'] ?? 0).toDouble(),
      entryPrice: (data['entryPrice'] ?? data['openPrice'] ?? 0).toDouble(),
      exitPrice: (data['exitPrice'] ?? data['closePrice'] ?? 0).toDouble(),
      netProfit: (data['netProfit'] ?? data['profit'] ?? 0).toDouble(),
      closeTime: closeTime,
      brokerMetrics: BrokerTradeMetrics.fromFirestoreMap(data),
      executionMode: executionMode?.isEmpty == true ? null : executionMode,
    );
  }

  @override
  List<Object?> get props => [
    symbol,
    action,
    lotSize,
    entryPrice,
    exitPrice,
    netProfit,
    closeTime,
    brokerMetrics,
    executionMode,
  ];
}

class HeatmapEntry extends Equatable {
  final int dayOfWeek; // 1=Monday, 7=Sunday
  final int hourSlot; // 0-23
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
  List<Object?> get props => [
    totalProfit,
    winRate,
    profitFactor,
    rrRatio,
    equityData,
    totalTrades,
    bestTrade,
    worstTrade,
    avgProfit,
    aiInsight,
    heatmapData,
  ];
}
