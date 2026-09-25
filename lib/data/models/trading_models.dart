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

  String get wireName => switch (this) {
    TradingMode.scalping => 'scalping',
    TradingMode.dayTrading => 'day_trading',
    TradingMode.swingTrading => 'swing',
  };

  String normalizeTimeframe(String tf) => switch (tf.toUpperCase()) {
    'M5' => '5',
    'M15' => '15',
    'H1' => '60',
    'H4' => '240',
    'D' || 'D1' || '1D' => '1440',
    _ => tf,
  };

  bool allowsTimeframe(String tf) {
    final normalized = normalizeTimeframe(tf);
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
  final String source;

  const TradingAccount({
    required this.balance,
    required this.equity,
    required this.margin,
    required this.leverage,
    required this.status,
    this.source = 'unavailable',
  });

  bool get hasAuthoritativeBrokerData =>
      status == 'LIVE' && source.isNotEmpty && source != 'unavailable';

  @override
  List<Object?> get props => [
    balance,
    equity,
    margin,
    leverage,
    status,
    source,
  ];
}

// ─── Trading Signal (V2.1 fields) ───
class TradingSignal extends Equatable {
  final String? signalId;
  final String? chartId;
  final String symbol;
  final double entryPrice;
  final double slPrice;
  final List<double> tpPrices;
  final int probability;
  final bool probabilityAvailable;
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
  final String? contractError;

  const TradingSignal({
    this.signalId,
    this.chartId,
    required this.symbol,
    required this.entryPrice,
    required this.slPrice,
    required this.tpPrices,
    required this.probability,
    this.probabilityAvailable = true,
    required this.type,
    required this.status,
    this.layers = const [],
    this.suggestedLot = 0,
    this.setupReady = false,
    this.veto = false,
    this.vetoData,
    this.forecastText,
    this.fallback = false,
    this.contractError,
  });

  /// Execution fails closed unless the backend supplied a complete Hard Setup.
  bool get canExecute {
    if (!setupReady ||
        veto ||
        entryPrice <= 0 ||
        slPrice <= 0 ||
        tpPrices.length != 3 ||
        tpPrices.any((price) => price <= 0) ||
        !layers.any((layer) => layer['layer'] == 4)) {
      return false;
    }
    final direction = type.toUpperCase();
    final risk = direction == 'BUY'
        ? entryPrice - slPrice
        : direction == 'SELL'
        ? slPrice - entryPrice
        : 0.0;
    final reward = direction == 'BUY'
        ? tpPrices.first - entryPrice
        : direction == 'SELL'
        ? entryPrice - tpPrices.first
        : 0.0;
    return risk > 0 && reward / risk >= 2.0;
  }

