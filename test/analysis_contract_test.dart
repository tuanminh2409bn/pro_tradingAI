import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:protrading_ai/data/models/trading_models.dart';

Map<String, dynamic> _canonicalExecution() => {
  'active': true,
  'entry': 100,
  'entry_color': '#0000FF',
  'sl': 99,
  'sl_color': '#FF0000',
  'tp': [102, 103, 104],
  'tp_color': '#00FF00',
  'prob': 82,
  'momentum': {'arrow': 'up', 'label': 'SIG', 'color': '#00FF7F'},
  'curves': [
    {
      'id': 'SIG_1',
      'type': 'bezier_quadratic',
      'style': 'dashed',
      'color': '#00F0FF',
      'points': [
        {'x': 1700000000, 'y': 100},
        {'x': 1700000300, 'y': 102},
        {'x': 1700000900, 'y': 104},
      ],
    },
    {
      'id': 'SIG_2',
      'type': 'bezier_cubic',
      'style': 'dashed',
      'color': '#1E90FF',
      'points': [
        {'x': 1700000000, 'y': 100},
        {'x': 1700000200, 'y': 99.7},
        {'x': 1700000500, 'y': 102},
        {'x': 1700000900, 'y': 104},
      ],
    },
  ],
};

Map<String, dynamic> _objectLayers({Map<String, dynamic>? execution}) => {
  'layer1_structural': [
    {
      'type': 'solid_box',
      'label': 'OB',
      'color': '#00FF7F',
      'x': 1700000000,
      'x_end': 1700000300,
      'y_top': 100.2,
      'y_bottom': 99.8,
      'evidence': {
        'source': 'candle',
        'source_id': 'M5:1700000000',
        'timestamp': 1700000000,
      },
    },
  ],
  'layer2_trap': <Map<String, dynamic>>[],
  'layer3_candle': <Map<String, dynamic>>[],
  'layer4_execution': execution,
  'layer5_overlay': <Map<String, dynamic>>[],
};

Map<String, dynamic> _canonicalSignal({bool setupReady = false}) => {
  'chart_id': 'XAUUSD_M5_1700000000',
  'setup_ready': setupReady,
  'veto': false,
  'veto_data': null,
  'fallback': false,
  'forecast_text': 'Waiting for confirmation.',
  'layers': _objectLayers(execution: setupReady ? _canonicalExecution() : null),
};

