import 'package:equatable/equatable.dart';

// ─── Trading Mode Enum (V2.1 Time Matrix) ───
enum TradingMode {
  scalping,
  dayTrading,
  swingTrading;

  String get displayName {
    switch (this) {
      case TradingMode.scalping:
        return 'Scalping';
      case TradingMode.dayTrading:
        return 'Day Trading';
      case TradingMode.swingTrading:
        return 'Swing Trading';
    }
  }

  /// Execution / HTF1 / HTF2 interval values sent to backend & WS.
  List<String> get timeframes {
    switch (this) {
      case TradingMode.scalping:
        return ['5', '15', '60']; // M5 / M15 / H1
      case TradingMode.dayTrading:
        return ['15', '60', '240']; // M15 / H1 / H4
      case TradingMode.swingTrading:
        return ['60', '240', '1440']; // H1 / H4 / D1
    }
  }

  List<String> get timeframeLabels {
    switch (this) {
      case TradingMode.scalping:
        return ['M5', 'M15', 'H1'];
      case TradingMode.dayTrading:
        return ['M15', 'H1', 'H4'];
      case TradingMode.swingTrading:
        return ['H1', 'H4', 'D1'];
    }
  }

  String get executionTf => timeframes[0];
  String get htf1 => timeframes[1];
  String get htf2 => timeframes[2];

  bool allowsTimeframe(String tf) {
    final normalized = tf == 'D' || tf == '1D' ? '1440' : tf;
    return timeframes.contains(normalized) || timeframes.contains(tf);
  }
}

// ─── Symbol metadata (tick/pip/lot — not SMC labels) ───
class SymbolMeta {
  final String symbol;
  final int digits;
  final double tickSize;
  final double pipSize;
  final double pipValuePerLot; // USD PnL per 1.0 price-pip move per 1.0 lot
  final double minLot;
  final double maxLot;
  final double lotStep;
  final double typicalSpread;

  const SymbolMeta({
    required this.symbol,
    required this.digits,
    required this.tickSize,
    required this.pipSize,
    required this.pipValuePerLot,
    this.minLot = 0.01,
    this.maxLot = 100.0,
    this.lotStep = 0.01,
    this.typicalSpread = 0.0,
  });

  static const _defaults = <String, SymbolMeta>{
    'XAUUSD': SymbolMeta(
      symbol: 'XAUUSD',
      digits: 2,
      tickSize: 0.01,
      pipSize: 0.1,
      pipValuePerLot: 10.0,
      typicalSpread: 0.30,
    ),
    'XAGUSD': SymbolMeta(
      symbol: 'XAGUSD',
      digits: 3,
      tickSize: 0.001,
      pipSize: 0.01,
      pipValuePerLot: 50.0,
      typicalSpread: 0.03,
    ),
    'BTCUSD': SymbolMeta(
      symbol: 'BTCUSD',
      digits: 2,
      tickSize: 0.01,
      pipSize: 1.0,
      pipValuePerLot: 1.0,
      typicalSpread: 20.0,
    ),
    'ETHUSD': SymbolMeta(
      symbol: 'ETHUSD',
      digits: 2,
      tickSize: 0.01,
      pipSize: 1.0,
      pipValuePerLot: 1.0,
      typicalSpread: 2.0,
    ),
    'EURUSD': SymbolMeta(
      symbol: 'EURUSD',
      digits: 5,
      tickSize: 0.00001,
      pipSize: 0.0001,
      pipValuePerLot: 10.0,
      typicalSpread: 0.00015,
    ),
    'GBPUSD': SymbolMeta(
      symbol: 'GBPUSD',
      digits: 5,
      tickSize: 0.00001,
      pipSize: 0.0001,
      pipValuePerLot: 10.0,
      typicalSpread: 0.00020,
    ),
    'USDJPY': SymbolMeta(
      symbol: 'USDJPY',
      digits: 3,
      tickSize: 0.001,
      pipSize: 0.01,
      pipValuePerLot: 9.0,
      typicalSpread: 0.015,
    ),
    'USDCHF': SymbolMeta(
      symbol: 'USDCHF',
      digits: 5,
      tickSize: 0.00001,
      pipSize: 0.0001,
      pipValuePerLot: 10.0,
      typicalSpread: 0.00020,
    ),
    'AUDUSD': SymbolMeta(
      symbol: 'AUDUSD',
      digits: 5,
      tickSize: 0.00001,
      pipSize: 0.0001,
      pipValuePerLot: 10.0,
      typicalSpread: 0.00018,
    ),
    'USDCAD': SymbolMeta(
      symbol: 'USDCAD',
      digits: 5,
      tickSize: 0.00001,
      pipSize: 0.0001,
      pipValuePerLot: 10.0,
      typicalSpread: 0.00020,
    ),
    'US100': SymbolMeta(
      symbol: 'US100',
      digits: 2,
      tickSize: 0.1,
      pipSize: 1.0,
      pipValuePerLot: 1.0,
      typicalSpread: 1.0,
    ),
    'USOIL': SymbolMeta(
      symbol: 'USOIL',
      digits: 2,
      tickSize: 0.01,
      pipSize: 0.01,
      pipValuePerLot: 10.0,
      typicalSpread: 0.03,
    ),
  };