  factory TradingSignal.fromMap(Map<String, dynamic> data) {
    Map<String, dynamic>? asStringMap(Object? value) {
      if (value is! Map || value.keys.any((key) => key is! String)) return null;
      return Map<String, dynamic>.from(value);
    }

    List<Map<String, dynamic>>? asMapList(Object? value) {
      if (value is! List) return null;
      final result = <Map<String, dynamic>>[];
      for (final item in value) {
        final map = asStringMap(item);
        if (map == null) return null;
        result.add(map);
      }
      return result;
    }

    double? asDouble(Object? value) => value is num ? value.toDouble() : null;

    bool isHexColor(Object? value) =>
        value is String && RegExp(r'^#[0-9A-Fa-f]{6}$').hasMatch(value);

    Map<String, dynamic>? normalizeLayer1(Map<String, dynamic> item) {
      final type = item['type'];
      if (type is! String || !isHexColor(item['color'])) return null;
      if (type == 'dashed_line') {
        if (item['x1'] is! num ||
            item['y1'] is! num ||
            item['x2'] is! num ||
            item['y2'] is! num ||
            (item['x2'] as num) <= (item['x1'] as num)) {
          return null;
        }
        return item;
      }
      if (type != 'solid_box' && type != 'bordered_box') return null;
      if (item['x'] is! num ||
          item['x_end'] is! num ||
          item['y_top'] is! num ||
          item['y_bottom'] is! num ||
          (item['x_end'] as num) <= (item['x'] as num)) {
        return null;
      }
      final label = item['label'];
      if (label != null && (label is! String || label.length > 4)) return null;
      return item;
    }

    Map<String, dynamic>? normalizeLayer2(Map<String, dynamic> item) {
      final type = item['type'];
      if (type is! String ||
          !isHexColor(item['color']) ||
          item['x'] is! num ||
          item['y'] is! num) {
        return null;
      }
      final text = type == 'arrow' ? item['label'] : item['text'];
      if (text is! String || text.isEmpty || text.length > 8) return null;
      if (type == 'arrow' &&
          item['direction'] != 'up' &&
          item['direction'] != 'down') {
        return null;
      }
      if (type != 'arrow' && type != 'text_tag' && type != 'volume_tag') {
        return null;
      }
      return item;
    }

    Map<String, dynamic>? normalizeLayer3(Map<String, dynamic> item) {
      if (item['timestamp'] is! num) return null;
      final fill = item['fill_color'];
      final border = item['border'];
      final text = item['text'];
      final divergence = item['divergence'];
      final divergenceColor = item['divergence_color'];
      if (fill != null && !isHexColor(fill)) return null;
      if (border != null && !isHexColor(border)) return null;
      if (text != null && (text is! String || text.length > 2)) return null;
      if (divergence != null && divergence != 'up' && divergence != 'down') {
        return null;
      }
      if (divergence != null && !isHexColor(divergenceColor)) return null;
      if (fill == null &&
          border == null &&
          text == null &&
          divergence == null) {
        return null;
      }
      return item;
    }

    Map<String, dynamic>? normalizeLayer5(Map<String, dynamic> item) {
      final type = item['type'];
      if (type is! String || !isHexColor(item['color'])) return null;
      if (type == 'ghost_box') {
        if (item['x'] is! num ||
            item['x_end'] is! num ||
            item['y_top'] is! num ||
            item['y_bottom'] is! num ||
            (item['x_end'] as num) <= (item['x'] as num) ||
            item['opacity'] != 0.15 ||
            item['tooltip'] is! String) {
          return null;
        }
        return item;
      }
      if (type == 'red_zone') {
        if (item['start_time'] is! num ||
            item['duration_min'] is! num ||
            item['label'] is! String) {
          return null;
        }
        return item;
      }
      if (type == 'phase_tracker_text') {
        if (item['label'] is! String) return null;
        return item;
      }
      if (type == 'htf_trend') {
        if (item['htf1_label'] is! String || item['htf1_trend'] is! String) {
          return null;
        }
        return item;
      }
      return null;
    }

    List<Map<String, dynamic>>? normalizeItems(
      Object? value,
      Map<String, dynamic>? Function(Map<String, dynamic>) normalizer,
    ) {
      final raw = asMapList(value);
      if (raw == null) return null;
      final normalized = <Map<String, dynamic>>[];
      for (final item in raw) {
        final result = normalizer(item);
        if (result == null) return null;
        normalized.add(result);
      }
      return normalized;
    }

    Map<String, dynamic>? normalizeExecutionLayer(Map<String, dynamic> layer) {
      final entry = asDouble(layer['entry']);
      final stop = asDouble(layer['sl']);
      final rawTargets = layer['tp'];
      final targets = rawTargets is List
          ? rawTargets.map(asDouble).toList()
          : <double?>[];
      final momentum = asStringMap(layer['momentum']);
      final curves = asMapList(layer['curves']);
      if (layer['active'] != true ||
          entry == null ||
          entry <= 0 ||
          layer['entry_color'] != '#0000FF' ||
          stop == null ||
          stop <= 0 ||
          layer['sl_color'] != '#FF0000' ||
          targets.length != 3 ||
          targets.any((target) => target == null || target <= 0) ||
          layer['tp_color'] != '#00FF00' ||
          momentum == null ||
          (momentum['arrow'] != 'up' && momentum['arrow'] != 'down') ||
          momentum['label'] is! String ||
          (momentum['label'] as String).length != 3 ||
          !isHexColor(momentum['color']) ||
          curves == null ||
          curves.length != 2) {
        return null;
      }
      final normalizedCurves = <Map<String, dynamic>>[];
      for (var index = 0; index < curves.length; index++) {
        final curve = curves[index];
        final expectedId = index == 0 ? 'SIG_1' : 'SIG_2';
        final expectedType = index == 0 ? 'bezier_quadratic' : 'bezier_cubic';
        final expectedColor = index == 0 ? '#00F0FF' : '#1E90FF';
        final expectedCount = index == 0 ? 3 : 4;
        final points = asMapList(curve['points']);
        if (curve['id'] != expectedId ||
            curve['type'] != expectedType ||
            curve['style'] != 'dashed' ||
            curve['color'] != expectedColor ||
            points == null ||
            points.length != expectedCount ||
            points.any((point) => point['x'] is! num || point['y'] is! num) ||
            asDouble(points.first['y']) != entry ||
            asDouble(points.last['y']) != targets.last) {
          return null;
        }
        normalizedCurves.add(curve);
      }
      final probability = layer['prob'];
      if (probability != null &&
          (probability is! num || probability < 0 || probability > 100)) {
        return null;
      }
      final values = targets.cast<double>();
      final up = momentum['arrow'] == 'up';
      final levelsOrdered = up
          ? stop < entry &&
                entry < values[0] &&
                values[0] < values[1] &&
                values[1] < values[2]
          : stop > entry &&
                entry > values[0] &&
                values[0] > values[1] &&
                values[1] > values[2];
      if (!levelsOrdered) return null;
      return {...layer, 'curves': normalizedCurves};
    }

    String? contractError;
    var layer4ContractValid = true;
    final layers = <Map<String, dynamic>>[];
    final rawLayers = data['layers'];
    final usesObjectContract = rawLayers is Map;
    if (rawLayers is List) {
      final legacyLayers = asMapList(rawLayers);
      if (legacyLayers == null) {
        contractError = 'Malformed legacy analysis layers';
      } else {
        layers.addAll(legacyLayers);
      }
    } else if (rawLayers is Map) {
      final objectLayers = asStringMap(rawLayers);
      const requiredKeys = {
        'layer1_structural',
        'layer2_trap',
        'layer3_candle',
        'layer4_execution',
        'layer5_overlay',
      };
      if (objectLayers == null ||
          !objectLayers.keys.toSet().containsAll(requiredKeys) ||
          objectLayers.keys.any((key) => !requiredKeys.contains(key))) {
        contractError = 'Malformed V2.1 analysis layer envelope';
      } else {
        final layer1 = normalizeItems(
          objectLayers['layer1_structural'],
          normalizeLayer1,
        );
        final layer2 = normalizeItems(
          objectLayers['layer2_trap'],
          normalizeLayer2,
        );
        final layer3 = normalizeItems(
          objectLayers['layer3_candle'],
          normalizeLayer3,
        );
        final layer5 = normalizeItems(
          objectLayers['layer5_overlay'],
          normalizeLayer5,
        );
        final execution = objectLayers['layer4_execution'];
        final rawLayer4 = execution == null ? null : asStringMap(execution);
        final layer4 = rawLayer4 == null
            ? null
            : normalizeExecutionLayer(rawLayer4);
        if (layer1 == null ||
            layer2 == null ||
            layer3 == null ||
            layer5 == null ||
            (execution != null && rawLayer4 == null)) {
          contractError = 'Malformed V2.1 analysis layer items';
        } else {
          if (execution != null && layer4 == null) {
            layer4ContractValid = false;
            contractError = 'Malformed V2.1 Layer 4 execution contract';
          }
          layers.addAll([
            {'layer': 1, 'type': 'structural', 'items': layer1},
            {'layer': 2, 'type': 'icon_text', 'items': layer2},
            {'layer': 3, 'type': 'candle_color', 'items': layer3},
            if (layer4 != null) {'layer': 4, 'type': 'execution', ...layer4},
            {'layer': 5, 'type': 'overlay', 'items': layer5},
          ]);
        }
      }
    } else {
      contractError = 'Missing or malformed analysis layers';
    }

    double suggestedLot = 0;
    for (final layer in layers) {
      final parsedLot = asDouble(layer['suggested_lot']);
      if (layer['layer'] == 4 && parsedLot != null && parsedLot > 0) {
        suggestedLot = parsedLot;
      }
    }

    final rawSetup = data.containsKey('setup_ready')
        ? data['setup_ready']
        : data['setupReady'];
    final rawVeto = data['veto'];
    final rawFallback = data['fallback'];
    if (rawSetup != null && rawSetup is! bool) {
      contractError ??= 'setup_ready must be a boolean';
    }
    if (rawVeto != null && rawVeto is! bool) {
      contractError ??= 'veto must be a boolean';
    }
    if (rawFallback != null && rawFallback is! bool) {
      contractError ??= 'fallback must be a boolean';
    }
    if (data['chart_id'] != null && data['chart_id'] is! String) {
      contractError ??= 'chart_id must be a string';
    }
    if (usesObjectContract) {
      const requiredEnvelopeKeys = {
        'chart_id',
        'setup_ready',
        'veto',
        'veto_data',
        'fallback',
        'forecast_text',
        'layers',
      };
      if (!data.keys.toSet().containsAll(requiredEnvelopeKeys)) {
        contractError ??= 'Incomplete V2.1 analysis response envelope';
      }
      final chartId = data['chart_id'];
      if (chartId is! String ||
          !RegExp(
            r'^[A-Z0-9._-]{2,20}_(M5|M15|H1|H4|D1|5|15|60|240|1440|UNKNOWN)_[1-9][0-9]*$',
          ).hasMatch(chartId)) {
        contractError ??= 'chart_id must use SYMBOL_TF_TIMESTAMP';
      }
    }
    if (data['symbol'] != null && data['symbol'] is! String) {
      contractError ??= 'symbol must be a string';
    }
    if (data['forecast_text'] != null && data['forecast_text'] is! String) {
      contractError ??= 'forecast_text must be a string';
    }
    if (data['veto_data'] != null && asStringMap(data['veto_data']) == null) {
      contractError ??= 'veto_data must be an object';
    }
    final requestedSetup = rawSetup is bool && rawSetup;
    final veto = rawVeto is bool && rawVeto;
    Map<String, dynamic>? parsedLayer4;
    for (final layer in layers) {
      if (layer['layer'] == 4) {
        parsedLayer4 = layer;
        break;
      }
    }
    final parsedEntry = usesObjectContract
        ? asDouble(parsedLayer4?['entry'])
        : asDouble(data['entryPrice']);
    final parsedStop = usesObjectContract
        ? asDouble(parsedLayer4?['sl'])
        : asDouble(data['slPrice']);
    final rawTargets = usesObjectContract
        ? (parsedLayer4 == null ? null : parsedLayer4['tp'])
        : data['tpPrices'];
    final parsedTargets = rawTargets is List
        ? rawTargets.map((target) => asDouble(target)).toList()
        : <double?>[];
    final hardValuesValid =
        parsedEntry != null &&
        parsedEntry > 0 &&
        parsedStop != null &&
        parsedStop > 0 &&
        parsedTargets.length == 3 &&
        parsedTargets.every((value) => value != null && value > 0) &&
        layer4ContractValid &&
        layers.any((layer) => layer['layer'] == 4);
    final setupReady =
        requestedSetup && !veto && contractError == null && hardValuesValid;
    if (requestedSetup && !veto && !hardValuesValid) {
      contractError ??= 'Incomplete Hard Setup execution contract';
    }
    if (!setupReady) {
      if (layers.any((layer) => layer['layer'] == 4)) {
        contractError ??= 'Soft/Veto response contained execution layer';
      }
      layers.removeWhere((layer) => layer['layer'] == 4);
      suggestedLot = 0;
    }

    final parsedChartId = data['chart_id'] is String
        ? data['chart_id'] as String
        : null;
    var parsedSymbol = data['symbol'] is String ? data['symbol'] as String : '';
    if (usesObjectContract && parsedSymbol.isEmpty && parsedChartId != null) {
      final parts = parsedChartId.split('_');
      if (parts.length >= 3) {
        parsedSymbol = parts.sublist(0, parts.length - 2).join('_');
      }
    }
    var parsedType = data['type'] is String
        ? data['type'] as String
        : 'NEUTRAL';
    if (usesObjectContract && parsedLayer4 != null) {
      final momentum = asStringMap(parsedLayer4['momentum']);
      parsedType = momentum?['arrow'] == 'up'
          ? 'BUY'
          : momentum?['arrow'] == 'down'
          ? 'SELL'
          : 'NEUTRAL';
    }
    final rawProbability = usesObjectContract
        ? (parsedLayer4 == null ? null : parsedLayer4['prob'])
        : data['probability'];
    final probabilityAvailable = usesObjectContract
        ? rawProbability is num
        : data['probability_source'] == 'backtest' && rawProbability is num;

    return TradingSignal(
      signalId: data['signalId'] is String ? data['signalId'] as String : null,
      chartId: parsedChartId,
      symbol: parsedSymbol,
      entryPrice: setupReady ? parsedEntry : 0,
      slPrice: setupReady ? parsedStop : 0,
      tpPrices: setupReady ? parsedTargets.cast<double>() : const [],
      probability: rawProbability is num
          ? rawProbability.toInt().clamp(0, 100)
          : 0,
      probabilityAvailable: probabilityAvailable,
      type: parsedType,
      status: data['status'] is String ? data['status'] as String : 'ACTIVE',
      layers: layers,
      suggestedLot: suggestedLot,
      setupReady: setupReady,
      veto: veto,
      vetoData: asStringMap(data['veto_data']),
      forecastText: data['forecast_text'] is String
          ? data['forecast_text'] as String
          : data['forecastText'] is String
          ? data['forecastText'] as String
          : null,
      fallback: rawFallback is bool && rawFallback,
      contractError: contractError,
    );
  }

