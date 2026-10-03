import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:protrading_ai/core/localization/locale_cubit.dart';
import 'package:protrading_ai/data/models/journal_models.dart';
import 'package:protrading_ai/features/journal/web/widgets/journal_trade_log.dart';

void main() {
  final trades = <TradeRecord>[
    TradeRecord(
      symbol: 'EURUSD',
      action: 'LONG',
      lotSize: 0.1,
      entryPrice: 1.1,
      exitPrice: 1.2,
      netProfit: 10,
      closeTime: DateTime.utc(2026, 10, 4),
      executionMode: 'paper',
    ),
    TradeRecord(
      symbol: 'BTCUSD',
      action: 'SHORT',
      lotSize: 0.2,
      entryPrice: 70000,
      exitPrice: 70100,
      netProfit: -20,
      closeTime: DateTime.utc(2026, 10, 4),
      executionMode: 'paper',
    ),
  ];

  Future<void> show(
    WidgetTester tester, {
    List<TradeRecord>? records,
    Future<bool> Function(String, String)? download,
    String scope = 'qa-one',
  }) async {
    await tester.pumpWidget(
      BlocProvider(
        create: (_) => LocaleCubit(),
        child: MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: JournalTradeLog(
                trades: records ?? trades,
                scopeId: scope,
                download: download,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> selectShort(WidgetTester tester) async {
    await tester.tap(find.byKey(const ValueKey('journal-filter')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('journal-filter-side')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('SHORT').last);
    await tester.pumpAndSettle();
  }

  testWidgets('Apply filters rows and export; reset restores source', (
    tester,
  ) async {
    String? exported;
    String? filename;
    await show(
      tester,
      download: (csv, name) async {
        exported = csv;
        filename = name;
        return true;
      },
    );
    await selectShort(tester);
    await tester.tap(find.byKey(const ValueKey('journal-filter-apply')));
    await tester.pumpAndSettle();
    expect(find.text('EURUSD'), findsNothing);
    expect(find.text('BTCUSD'), findsOneWidget);
    expect(find.text('1 / 2'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('journal-export-csv')));
    await tester.pumpAndSettle();
    expect(exported, contains('BTCUSD'));
    expect(exported, isNot(contains('EURUSD')));
    expect(filename, matches(r'^protrading-journal-\d{4}-\d{2}-\d{2}\.csv$'));
    expect(find.text('Download request sent to the browser.'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('journal-filter-reset')));
    await tester.pumpAndSettle();
    expect(find.text('EURUSD'), findsOneWidget);
    expect(find.text('2 / 2'), findsOneWidget);
  });

  testWidgets(
    'Cancel keeps prior filter; refreshed stream applies current filter',
    (tester) async {
      await show(tester);
      await selectShort(tester);
      await tester.tap(find.byKey(const ValueKey('journal-filter-cancel')));
      await tester.pumpAndSettle();
      expect(find.text('EURUSD'), findsOneWidget);
      await selectShort(tester);
      await tester.tap(find.byKey(const ValueKey('journal-filter-apply')));
      await tester.pumpAndSettle();
      await show(tester, records: [trades.first]);
      await tester.pumpAndSettle();
      expect(find.text('No trades match the filters.'), findsOneWidget);
      expect(find.text('0 / 1'), findsOneWidget);
      final button = tester.widget<OutlinedButton>(
        find.byKey(const ValueKey('journal-export-csv')),
      );
      expect(button.onPressed, isNull);
      await show(tester, scope: 'qa-two');
      await tester.pumpAndSettle();
      expect(find.text('2 / 2'), findsOneWidget);
    },
  );

  testWidgets(
    'one download at a time, failure recovers, no stale completion after owner change',
    (tester) async {
      final pending = Completer<bool>();
      var calls = 0;
      Future<bool> download(String _, String __) {
        calls++;
        return pending.future;
      }

      await show(tester, download: download);
      await tester.tap(find.byKey(const ValueKey('journal-export-csv')));
      await tester.pump();
      expect(calls, 1);
      expect(
        tester
            .widget<OutlinedButton>(
              find.byKey(const ValueKey('journal-export-csv')),
            )
            .onPressed,
        isNull,
      );
      await show(tester, download: download, scope: 'qa-two');
      await tester.pump();
      pending.complete(false);
      await tester.pumpAndSettle();
      expect(find.text('CSV download could not start.'), findsNothing);
      expect(
        tester
            .widget<OutlinedButton>(
              find.byKey(const ValueKey('journal-export-csv')),
            )
            .onPressed,
        isNotNull,
      );
    },
  );

  testWidgets('download error is visible and controls remain usable', (
    tester,
  ) async {
    await show(
      tester,
      download: (_, __) async => throw StateError('test only'),
    );
    await tester.tap(find.byKey(const ValueKey('journal-export-csv')));
    await tester.pumpAndSettle();
    expect(find.text('CSV download could not start.'), findsOneWidget);
    expect(
      tester
          .widget<OutlinedButton>(
            find.byKey(const ValueKey('journal-export-csv')),
          )
          .onPressed,
      isNotNull,
    );
  });

  testWidgets('390px keeps accessible actions and empty export is disabled', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await show(tester, records: [], download: (_, __) async => true);
    await tester.pumpAndSettle();
    expect(find.text('Export CSV'), findsOneWidget);
    expect(find.text('Filter'), findsOneWidget);
    expect(find.text('No trades recorded yet'), findsOneWidget);
    expect(
      tester
          .widget<OutlinedButton>(
            find.byKey(const ValueKey('journal-export-csv')),
          )
          .onPressed,
      isNull,
    );
    expect(tester.takeException(), isNull);
  });
}
