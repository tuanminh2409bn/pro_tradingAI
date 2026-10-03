import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:protrading_ai/core/localization/locale_cubit.dart';
import 'package:protrading_ai/data/models/radar_models.dart';
import 'package:protrading_ai/data/repositories/radar_repository.dart';
import 'package:protrading_ai/features/radar/web/radar_web_page.dart';
import 'package:protrading_ai/logic/navigation_cubit.dart';

class _RadarRepository extends Fake implements RadarRepository {
  final snapshots = StreamController<List<RadarAsset>>.broadcast();
  @override
  Stream<List<RadarAsset>> getRadarAssets() => snapshots.stream;
}

RadarAsset radarFixture({double price = 1.1234567, bool verified = false}) =>
    RadarAsset(
      symbol: 'EURUSD',
      fullName: 'EUR / USD',
      price: price,
      changePercent: -0.08,
      volatilityStatus: 'STABLE',
      hasAiConfirmation: verified,
      aiSignal: verified ? 'BUY' : 'NEUTRAL',
      sparklineData: const [],
      confirmationId: verified ? 'qa-emulator-only' : null,
      rationale: verified ? 'Test fixture, not a real AI confirmation' : null,
      provider: verified ? 'qa-emulator-fixture' : null,
      model: verified ? 'qa-fixture-no-model-call' : null,
      licenseRef: verified ? 'test-only' : null,
      timeframe: 'H4',
      confirmedAt: verified ? DateTime.utc(2026, 10, 4) : null,
    );

void main() {
  Future<_RadarRepository> show(
    WidgetTester tester, {
    Size size = const Size(1280, 900),
    double textScale = 1,
    String language = 'en',
    NavigationCubit? navigation,
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final repository = _RadarRepository();
    addTearDown(repository.snapshots.close);
    await tester.pumpWidget(
      MultiBlocProvider(
        providers: [
          BlocProvider(create: (_) => LocaleCubit()..setLanguage(language)),
          BlocProvider(
            create: (_) =>
                navigation ??
                (NavigationCubit()..getNavBarItem(NavbarItem.radar)),
          ),
        ],
        child: RepositoryProvider<RadarRepository>.value(
          value: repository,
          child: MaterialApp(
            home: MediaQuery(
              data: MediaQueryData(
                size: size,
                textScaler: TextScaler.linear(textScale),
              ),
              child: const RadarWebPage(),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    repository.snapshots.add([radarFixture()]);
    await tester.pump();
    await tester.pump();
    return repository;
  }

  testWidgets(
    'unconfirmed snapshot has no invented signal strength or USD price',
    (tester) async {
      await show(tester);
      expect(
        find.text('No measured signal strength is available.'),
        findsOneWidget,
      );
      expect(find.text('1.1234567'), findsOneWidget);
      expect(find.textContaining(r'$1.12'), findsNothing);
      expect(find.textContaining('REAL-TIME'), findsNothing);
      expect(find.textContaining('TODAY'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('390 px Vietnamese Radar tolerates text scale 2', (tester) async {
    await show(
      tester,
      size: const Size(390, 844),
      textScale: 2,
      language: 'vi',
    );
    expect(tester.takeException(), isNull);
    expect(find.text('Chưa có số đo độ mạnh tín hiệu.'), findsOneWidget);
  });

  testWidgets('Radar opens the selected symbol and only a verified timeframe', (
    tester,
  ) async {
    final navigation = NavigationCubit()..getNavBarItem(NavbarItem.radar);
    final repository = await show(tester, navigation: navigation);
    await tester.tap(find.text('OPEN TRADING ROOM'));
    expect(navigation.state, NavbarItem.tradingRoom);
    expect(navigation.tradingRoomSymbol, 'EURUSD');
    expect(navigation.tradingRoomTimeframe, isNull);
    navigation.getNavBarItem(NavbarItem.radar);
    repository.snapshots.add([radarFixture(verified: true)]);
    await tester.pump();
    await tester.pump();
    await tester.tap(find.text('OPEN TRADING ROOM'));
    expect(navigation.tradingRoomTimeframe, '240');
    expect(tester.takeException(), isNull);
  });
}