  TradingSignal copyWith({
    String? signalId,
    String? chartId,
    String? symbol,
    double? entryPrice,
    double? slPrice,
    List<double>? tpPrices,
    int? probability,
    bool? probabilityAvailable,
    String? type,
    String? status,
    List<Map<String, dynamic>>? layers,
    double? suggestedLot,
    bool? setupReady,
    bool? veto,
    Map<String, dynamic>? vetoData,
    String? forecastText,
    bool? fallback,
    String? contractError,
  }) {
    return TradingSignal(
      signalId: signalId ?? this.signalId,
      chartId: chartId ?? this.chartId,
      symbol: symbol ?? this.symbol,
      entryPrice: entryPrice ?? this.entryPrice,
      slPrice: slPrice ?? this.slPrice,
      tpPrices: tpPrices ?? this.tpPrices,
      probability: probability ?? this.probability,
      probabilityAvailable: probabilityAvailable ?? this.probabilityAvailable,
      type: type ?? this.type,
      status: status ?? this.status,
      layers: layers ?? this.layers,
      suggestedLot: suggestedLot ?? this.suggestedLot,
      setupReady: setupReady ?? this.setupReady,
      veto: veto ?? this.veto,
      vetoData: vetoData ?? this.vetoData,
      forecastText: forecastText ?? this.forecastText,
      fallback: fallback ?? this.fallback,
      contractError: contractError ?? this.contractError,
    );
  }

