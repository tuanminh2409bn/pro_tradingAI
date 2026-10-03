import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:protrading_ai/data/models/trading_models.dart';
import 'package:protrading_ai/data/repositories/trading_repository.dart';
import 'package:protrading_ai/features/trading_room/bloc/trading_room_bloc.dart';
import 'package:protrading_ai/features/trading_room/bloc/trading_room_event.dart';
import 'package:protrading_ai/features/trading_room/bloc/trading_room_state.dart';
import 'package:protrading_ai/logic/navigation_cubit.dart';

class _Repository extends Fake implements TradingRepository {
  final symbols = <String>[];
  final timeframes = <String>[];
  int analysisRequests = 0;

  @override
  void changeSymbol(String symbol) => symbols.add(symbol);
  @override
  void changeTimeframe(String timeframe) => timeframes.add(timeframe);
  @override
  Stream<TradingAccount> getTradingAccount(String userId) =>
      const Stream.empty();
  @override
  Stream<List<Candle>> getCandleStream(String symbol) => const Stream.empty();
  @override
  Stream<List<TradingSignal>> getActiveSignals(String userId) =>
      const Stream.empty();
  @override
  Stream<Map<String, double>> get priceBookStream => const Stream.empty();
  @override
  Map<String, double> get symbolPrices => const {};
  @override
  Future<void> requestAnalysis(
    String symbol,
    String timeframe, {
    String userId = '',
    String? tradingMode,
  }) async {
    analysisRequests++;
  }
}

Future<void> flush() async {
  for (var i = 0; i < 6; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'normal navigation clears the transient chart request; invalid targets do not navigate',
    () async {
      final navigation = NavigationCubit()..getNavBarItem(NavbarItem.radar);
      addTearDown(navigation.close);
      expect(navigation.openTradingRoom(' ethusd ', timeframe: 'h4'), isTrue);
      expect(navigation.tradingRoomSymbol, 'ETHUSD');
      expect(navigation.tradingRoomTimeframe, '240');
      navigation.getNavBarItem(NavbarItem.newsFeed);
      expect(navigation.tradingRoomSymbol, isNull);
      expect(navigation.tradingRoomTimeframe, isNull);
      expect(navigation.openTradingRoom('ETH/USD'), isFalse);
      expect(navigation.openTradingRoom('ETHUSD', timeframe: 'M1'), isFalse);
      expect(navigation.state, NavbarItem.newsFeed);
      expect(navigation.tradingRoomSymbol, isNull);
    },
  );

  test(
    'explicit Radar target wins over saved symbol and matches repository timeframe/mode',
    () async {
      SharedPreferences.setMockInitialValues({'selected_symbol': 'BTCUSD'});
      for (final frame in ['M5', 'M15', 'H1', 'H4', 'D1']) {
        final repository = _Repository();
        final bloc = TradingRoomBloc(tradingRepository: repository);
        bloc.add(
          LoadTradingData(initialSymbol: ' ethusd ', initialTimeframe: frame),
        );
        await flush();
        final result = bloc.state as TradingRoomLoaded;
        expect(result.currentSymbol, 'ETHUSD');
        expect(
          result.currentTimeframe,
          TradingMode.scalping.normalizeTimeframe(frame),
        );
        expect(
          result.tradingMode.allowsTimeframe(result.currentTimeframe),
          isTrue,
        );
        expect(repository.symbols, ['ETHUSD']);
        expect(repository.timeframes, [result.currentTimeframe]);
        expect(result.currentSignal, isNull);
        expect(result.isAnalyzing, isFalse);
        expect(repository.analysisRequests, 0);
        await bloc.close();
      }
    },
  );

  test(
    'ordinary Trading Room entry still restores saved symbol and resets repository to M5',
    () async {
      SharedPreferences.setMockInitialValues({'selected_symbol': 'BTCUSD'});
      final repository = _Repository();
      final bloc = TradingRoomBloc(tradingRepository: repository);
      addTearDown(bloc.close);
      bloc.add(const LoadTradingData());
      await flush();
      expect((bloc.state as TradingRoomLoaded).currentSymbol, 'BTCUSD');
      expect(repository.symbols, ['XAUUSD', 'BTCUSD']);
      expect(repository.timeframes, ['5']);
      expect(repository.analysisRequests, 0);
    },
  );
}
