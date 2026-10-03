import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:protrading_ai/core/localization/locale_cubit.dart';
import 'package:protrading_ai/data/models/journal_models.dart';
import 'package:protrading_ai/data/repositories/journal_repository.dart';
import 'package:protrading_ai/features/journal/web/widgets/journal_equity_painter.dart';
import 'package:protrading_ai/features/journal/web/widgets/journal_heatmap.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'heatmap and insight use the same UTC day/hour across a local boundary',
    () {
      final instant = DateTime.utc(2026, 10, 4, 23, 30);
      final trades = [
        TradeRecord(
          symbol: 'BTCUSD',
          action: 'SHORT',
          lotSize: 0.1,
          entryPrice: 70000,
          exitPrice: 70100,
          netProfit: -20,
          closeTime: instant.toLocal(),
          executionMode: 'paper',
        ),
        TradeRecord(
          symbol: 'BTCUSD',
          action: 'LONG',
          lotSize: 0.1,
          entryPrice: 70000,
          exitPrice: 70100,
          netProfit: 5,
          closeTime: instant,
          executionMode: 'paper',
        ),
      ];
      final grouped = buildJournalHeatmap(trades);
      expect(grouped, [
        const HeatmapEntry(
          dayOfWeek: 7,
          hourSlot: 23,
          totalPnL: -15,
          tradeCount: 2,
        ),
      ]);
      final insight = buildJournalInsight(
        totalTrades: 2,
        winRate: 50,
        totalProfit: -15,
        bestTrade: 5,
        worstTrade: -20,
        profitFactor: 0.25,
        trades: trades,
      );
      expect(insight, contains('Sunday 23:00 UTC'));
    },
  );

  test('weekends remain visible and compact buckets merge count/PnL', () {
    const entries = [
      HeatmapEntry(dayOfWeek: 6, hourSlot: 6, totalPnL: 4, tradeCount: 1),
      HeatmapEntry(dayOfWeek: 7, hourSlot: 6, totalPnL: -20, tradeCount: 1),
      HeatmapEntry(dayOfWeek: 7, hourSlot: 7, totalPnL: 5, tradeCount: 2),
    ];
    final narrow = journalHeatmapBuckets(entries, compact: true);
    expect(narrow['6-3']!.totalPnL, 4);
    expect(
      narrow['7-3'],
      const HeatmapEntry(
        dayOfWeek: 7,
        hourSlot: 6,
        totalPnL: -15,
        tradeCount: 3,
      ),
    );
    final wide = journalHeatmapBuckets(entries, compact: false);
    expect(wide.length, 3);
    expect(wide['7-6']!.tradeCount, 1);
  });

  test('invalid day/hour/count/measurement never creates heatmap data', () {
    const invalid = [
      HeatmapEntry(dayOfWeek: 0, hourSlot: 6, totalPnL: 1, tradeCount: 1),
      HeatmapEntry(dayOfWeek: 8, hourSlot: 6, totalPnL: 1, tradeCount: 1),
      HeatmapEntry(dayOfWeek: 7, hourSlot: 24, totalPnL: 1, tradeCount: 1),
      HeatmapEntry(dayOfWeek: 7, hourSlot: -1, totalPnL: 1, tradeCount: 1),
      HeatmapEntry(dayOfWeek: 7, hourSlot: 6, totalPnL: 1, tradeCount: 0),
      HeatmapEntry(
        dayOfWeek: 7,
        hourSlot: 6,
        totalPnL: double.nan,
        tradeCount: 1,
      ),
    ];
    expect(journalHeatmapBuckets(invalid, compact: false), isEmpty);
  });

  testWidgets(
    '390px heatmap includes Sunday, labels count as trades, and uses UTC',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        BlocProvider(
          create: (_) => LocaleCubit(),
          child: const MaterialApp(
            home: Scaffold(
              body: JournalHeatmap(
                compact: true,
                data: [
                  HeatmapEntry(
                    dayOfWeek: 7,
                    hourSlot: 6,
                    totalPnL: -20,
                    tradeCount: 3,
                  ),
                ],
              ),
            ),
          ),
        ),
      );
      expect(find.text('SUN'), findsOneWidget);
      expect(find.text('UTC'), findsOneWidget);
      expect(find.byKey(const ValueKey('journal-heatmap-7-3')), findsOneWidget);
      final tooltip = tester.widget<Tooltip>(
        find.byKey(const ValueKey('journal-heatmap-7-3')),
      );
      expect(tooltip.message, 'SUN 06:00–07:59 UTC · 3 trades · P&L: -20.00');
      expect(tooltip.message, isNot(contains('Lots')));
      expect(tester.takeException(), isNull);
    },
  );

  Future<int> centerAlpha(List<double> data) async {
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    JournalEquityPainter(data: data).paint(canvas, const Size(200, 100));
    final picture = recorder.endRecording();
    final image = await picture.toImage(200, 100);
    try {
      final bytes = (await image.toByteData(
        format: ui.ImageByteFormat.rawRgba,
      ))!;
      return bytes.getUint8((50 * 200 + 100) * 4 + 3);
    } finally {
      image.dispose();
      picture.dispose();
    }
  }

  test('single equity point paints a visible finite point', () async {
    expect(await centerAlpha([83.05]), 255);
  });
  test(
    'flat equity paints through the center instead of the clipped edge',
    () async {
      expect(await centerAlpha([5, 5, 5]), 255);
    },
  );
  test('empty or invalid equity never paints a fabricated curve', () async {
    expect(await centerAlpha([]), 0);
    expect(await centerAlpha([double.nan]), 0);
    expect(await centerAlpha([1, double.infinity]), 0);
  });
}
