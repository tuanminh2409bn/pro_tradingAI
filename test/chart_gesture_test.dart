import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:protrading_ai/data/models/trading_models.dart';
import 'package:protrading_ai/features/trading_room/web/widgets/kinetic_chart.dart';

List<Candle> _candles() => List.generate(
  80,
  (index) => Candle(
    timestamp: DateTime.fromMillisecondsSinceEpoch(
      (1700000000 + index * 300) * 1000,
    ),
    open: 100 + index / 10,
    high: 101 + index / 10,
    low: 99 + index / 10,
    close: 100.5 + index / 10,
  ),
);

class _ViewportProbe {
  ChartViewportState? latest;
  void update(ChartViewportState value) => latest = value;
}

Future<void> _pumpChart(WidgetTester tester, _ViewportProbe probe) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Center(
        child: SizedBox(
          width: 800,
          height: 500,
          child: KineticChart(
            key: UniqueKey(),
            symbol: 'XAUUSD',
            candles: _candles(),
            onViewportChanged: probe.update,
          ),
        ),
      ),
    ),
  );
}

Future<ChartViewportState> _dragChart(
  WidgetTester tester, {
  required Offset start,
  required Offset delta,
}) async {
  final probe = _ViewportProbe();
  await _pumpChart(tester, probe);
  await tester.dragFrom(start, delta);
  await tester.pump();
  return probe.latest!;
}

void main() {
  testWidgets('dragging the bottom time axis changes X scale only', (
    tester,
  ) async {
    final viewport = await _dragChart(
      tester,
      start: const Offset(300, 545),
      delta: const Offset(90, 0),
    );
    expect(viewport.scaleX, greaterThan(1));
    expect(viewport.scaleY, 1);
  });

  testWidgets('dragging the right price axis changes Y scale only', (
    tester,
  ) async {
    final viewport = await _dragChart(
      tester,
      start: const Offset(755, 300),
      delta: const Offset(0, -90),
    );
    expect(viewport.scaleY, greaterThan(1));
    expect(viewport.scaleX, 1);
  });

  testWidgets('dragging chart center pans time and price together', (
    tester,
  ) async {
    final viewport = await _dragChart(
      tester,
      start: const Offset(400, 300),
      delta: const Offset(50, 40),
    );
    expect(viewport.offsetX, isNot(0));
    expect(viewport.priceOffset, isNot(0));
  });

  testWidgets('mouse wheel over chart center zooms the time axis', (
    tester,
  ) async {
    final probe = _ViewportProbe();
    await _pumpChart(tester, probe);

    await tester.sendEventToBinding(
      const PointerScrollEvent(
        position: Offset(400, 300),
        scrollDelta: Offset(0, -20),
      ),
    );
    await tester.pump();

    expect(probe.latest?.scaleX, greaterThan(1));
    expect(probe.latest?.scaleY, 1);
  });

  testWidgets('two-pointer pinch zooms chart-center time scale', (
    tester,
  ) async {
    final probe = _ViewportProbe();
    await _pumpChart(tester, probe);
    final left = await tester.createGesture(pointer: 1);
    final right = await tester.createGesture(pointer: 2);

    await left.down(const Offset(350, 300));
    await right.down(const Offset(450, 300));
    await tester.pump();
    await left.moveTo(const Offset(300, 300));
    await right.moveTo(const Offset(500, 300));
    await tester.pump();
    await left.up();
    await right.up();

    expect(probe.latest?.scaleX, greaterThan(1));
  });
}