  /// Merge a validated scheduled event into Layer 5 without replacing peers.
  TradingSignal withNewsRedZone(RedZoneOverlay overlay) {
    if (!overlay.isValid) return this;
    final layers = layersWithoutNewsColumn(
      this.layers,
      sourceId: overlay.evidence['source_id'] as String,
    );
    final newsItem = overlay.toLayerItem();
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
    List<Map<String, dynamic>> layers, {
    String? sourceId,
  }) {
    return layers.map((raw) {
      final layer = Map<String, dynamic>.from(raw);
      if (layer['layer'] != 5) return layer;
      final items = ((layer['items'] as List?) ?? const [])
          .map((e) => Map<String, dynamic>.from(e as Map))
          .where((item) {
            final isRedZone =
                item['type'] == 'news_column' || item['type'] == 'red_zone';
            if (!isRedZone) return true;
            if (sourceId == null) return false;
            final evidence = item['evidence'];
            return evidence is! Map || evidence['source_id'] != sourceId;
          })
          .toList();
      layer['items'] = items;
      return layer;
    }).toList();
  }

  @override
  List<Object?> get props => [
    signalId,
    chartId,
    symbol,
    entryPrice,
    slPrice,
    tpPrices,
    probability,
    probabilityAvailable,
    type,
    status,
    layers,
    suggestedLot,
    setupReady,
    veto,
    forecastText,
    fallback,
    vetoData,
    contractError,
  ];
}