  static SymbolMeta of(String symbol) {
    final key = symbol.toUpperCase().replaceAll(RegExp(r'[^A-Z0-9]'), '');
    return _defaults[key] ??
        SymbolMeta(
          symbol: key,
          digits: key.contains('JPY') ? 3 : (key.contains('XAU') ? 2 : 5),
          tickSize: key.contains('JPY')
              ? 0.001
              : (key.contains('XAU') ? 0.01 : 0.00001),
          pipSize: key.contains('JPY')
              ? 0.01
              : (key.contains('XAU') ? 0.1 : 0.0001),
          pipValuePerLot: 10.0,
          typicalSpread: key.contains('XAU') ? 0.30 : 0.00020,
        );
  }

  /// Approximate USD PnL for a price move (open → mark) at [lotSize].
  double calcPnL({
    required String type,
    required double openPrice,
    required double markPrice,
    required double lotSize,
  }) {
    final direction = type.toUpperCase() == 'SELL' ? -1.0 : 1.0;
    final priceMove = (markPrice - openPrice) * direction;
    if (pipSize <= 0) return 0.0;
    final pips = priceMove / pipSize;
    return pips * pipValuePerLot * lotSize;
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

// ─── Trading Signal (V2.1 fields) ───
class TradingSignal extends Equatable {
  final String symbol;
  final double entryPrice;
  final double slPrice;
  final List<double> tpPrices;
  final int probability;
  final String type; // 'BUY', 'SELL'
  final String status; // 'ACTIVE', 'PENDING'
  final List<Map<String, dynamic>> layers;
  final double suggestedLot;

  /// Soft alert until true — Layer 4 only when ready (wired Day 3).
  final bool setupReady;
  final bool veto;
  final Map<String, dynamic>? vetoData;
  final String? forecastText;
  final bool fallback;

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
    this.setupReady = true,
    this.veto = false,
    this.vetoData,
    this.forecastText,
    this.fallback = false,
  });

  factory TradingSignal.fromMap(Map<String, dynamic> data) {
    List<Map<String, dynamic>> layers = [];
    if (data['layers'] != null) {
      layers = (data['layers'] as List<dynamic>)
          .map((l) => Map<String, dynamic>.from(l as Map))
          .toList();
    }
    double suggestedLot = 0.1;
    for (final layer in layers) {
      if (layer['layer'] == 4 && layer['suggested_lot'] != null) {
        suggestedLot = (layer['suggested_lot'] as num).toDouble();
      }
    }
    return TradingSignal(
      symbol: data['symbol'] ?? '',
      entryPrice: (data['entryPrice'] ?? 0).toDouble(),
      slPrice: (data['slPrice'] ?? 0).toDouble(),
      tpPrices: List<double>.from(
        (data['tpPrices'] ?? []).map((e) => (e as num).toDouble()),
      ),
      probability: (data['probability'] ?? 0).toInt(),
      type: data['type'] ?? 'BUY',
      status: data['status'] ?? 'ACTIVE',
      layers: layers,
      suggestedLot: suggestedLot,
      setupReady:
          data['setup_ready'] as bool? ?? data['setupReady'] as bool? ?? true,
      veto: data['veto'] as bool? ?? false,
      vetoData: data['veto_data'] != null
          ? Map<String, dynamic>.from(data['veto_data'] as Map)
          : null,
      forecastText:
          data['forecast_text'] as String? ?? data['forecastText'] as String?,
      fallback: data['fallback'] as bool? ?? false,
    );
  }

  TradingSignal copyWith({
    String? symbol,
    double? entryPrice,
    double? slPrice,
    List<double>? tpPrices,
    int? probability,
    String? type,
    String? status,
    List<Map<String, dynamic>>? layers,
    double? suggestedLot,
    bool? setupReady,
    bool? veto,
    Map<String, dynamic>? vetoData,
    String? forecastText,
    bool? fallback,
  }) {
    return TradingSignal(
      symbol: symbol ?? this.symbol,
      entryPrice: entryPrice ?? this.entryPrice,
      slPrice: slPrice ?? this.slPrice,
      tpPrices: tpPrices ?? this.tpPrices,
      probability: probability ?? this.probability,
      type: type ?? this.type,
      status: status ?? this.status,
      layers: layers ?? this.layers,
      suggestedLot: suggestedLot ?? this.suggestedLot,
      setupReady: setupReady ?? this.setupReady,
      veto: veto ?? this.veto,
      vetoData: vetoData ?? this.vetoData,
      forecastText: forecastText ?? this.forecastText,
      fallback: fallback ?? this.fallback,
    );
  }