void main() {
  group('TradingSignal V2.1 Appendix-8 contract', () {
    test('parses every shared T19 signal golden fail closed', () {
      final cases =
          jsonDecode(
                File(
                  'test/fixtures/v21_signal_contract_cases.json',
                ).readAsStringSync(),
              )
              as List<dynamic>;

      expect(cases.map((item) => item['name']).toSet(), {
        'soft_bullish',
        'hard_bullish',
        'hard_bearish',
        'fallback_unavailable',
      });
      for (final rawCase in cases) {
        final testCase = rawCase as Map<String, dynamic>;
        final signal = TradingSignal.fromMap(
          testCase['contract'] as Map<String, dynamic>,
        );

        expect(signal.contractError, isNull, reason: testCase['name'] as String);
        final isHard = (testCase['name'] as String).startsWith('hard_');
        expect(signal.setupReady, isHard, reason: testCase['name'] as String);
        expect(signal.canExecute, isHard, reason: testCase['name'] as String);
        expect(
          signal.layers.any((layer) => layer['layer'] == 4),
          isHard,
          reason: testCase['name'] as String,
        );
      }
    });

    test('parses the shared Python-validated HTF Veto fixture', () {
      final payload =
          jsonDecode(
                File(
                  'test/fixtures/v21_htf_veto_signal.json',
                ).readAsStringSync(),
              )
              as Map<String, dynamic>;
      final signal = TradingSignal.fromMap(payload);

      expect(signal.contractError, isNull);
      expect(signal.veto, isTrue);
      expect(signal.setupReady, isFalse);
      expect(signal.canExecute, isFalse);
      expect(signal.layers.any((layer) => layer['layer'] == 4), isFalse);
      expect(signal.vetoData?['veto_reason'], 'htf_opposing_order_block');
      expect(signal.vetoData?['conflict_htf'], 'H4');
      expect(signal.vetoData?['danger_zone'], {
        'top': 101.2,
        'bottom': 99.8,
        'bias': 'bearish',
      });
    });

    test('parses exact object envelope without renaming Appendix-8 fields', () {
      final signal = TradingSignal.fromMap(_canonicalSignal());

      expect(signal.chartId, 'XAUUSD_M5_1700000000');
      expect(signal.symbol, 'XAUUSD');
      expect(signal.contractError, isNull);
      expect(signal.layers.map((layer) => layer['layer']), [1, 2, 3, 5]);
      final item = signal.layers.first['items'].first as Map<String, dynamic>;
      expect(item['type'], 'solid_box');
      expect(item['x'], 1700000000);
      expect(item['y_top'], 100.2);
      expect(signal.canExecute, isFalse);
    });

    test('soft legacy response scrubs executable values', () {
      final signal = TradingSignal.fromMap({
        'symbol': 'XAUUSD',
        'setup_ready': false,
        'entryPrice': 100,
        'slPrice': 99,
        'tpPrices': [102, 103, 104],
        'layers': [
          {
            'layer': 4,
            'suggested_lot': 0.5,
            'entry_line': {'price': 100},
          },
        ],
      });

      expect(signal.entryPrice, 0);
      expect(signal.slPrice, 0);
      expect(signal.tpPrices, isEmpty);
      expect(signal.suggestedLot, 0);
      expect(signal.layers.any((layer) => layer['layer'] == 4), isFalse);
      expect(signal.canExecute, isFalse);
    });

    test('malformed layers fail closed without throwing', () {
      final signal = TradingSignal.fromMap({
        'symbol': 'XAUUSD',
        'setup_ready': true,
        'entryPrice': 100,
        'slPrice': 99,
        'tpPrices': [102, 103, 104],
        'layers': 'not-a-contract',
      });

      expect(signal.setupReady, isFalse);
      expect(signal.layers, isEmpty);
      expect(signal.contractError, isNotNull);
      expect(signal.canExecute, isFalse);
    });

    test('malformed scalar fields fail closed without throwing', () {
      final signal = TradingSignal.fromMap({
        'chart_id': 42,
        'symbol': 99,
        'setup_ready': 'yes',
        'veto': 1,
        'fallback': 'no',
        'forecast_text': <String>[],
        'probability': '99',
        'layers': <Map<String, dynamic>>[],
      });

      expect(signal.setupReady, isFalse);
      expect(signal.canExecute, isFalse);
      expect(signal.contractError, isNotNull);
    });

    test('complete exact hard contract remains executable', () {
      final signal = TradingSignal.fromMap(_canonicalSignal(setupReady: true));

      expect(signal.contractError, isNull);
      expect(signal.setupReady, isTrue);
      expect(signal.type, 'BUY');
      expect(signal.entryPrice, 100);
      expect(signal.slPrice, 99);
      expect(signal.tpPrices, [102, 103, 104]);
      expect(signal.probability, 82);
      expect(signal.probabilityAvailable, isTrue);
      expect(signal.canExecute, isTrue);
      final layer4 = signal.layers.firstWhere((layer) => layer['layer'] == 4);
      expect(layer4['entry_color'], '#0000FF');
      expect(layer4['curves'][0]['points'][2]['y'], 104);
    });

    test('hard contract rejects non-spec execution colors', () {
      final data = _canonicalSignal(setupReady: true);
      final layers = data['layers'] as Map<String, dynamic>;
      final execution = layers['layer4_execution'] as Map<String, dynamic>;
      execution['entry_color'] = 'blue';

      final signal = TradingSignal.fromMap(data);

      expect(signal.setupReady, isFalse);
      expect(signal.canExecute, isFalse);
      expect(signal.layers.any((layer) => layer['layer'] == 4), isFalse);
      expect(signal.contractError, contains('Layer 4'));
    });

    test(
      'unknown win probability is marked unavailable instead of invented',
      () {
        final data = _canonicalSignal(setupReady: true);
        final layers = data['layers'] as Map<String, dynamic>;
        final execution = layers['layer4_execution'] as Map<String, dynamic>;
        execution['prob'] = null;

        final signal = TradingSignal.fromMap(data);

        expect(signal.contractError, isNull);
        expect(signal.probability, 0);
        expect(signal.probabilityAvailable, isFalse);
        expect(signal.canExecute, isTrue);
      },
    );

    test('legacy object key cannot masquerade as Appendix-8 Layer 5', () {
      final data = _canonicalSignal();
      final layers = data['layers'] as Map<String, dynamic>;
      layers['layer5_environment'] = layers.remove('layer5_overlay');

      final signal = TradingSignal.fromMap(data);

      expect(signal.contractError, contains('layer envelope'));
      expect(signal.canExecute, isFalse);
    });
  });
}