// ─── Candle ───
class Candle extends Equatable {
  final DateTime timestamp;
  final double open;
  final double high;
  final double low;
  final double close;
  final double volume;

  const Candle({
    required this.timestamp,
    required this.open,
    required this.high,
    required this.low,
    required this.close,
    this.volume = 0.0,
  });

  @override
  List<Object?> get props => [timestamp, open, high, low, close, volume];
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

class RedZoneOverlay extends Equatable {
  final String eventId;
  final int startTime;
  final double durationMinutes;
  final String label;
  final String color;
  final List<String> currencies;
  final Map<String, dynamic> evidence;

  const RedZoneOverlay({
    required this.eventId,
    required this.startTime,
    required this.durationMinutes,
    required this.label,
    required this.color,
    required this.currencies,
    required this.evidence,
  });

  bool get isValid {
    final source = evidence['source'];
    final sourceId = evidence['source_id'];
    final timestamp = evidence['timestamp'];
    return eventId.trim().isNotEmpty &&
        startTime > 0 &&
        durationMinutes.isFinite &&
        durationMinutes > 0 &&
        label.trim().isNotEmpty &&
        currencies.isNotEmpty &&
        currencies.every(
          (currency) => RegExp(r'^[A-Z]{3}$').hasMatch(currency),
        ) &&
        RegExp(r'^#[0-9A-Fa-f]{6}$').hasMatch(color) &&
        source is String &&
        source.trim().isNotEmpty &&
        sourceId is String &&
        sourceId.trim().isNotEmpty &&
        sourceId == eventId &&
        timestamp is int &&
        timestamp > 0;
  }