  /// Merge / replace Layer-5 `news_column` Red Zone (Day 6).
  TradingSignal withNewsRedZone(String label) {
    final layers = layersWithoutNewsColumn(this.layers);
    final newsItem = {
      'type': 'news_column',
      'text': label.length > 18 ? '${label.substring(0, 18)}…' : label,
      'full_text': label,
    };
    final idx = layers.indexWhere((l) => l['layer'] == 5);
    if (idx >= 0) {
      final layer = Map<String, dynamic>.from(layers[idx]);
      final items = List<Map<String, dynamic>>.from(
        ((layer['items'] as List?) ?? const []).map(
          (e) => Map<String, dynamic>.from(e as Map),
        ),
      );
      items.add(newsItem);
      layer['items'] = items;
      layers[idx] = layer;
    } else {
      layers.add({
        'layer': 5,
        'type': 'overlay',
        'items': [newsItem],
      });
    }
    return copyWith(layers: layers);
  }

  static List<Map<String, dynamic>> layersWithoutNewsColumn(
    List<Map<String, dynamic>> layers,
  ) {
    return layers.map((raw) {
      final layer = Map<String, dynamic>.from(raw);
      if (layer['layer'] != 5) return layer;
      final items = ((layer['items'] as List?) ?? const [])
          .map((e) => Map<String, dynamic>.from(e as Map))
          .where((item) => item['type'] != 'news_column')
          .toList();
      layer['items'] = items;
      return layer;
    }).toList();
  }

  @override
  List<Object?> get props => [
    symbol,
    entryPrice,
    slPrice,
    tpPrices,
    probability,
    type,
    status,
    layers,
    suggestedLot,
    setupReady,
    veto,
    forecastText,
    fallback,
  ];
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
  final List<Map<String, dynamic>> structures;
  final List<Map<String, dynamic>> traps;
  final List<Map<String, dynamic>> arrows;

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

  Position copyWith({double? currentPrice, double? profit, String? status}) {
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

  /// Mark-to-market using [markPrice] bound to this position's symbol.
  Position markToMarket(double markPrice) {
    final pnl = SymbolMeta.of(symbol).calcPnL(
      type: type,
      openPrice: openPrice,
      markPrice: markPrice,
      lotSize: lotSize,
    );
    return copyWith(currentPrice: markPrice, profit: pnl);
  }

  factory Position.fromMap(Map<String, dynamic> map) {
    return Position(
      id: map['id'] ?? '',
      symbol: map['symbol'] ?? 'XAUUSD',
      type: map['type'] ?? map['action'] ?? 'BUY',
      lotSize:
          (map['lotSize'] as num?)?.toDouble() ??
          (map['volume'] as num?)?.toDouble() ??
          0.1,
      openPrice:
          (map['openPrice'] as num?)?.toDouble() ??
          (map['entryPrice'] as num?)?.toDouble() ??
          0.0,
      currentPrice: (map['currentPrice'] as num?)?.toDouble() ?? 0.0,
      sl: (map['sl'] as num?)?.toDouble() ?? 0.0,
      tp: (map['tp'] as num?)?.toDouble() ?? 0.0,
      tpLevels: List<double>.from(
        (map['tpLevels'] ?? map['tpPrices'] ?? []).map(
          (e) => (e as num).toDouble(),
        ),
      ),
      profit:
          (map['profit'] as num?)?.toDouble() ??
          (map['netProfit'] as num?)?.toDouble() ??
          0.0,
      status: map['status'] ?? 'OPEN',
      tradingMode: map['tradingMode'] ?? 'scalping',
    );
  }

  @override
  List<Object?> get props => [
    id,
    symbol,
    type,
    lotSize,
    openPrice,
    currentPrice,
    sl,
    tp,
    profit,
    status,
  ];
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
  final bool isFallback;

  const ChatMessage({
    required this.id,
    required this.content,
    required this.isUser,
    required this.timestamp,
    this.isFallback = false,
  });

  Map<String, dynamic> toMap() => {
    'id': id,
    'content': content,
    'isUser': isUser,
    'timestamp': timestamp.millisecondsSinceEpoch,
    'isFallback': isFallback,
  };

  factory ChatMessage.fromMap(Map<String, dynamic> map) {
    return ChatMessage(
      id: map['id'] as String? ?? '',
      content: map['content'] as String? ?? '',
      isUser: map['isUser'] as bool? ?? false,
      timestamp: map['timestamp'] != null
          ? DateTime.fromMillisecondsSinceEpoch(map['timestamp'] as int)
          : DateTime.now(),
      isFallback:
          map['isFallback'] as bool? ?? map['fallback'] as bool? ?? false,
    );
  }

  @override
  List<Object?> get props => [id, content, isUser, timestamp, isFallback];
}
