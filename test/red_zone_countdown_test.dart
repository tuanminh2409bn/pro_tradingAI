import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/material.dart';
import 'package:protrading_ai/data/models/trading_models.dart';
import 'package:protrading_ai/features/trading_room/web/widgets/kinetic_chart.dart';

void main() {
  test('red zone countdown is deterministic for an injected clock', () {
    expect(
      formatRedZoneCountdown(
        startTime: 1700000601,
        durationSeconds: 2700,
        nowEpochSeconds: 1700000000,
      ),
      ' T-11m',
    );
    expect(
      formatRedZoneCountdown(
        startTime: 1700000601,
        durationSeconds: 2700,
        nowEpochSeconds: 1700000601,
      ),
      ' LIVE',
    );
    expect(
      formatRedZoneCountdown(
        startTime: 1700000601,
        durationSeconds: 2700,
        nowEpochSeconds: 1700003301,
      ),
      isEmpty,
    );
  });

  testWidgets('active Red Zone clock repaints once per second', (tester) async {
    var clockCalls = 0;
    final now = DateTime.fromMillisecondsSinceEpoch(1700000000 * 1000);
    DateTime clock() {
      clockCalls += 1;
      return now;
    }

    const signal = TradingSignal(
      symbol: 'XAUUSD',
      entryPrice: 0,
      slPrice: 0,
      tpPrices: [],
      probability: 0,
      type: 'NEUTRAL',
      status: 'ACTIVE',
      layers: [
        {
          'layer': 5,
          'items': [
            {
              'type': 'red_zone',
              'start_time': 1700000600,
              'duration_min': 45,
              'label': 'CPI',
              'color': '#FF0000',
            },
          ],
        },
      ],
    );
    final candles = [
      Candle(
        timestamp: DateTime(2023, 11, 14, 22),
        open: 100,
        high: 101,
        low: 99,
        close: 100.5,
      ),
    ];
    await tester.pumpWidget(
      MaterialApp(
        home: SizedBox(
          width: 800,
          height: 500,
          child: KineticChart(
            symbol: 'XAUUSD',
            signal: signal,
            candles: candles,
            now: clock,
          ),
        ),
      ),
    );
    final callsAfterFirstPaint = clockCalls;

    await tester.pump(const Duration(seconds: 1));

    expect(clockCalls, greaterThan(callsAfterFirstPaint));
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