  Map<String, dynamic> toLayerItem() => {
    'type': 'red_zone',
    'event_id': eventId,
    'start_time': startTime,
    'duration_min': durationMinutes,
    'label': label.length > 20 ? label.substring(0, 20) : label,
    'color': color,
    'currencies': List<String>.from(currencies),
    'evidence': Map<String, dynamic>.from(evidence),
  };

  @override
  List<Object?> get props => [
    eventId,
    startTime,
    durationMinutes,
    label,
    color,
    currencies,
    evidence,
  ];
}

// ─── Partial Take Profit ───
class TakeProfitLeg extends Equatable {
  final int targetIndex;
  final double targetPrice;
  final double percentage;
  final double volume;

  const TakeProfitLeg({
    required this.targetIndex,
    required this.targetPrice,
    required this.percentage,
    required this.volume,
  });

  @override
  List<Object?> get props => [targetIndex, targetPrice, percentage, volume];
}

/// A deterministic, lot-step-safe split of one paper order across TP1–TP3.
class TakeProfitAllocationPlan extends Equatable {
  final double totalVolume;
  final List<TakeProfitLeg> legs;

  const TakeProfitAllocationPlan._({
    required this.totalVolume,
    required this.legs,
  });

  factory TakeProfitAllocationPlan.create({
    required double totalVolume,
    required List<double> targetPrices,
    required List<double> percentages,
    required double lotStep,
    required double minLot,
  }) {
    if (!totalVolume.isFinite || totalVolume <= 0) {
      throw ArgumentError.value(totalVolume, 'totalVolume');
    }
    if (!lotStep.isFinite || lotStep <= 0) {
      throw ArgumentError.value(lotStep, 'lotStep');
    }
    if (!minLot.isFinite || minLot <= 0) {
      throw ArgumentError.value(minLot, 'minLot');
    }
    if (targetPrices.length != 3 ||
        targetPrices.any((price) => !price.isFinite || price <= 0)) {
      throw ArgumentError.value(targetPrices, 'targetPrices');
    }
    if (percentages.length != 3 ||
        percentages.any(
          (percentage) => !percentage.isFinite || percentage < 0,
        )) {
      throw ArgumentError.value(percentages, 'percentages');
    }
    final percentageTotal = percentages.fold<double>(0, (a, b) => a + b);
    if ((percentageTotal - 100).abs() > 1e-6) {
      throw ArgumentError.value(percentages, 'percentages', 'Must total 100');
    }

    final totalUnits = (totalVolume / lotStep).round();
    final normalizedTotal = totalUnits * lotStep;
    if ((normalizedTotal - totalVolume).abs() > 1e-8) {
      throw ArgumentError.value(
        totalVolume,
        'totalVolume',
        'Must align to lotStep',
      );
    }

    final rawUnits = percentages
        .map((percentage) => totalUnits * percentage / 100)
        .toList(growable: false);
    final allocatedUnits = rawUnits.map((units) => units.floor()).toList();
    var remainingUnits =
        totalUnits - allocatedUnits.fold<int>(0, (a, b) => a + b);
    final remainderOrder = List<int>.generate(3, (index) => index)
      ..sort((a, b) {
        final fractionA = rawUnits[a] - rawUnits[a].floor();
        final fractionB = rawUnits[b] - rawUnits[b].floor();
        final byFraction = fractionB.compareTo(fractionA);
        return byFraction != 0 ? byFraction : a.compareTo(b);
      });
    for (final index in remainderOrder) {
      if (remainingUnits == 0) break;
      allocatedUnits[index] += 1;
      remainingUnits -= 1;
    }

    final minUnits = (minLot / lotStep).ceil();
    final legs = <TakeProfitLeg>[];
    for (var index = 0; index < 3; index++) {
      if (percentages[index] == 0) continue;
      if (allocatedUnits[index] < minUnits) {
        throw ArgumentError.value(
          totalVolume,
          'totalVolume',
          'A TP leg is below the symbol minimum lot',
        );
      }
      legs.add(
        TakeProfitLeg(
          targetIndex: index,
          targetPrice: targetPrices[index],
          percentage: percentages[index],
          volume: allocatedUnits[index] * lotStep,
        ),
      );
    }
    if (legs.isEmpty) {
      throw ArgumentError.value(percentages, 'percentages');
    }
    return TakeProfitAllocationPlan._(
      totalVolume: normalizedTotal,
      legs: List.unmodifiable(legs),
    );
  }

