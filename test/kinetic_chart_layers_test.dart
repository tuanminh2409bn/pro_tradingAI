import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:protrading_ai/data/models/trading_models.dart';
import 'package:protrading_ai/features/trading_room/web/widgets/kinetic_chart.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test('Layer 1 geometry remaps through shared pan and zoom coordinates', () {
    final candles = List.generate(
      12,
      (index) => Candle(
        timestamp: DateTime.fromMillisecondsSinceEpoch(
          (1_700_000_000 + index * 300) * 1000,
        ),
        open: 100 + index * 0.1,
        high: 101 + index * 0.1,
        low: 99 + index * 0.1,
        close: 100.5 + index * 0.1,
        volume: 10,
      ),
    );
    const size = Size(800, 500);
    const baseViewport = (
      scaleX: 1.0,
      scaleY: 1.0,
      offsetX: 0.0,
      priceOffset: 0.0,
    );
    Offset map(int timestamp, double price, ChartViewportState viewport) =>
        mapAnalysisPoint(
          candles: candles,
          timestamp: timestamp,
          price: price,
          size: size,
          viewport: viewport,
        );

    final first = map(1700000600, 100, baseViewport);
    final second = map(1700002400, 102, baseViewport);
    final panned = map(1700000600, 100, (
      scaleX: 1.0,
      scaleY: 1.0,
      offsetX: 40.0,
      priceOffset: -0.5,
    ));
    final zoomedFirst = map(1700000600, 100, (
      scaleX: 2.0,
      scaleY: 2.0,
      offsetX: 0.0,
      priceOffset: 0.0,
    ));
    final zoomedSecond = map(1700002400, 102, (
      scaleX: 2.0,
      scaleY: 2.0,
      offsetX: 0.0,
      priceOffset: 0.0,
    ));

    expect(panned.dx - first.dx, closeTo(40, 0.0001));
    expect(panned.dy, isNot(closeTo(first.dy, 0.0001)));
    expect(
      (zoomedSecond.dx - zoomedFirst.dx).abs(),
      closeTo((second.dx - first.dx).abs() * 2, 0.0001),
    );
    expect(
      (zoomedSecond.dy - zoomedFirst.dy).abs(),
      closeTo((second.dy - first.dy).abs() * 2, 0.0001),
    );
  });

  testWidgets('V2.1 object layers render together without contract fallback', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final candles = List.generate(
      12,
      (index) => Candle(
        timestamp: DateTime.fromMillisecondsSinceEpoch(
          (1_700_000_000 + index * 300) * 1000,
        ),
        open: 100 + index * 0.1,
        high: 101 + index * 0.1,
        low: 99 + index * 0.1,
        close: 100.5 + index * 0.1,
        volume: 10,
      ),
    );
    Map<String, dynamic> evidence(String id, int timestamp) => {
      'source': 'fixture',
      'source_id': id,
      'timestamp': timestamp,
    };
    String? selectedTimeframe;
    final signal = TradingSignal.fromMap({
      'chart_id': 'XAUUSD_M5_1700003300',
      'setup_ready': true,
      'veto': false,
      'veto_data': null,
      'fallback': false,
      'forecast_text': 'Fixture hard setup.',
      'layers': {
        'layer1_structural': [
          {
            'type': 'dashed_line',
            'label': 'BOS',
            'color': '#FFD700',
            'x1': 1700000300,
            'y1': 99.5,
            'x2': 1700002400,
            'y2': 103,
            'evidence': evidence('BOS', 1700002400),
          },
          {
            'type': 'solid_box',
            'label': 'OB',
            'color': '#00FF7F',
            'x': 1700000600,
            'x_end': 1700001800,
            'y_top': 102,
            'y_bottom': 100,
            'evidence': evidence('OB', 1700000600),
          },
          {
            'type': 'bordered_box',
            'label': 'MIT',
            'color': '#F0E68C',
            'x': 1700001200,
            'x_end': 1700002700,
            'y_top': 104,
            'y_bottom': 103,
            'evidence': evidence('MIT', 1700001200),
          },
        ],
        'layer2_trap': [
          {
            'type': 'text_tag',
            'text': r'$$$',
            'color': '#FF0000',
            'x': 1700001500,
            'y': 103,
            'evidence': evidence('BSL', 1700001500),
          },
          {
            'type': 'text_tag',
            'text': 'LIQ',
            'color': '#A9A9A9',
            'background_color': '#D3D3D3',
            'x': 1700001800,
            'y': 102,
            'evidence': evidence('LIQ', 1700001800),
          },
          {
            'type': 'arrow',
            'direction': 'down',
            'label': 'TYPE1',
            'color': '#FF0000',
            'x': 1700001800,
            'y': 104,
            'evidence': evidence('TYPE1', 1700001800),
          },
          {
            'type': 'volume_tag',
            'text': 'STOP',
            'color': '#8A2BE2',
            'x': 1700002100,
            'y': 104,
            'evidence': evidence('STOP', 1700002100),
          },
        ],
        'layer3_candle': [
          {
            'timestamp': 1700002100,
            'fill_color': '#8A2BE2',
            'border': '#FFD700',
            'text': 'BC',
            'divergence': 'up',
            'divergence_color': '#00FF7F',
            'evidence': evidence('BC', 1700002100),
          },
        ],
        'layer4_execution': {
          'active': true,
          'entry': 101,
          'entry_color': '#0000FF',
          'sl': 99,
          'sl_color': '#FF0000',
          'tp': [105, 107, 109],
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
                {'x': 1700002100, 'y': 101},
                {'x': 1700002600, 'y': 105},
                {'x': 1700003300, 'y': 109},
              ],
            },
            {
              'id': 'SIG_2',
              'type': 'bezier_cubic',
              'style': 'dashed',
              'color': '#1E90FF',
              'points': [
                {'x': 1700002100, 'y': 101},
                {'x': 1700002400, 'y': 100},
                {'x': 1700002800, 'y': 105},
                {'x': 1700003300, 'y': 109},
              ],
            },
          ],
        },
        'layer5_overlay': [
          {
            'type': 'ghost_box',
            'opacity': 0.15,
            'color': '#FF4500',
            'x': 1700000300,
            'x_end': 1700003300,
            'y_top': 101.4,
            'y_bottom': 100.8,
            'tooltip': 'H4 supply zone',
            'evidence': evidence('H4-OB', 1700000300),
          },
          {
            'type': 'phase_tracker_text',
            'label': 'PHASE C',
            'color': '#FFFFFF',
            'evidence': evidence('PHASE-C', 1700002100),
          },
          {
            'type': 'red_zone',
            'start_time': 1700003000,
            'duration_min': 30,
            'label': 'CPI',
            'color': '#FF0000',
            'evidence': evidence('CPI', 1700003000),
          },
          {
            'type': 'htf_trend',
            'htf1_label': 'H4',
            'htf1_trend': 'Bearish',
            'htf2_label': 'D1',
            'htf2_trend': 'Bullish',
            'color': '#FFFFFF',
            'evidence': evidence('HTF-TREND', 1700002100),
          },
        ],
      },
    });

    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(splashFactory: NoSplash.splashFactory),
        home: Scaffold(
          body: SizedBox(
            width: 900,
            height: 500,
            child: KineticChart(
              symbol: 'XAUUSD',
              signal: signal,
              candles: candles,
              onTimeframeSelected: (value) => selectedTimeframe = value,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(signal.contractError, isNull);
    expect(find.byType(CustomPaint), findsWidgets);
    await tester.tap(find.byKey(const ValueKey('ghost-box-1700000300')));
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text('H4 supply zone'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('htf-trend-H4')));
    await tester.pump();
    expect(selectedTimeframe, 'H4');
    await tester.dragFrom(const Offset(300, 485), const Offset(80, 0));
    await tester.dragFrom(const Offset(870, 260), const Offset(0, -60));
    await tester.dragFrom(const Offset(450, 250), const Offset(35, 25));
    await tester.pump();
    expect(tester.takeException(), isNull);
  });
}
