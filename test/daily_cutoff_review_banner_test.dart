import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:protrading_ai/core/localization/locale_cubit.dart';
import 'package:protrading_ai/data/models/trading_models.dart';
import 'package:protrading_ai/features/trading_room/web/widgets/daily_cutoff_review_banner.dart';

void main() {
  testWidgets('review displays persisted figures before acknowledging', (
    tester,
  ) async {
    var reviews = 0;
    var acknowledgements = 0;
    await tester.pumpWidget(
      BlocProvider(
        create: (_) => LocaleCubit(),
        child: MaterialApp(
          home: Scaffold(
            body: DailyCutoffReviewBanner(
              review: () async {
                reviews++;
                return const DailyCutoffStatus(
                  active: true,
                  reviewed: true,
                  sessionDate: '2026-09-24',
                  realizedPnl: -20,
                  floatingPnl: -30,
                  lossLimit: 50,
                );
              },
              acknowledge: () async {
                acknowledgements++;
                return const DailyCutoffStatus(
                  active: true,
                  reviewed: true,
                  acknowledged: true,
                );
              },
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.byKey(const ValueKey('cutoff-review')));
    await tester.pumpAndSettle();
    expect(reviews, 1);
    expect(find.textContaining('2026-09-24'), findsOneWidget);
    expect(find.textContaining('-20.00'), findsOneWidget);
    expect(acknowledgements, 0);
    await tester.tap(find.text('I acknowledge'));
    await tester.pumpAndSettle();
    expect(acknowledgements, 1);
  });
}