  double get allocatedVolume =>
      legs.fold<double>(0, (total, leg) => total + leg.volume);

  @override
  List<Object?> get props => [totalVolume, legs];
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
class DailyCutoffStatus extends Equatable {
  final bool active;
  final bool reviewed;
  final bool acknowledged;
  final String? sessionDate;
  final double? realizedPnl;
  final double? floatingPnl;
  final double? lossLimit;

  const DailyCutoffStatus({
    required this.active,
    this.reviewed = false,
    this.acknowledged = false,
    this.sessionDate,
    this.realizedPnl,
    this.floatingPnl,
    this.lossLimit,
  });

  factory DailyCutoffStatus.fromMap(Map<String, dynamic> map) {
    if (map['active'] is! bool) {
      throw const FormatException('Invalid cutoff status');
    }
    double? amount(Object? value) =>
        value is num && value.isFinite ? value.toDouble() : null;
    return DailyCutoffStatus(
      active: map['active'] as bool,
      reviewed: map['reviewed'] == true,
      acknowledged: map['acknowledged'] == true,
      sessionDate: map['sessionDate'] is String
          ? map['sessionDate'] as String
          : null,
      realizedPnl: amount(map['realizedPnl']),
      floatingPnl: amount(map['floatingPnl']),
      lossLimit: amount(map['lossLimit']),
    );
  }

  @override
  List<Object?> get props => [
    active,
    reviewed,
    acknowledged,
    sessionDate,
    realizedPnl,
    floatingPnl,
    lossLimit,
  ];
}

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
