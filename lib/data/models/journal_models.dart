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
    final rawStatus = data['status'];
    if (rawStatus != null && rawStatus is! String) return null;
    final status = (rawStatus as String?)?.trim().toUpperCase() ?? '';
    if (status.isNotEmpty && status != 'CLOSED') return null;

    final rawSymbol = data['symbol'];
    final sourceAction = data['action'] ?? data['type'];
    if (rawSymbol is! String || sourceAction is! String) return null;
    final symbol = rawSymbol.trim().toUpperCase();
    if (symbol.isEmpty) return null;
    final rawAction = sourceAction.trim().toUpperCase();
    final action = (rawAction == 'BUY' || rawAction == 'LONG')
        ? 'LONG'
        : (rawAction == 'SELL' || rawAction == 'SHORT')
        ? 'SHORT'
        : null;
    if (action == null) return null;

    double? finiteNumber(Object? value) {
      if (value is! num) return null;
      final number = value.toDouble();
      return number.isFinite ? number : null;
    }

    final closeTime = _journalCloseTime(data['closeTime']);
    final entryPrice = finiteNumber(data['entryPrice'] ?? data['openPrice']);
    final exitPrice = finiteNumber(data['exitPrice'] ?? data['closePrice']);
    final netProfit = finiteNumber(data['netProfit'] ?? data['profit']);
    final rawSize = data['lotSize'] ?? data['volume'];
    // Zero is the existing unknown-size sentinel, never a measured zero lot.
    final lotSize = rawSize == null ? 0.0 : finiteNumber(rawSize);
    if (closeTime == null ||
        entryPrice == null ||
        exitPrice == null ||
        netProfit == null ||
        lotSize == null ||
        lotSize < 0) {
      return null;
    }

    final rawExecutionMode = data['executionMode'] ?? data['tradeMode'];
    final executionMode = rawExecutionMode is String
        ? rawExecutionMode.trim().toLowerCase()
        : data['isPaperTrade'] == true
        ? 'paper'
        : null;

    return TradeRecord(
      symbol: symbol,
      action: action,
      lotSize: lotSize,
      entryPrice: entryPrice,
      exitPrice: exitPrice,
      netProfit: netProfit,
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

DateTime? _journalCloseTime(Object? value) {
  if (value is Timestamp) return value.toDate().toUtc();
  if (value is DateTime) return value.toUtc();
  if (value is! String) return null;
  final text = value.trim();
  final match = RegExp(
    r'^(\d{4})-(\d{2})-(\d{2})T(\d{2}):(\d{2}):(\d{2})(?:\.\d{1,6})?(Z|[+-](\d{2}):(\d{2}))$',
  ).firstMatch(text);
  if (match == null) return null;
  final year = int.parse(match[1]!);
  final month = int.parse(match[2]!);
  final day = int.parse(match[3]!);
  if (year < 1 ||
      month < 1 ||
      month > 12 ||
      day < 1 ||
      day > DateTime.utc(year, month + 1, 0).day ||
      int.parse(match[4]!) > 23 ||
      int.parse(match[5]!) > 59 ||
      int.parse(match[6]!) > 59 ||
      (match[8] != null && int.parse(match[8]!) > 23) ||
      (match[9] != null && int.parse(match[9]!) > 59)) {
    return null;
  }
  return DateTime.tryParse(text)?.toUtc();
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
  final double? profitFactor;
  final String rrRatio;
  final double? payoffRatio;
  final int winningTrades;
  final int losingTrades;
  final int breakEvenTrades;
  final HeatmapEntry? lossConcentration;
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
    this.payoffRatio,
    this.winningTrades = 0,
    this.losingTrades = 0,
    this.breakEvenTrades = 0,
    this.lossConcentration,
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
    payoffRatio,
    winningTrades,
    losingTrades,
    breakEvenTrades,
    lossConcentration,
    equityData,
    totalTrades,
    bestTrade,
    worstTrade,
    avgProfit,
    aiInsight,
    heatmapData,
  ];
}
