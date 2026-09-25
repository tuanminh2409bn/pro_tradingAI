import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:protrading_ai/core/localization/locale_cubit.dart';
import 'package:protrading_ai/data/models/trading_models.dart';
import 'package:protrading_ai/features/trading_room/web/widgets/forecast_panel.dart';

void main() {
  testWidgets('forecast panel renders the backend forecast below its parent', (
    tester,
  ) async {
    const signal = TradingSignal(
      symbol: 'XAUUSD',
      entryPrice: 0,
      slPrice: 0,
      tpPrices: [],
      probability: 0,
      type: 'NEUTRAL',
      status: 'ACTIVE',
      forecastText: 'Wait for price to enter the verified H4 zone.',
    );
    await tester.pumpWidget(
      BlocProvider(
        create: (_) => LocaleCubit(),
        child: const MaterialApp(
          home: Column(
            children: [
              SizedBox(key: ValueKey('chart-slot'), height: 200),
              ForecastPanel(signal: signal),
            ],
          ),
        ),
      ),
    );

    expect(find.byKey(const ValueKey('forecast-panel')), findsOneWidget);
    expect(find.textContaining('verified H4 zone'), findsOneWidget);
    expect(
      tester.getTopLeft(find.byKey(const ValueKey('forecast-panel'))).dy,
      greaterThanOrEqualTo(
        tester.getBottomLeft(find.byKey(const ValueKey('chart-slot'))).dy,
      ),
    );
  });

  testWidgets('forecast panel stays hidden when backend text is absent', (
    tester,
  ) async {
    await tester.pumpWidget(
      BlocProvider(
        create: (_) => LocaleCubit(),
        child: const MaterialApp(home: ForecastPanel(signal: null)),
      ),
    );
    expect(find.byKey(const ValueKey('forecast-panel')), findsNothing);
  });
}
