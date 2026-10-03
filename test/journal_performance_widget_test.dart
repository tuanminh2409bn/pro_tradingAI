import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:protrading_ai/core/localization/locale_cubit.dart';
import 'package:protrading_ai/data/models/journal_models.dart';
import 'package:protrading_ai/data/repositories/journal_repository.dart';
import 'package:protrading_ai/features/journal/web/widgets/journal_audio_button.dart';
import 'package:protrading_ai/features/journal/web/widgets/journal_performance.dart';

void main() {
  TradeRecord trade(double pnl) => TradeRecord(
    symbol: 'EURUSD',
    action: 'LONG',
    lotSize: 0.1,
    entryPrice: 1.1,
    exitPrice: 1.2,
    netProfit: pnl,
    closeTime: DateTime.utc(2026, 10, 4, 6),
    executionMode: 'paper',
  );

  Future<void> show(
    WidgetTester tester,
    Widget child, {
    String language = 'en',
    double textScale = 1,
  }) => tester.pumpWidget(
    BlocProvider(
      create: (_) => LocaleCubit()..setLanguage(language),
      child: MaterialApp(
        home: MediaQuery(
          data: MediaQueryData(
            size: const Size(390, 844),
            textScaler: TextScaler.linear(textScale),
          ),
          child: Scaffold(body: SingleChildScrollView(child: child)),
        ),
      ),
    ),
  );

  testWidgets(
    'all-wins ratios explain absence of losses without zero or infinity',
    (tester) async {
      await show(
        tester,
        JournalPerformanceMetrics(
          stats: buildJournalStats([trade(10), trade(20)]),
          compact: true,
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('No losing trades in this sample'), findsOneWidget);
      expect(find.text('—'), findsNWidgets(2));
      expect(find.text('100.0%'), findsOneWidget);
      expect(find.text('0.00'), findsNothing);
      expect(find.textContaining('Infinity'), findsNothing);
    },
  );

  testWidgets(
    'measured summary is localized, has exact counts and feeds the same text to audio',
    (tester) async {
      final stats = buildJournalStats([trade(12.34), trade(-20.25), trade(0)]);
      await show(
        tester,
        JournalPerformanceSummary(stats: stats),
        language: 'vi',
      );
      await tester.pumpAndSettle();
      expect(find.text('TÓM TẮT HIỆU SUẤT'), findsOneWidget);
      expect(find.text('Thắng 1 · Thua 1 · Hòa vốn 1'), findsOneWidget);
      final audio = tester.widget<JournalAudioButton>(
        find.byType(JournalAudioButton),
      );
      expect(audio.insight, contains('P&L ròng -7.91'));
      expect(audio.insight, contains('CN 06:00 UTC, 1 lệnh lỗ'));
      expect(find.text(audio.insight), findsOneWidget);
      expect(audio.insight, isNot(contains(r'$')));
      expect(find.byType(LinearProgressIndicator), findsNothing);
      expect(find.text('ĐIỂM TÂM LÝ'), findsNothing);
      expect(find.textContaining('Chưa đo kỷ luật'), findsOneWidget);
    },
  );

  testWidgets('390 px Vietnamese metrics tolerate enlarged text', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await show(
      tester,
      JournalPerformanceMetrics(
        stats: buildJournalStats([trade(10)]),
        compact: true,
      ),
      language: 'vi',
      textScale: 2,
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.text('Mẫu này chưa có lệnh lỗ'), findsOneWidget);
  });

  testWidgets('empty summary passes no-trades sentinel to disabled audio', (
    tester,
  ) async {
    await show(
      tester,
      JournalPerformanceSummary(stats: buildJournalStats(const [])),
    );
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<JournalAudioButton>(find.byType(JournalAudioButton))
          .insight,
      '__NO_TRADES__',
    );
    expect(find.byType(LinearProgressIndicator), findsNothing);
  });
}
