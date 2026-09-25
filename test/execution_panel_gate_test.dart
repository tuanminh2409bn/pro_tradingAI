import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:protrading_ai/core/localization/locale_cubit.dart';
import 'package:protrading_ai/data/models/trading_models.dart';
import 'package:protrading_ai/features/trading_room/bloc/trading_room_bloc.dart';
import 'package:protrading_ai/features/trading_room/bloc/trading_room_event.dart';
import 'package:protrading_ai/features/trading_room/bloc/trading_room_state.dart';
import 'package:protrading_ai/features/trading_room/web/widgets/execution_panel.dart';

class _RecordingTradingRoomBloc implements TradingRoomBloc {
  _RecordingTradingRoomBloc(this._state);

  final TradingRoomLoaded _state;
  final events = <TradingRoomEvent>[];

  @override
  TradingRoomState get state => _state;

  @override
  Stream<TradingRoomState> get stream => const Stream.empty();

  @override
  void add(TradingRoomEvent event) => events.add(event);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

const _account = TradingAccount(
  balance: 1000,
  equity: 1000,
  margin: 0,
  leverage: 100,
  status: 'DEMO',
);

TradingSignal _signal({
  bool ready = true,
  bool veto = false,
  bool withChartId = true,
  String? contractError,
}) => TradingSignal(
  chartId: withChartId ? 'XAUUSD_5_1700000000' : null,
  symbol: 'XAUUSD',
  entryPrice: 2000,
  slPrice: 1990,
  tpPrices: const [2020, 2030, 2040],
  probability: 0,
  probabilityAvailable: false,
  type: 'BUY',
  status: 'ACTIVE',
  setupReady: ready,
  veto: veto,
  contractError: contractError,
  layers: const [
    {'layer': 4},
  ],
);

Future<_RecordingTradingRoomBloc> _pumpPanel(
  WidgetTester tester, {
  required TradingSignal signal,
  bool cutoff = false,
  String timeframe = '5',
}) async {
  final bloc = _RecordingTradingRoomBloc(
    TradingRoomLoaded(
      account: _account,
      currentSymbol: 'XAUUSD',
      currentTimeframe: timeframe,
      currentSignal: signal,
      isCutoffActive: cutoff,
    ),
  );
  await tester.pumpWidget(
    MultiBlocProvider(
      providers: [
        BlocProvider<TradingRoomBloc>.value(value: bloc),
        BlocProvider<LocaleCubit>(create: (_) => LocaleCubit()),
      ],
      child: MaterialApp(
        theme: ThemeData(splashFactory: NoSplash.splashFactory),
        home: const Scaffold(body: ExecutionPanel()),
      ),
    ),
  );
  return bloc;
}

void main() {
  testWidgets('missing market price does not show invented bid or ask', (
    tester,
  ) async {
    await _pumpPanel(tester, signal: _signal(ready: false));
    expect(find.text('-0.15'), findsNothing);
    expect(find.text('0.15'), findsNothing);
    expect(find.text('3.0'), findsNothing);
    expect(find.text('—'), findsNWidgets(3));
  });

  testWidgets('Soft, Veto and daily cutoff expose no order action', (
    tester,
  ) async {
    for (final (signal, cutoff) in [
      (_signal(ready: false), false),
      (_signal(veto: true), false),
      (_signal(), true),
    ]) {
      await _pumpPanel(tester, signal: signal, cutoff: cutoff);
      expect(find.byKey(const ValueKey('execute-buy')), findsNothing);
      expect(find.byKey(const ValueKey('execute-sell')), findsNothing);
    }
  });

  testWidgets('Hard Setup sends a request without claiming execution success', (
    tester,
  ) async {
    final bloc = await _pumpPanel(tester, signal: _signal());
    final buy = find.byKey(const ValueKey('execute-buy'));
    expect(buy, findsOneWidget);
    await tester.ensureVisible(buy);
    await tester.tap(buy);
    await tester.pump();

    final requests = bloc.events.whereType<ExecuteTrade>().toList();
    expect(requests, hasLength(1));
    expect(requests.single.signalChartId, 'XAUUSD_5_1700000000');
    expect(find.textContaining('order submitted'), findsNothing);
  });

  testWidgets('a Hard signal from another timeframe has no order controls', (
    tester,
  ) async {
    await _pumpPanel(tester, signal: _signal(), timeframe: '15');
    expect(find.byKey(const ValueKey('execute-buy')), findsNothing);
    expect(find.byKey(const ValueKey('execute-sell')), findsNothing);
  });

  testWidgets('a contract-invalid Hard signal has no order controls', (
    tester,
  ) async {
    await _pumpPanel(tester, signal: _signal(contractError: 'invalid layer'));
    expect(find.byKey(const ValueKey('execute-buy')), findsNothing);
    expect(find.byKey(const ValueKey('execute-sell')), findsNothing);
  });

  testWidgets('a legacy Soft signal remains visible but cannot execute', (
    tester,
  ) async {
    await _pumpPanel(tester, signal: _signal(ready: false, withChartId: false));
    expect(find.textContaining('SOFT ALERT'), findsOneWidget);
    expect(find.byKey(const ValueKey('execute-buy')), findsNothing);
    expect(find.byKey(const ValueKey('execute-sell')), findsNothing);
  });
}
