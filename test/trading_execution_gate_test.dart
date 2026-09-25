import 'package:flutter_test/flutter_test.dart';
import 'package:protrading_ai/data/models/trading_models.dart';
import 'package:protrading_ai/features/trading_room/bloc/trading_room_bloc.dart';
import 'package:protrading_ai/features/trading_room/bloc/trading_room_event.dart';
import 'package:protrading_ai/features/trading_room/bloc/trading_room_state.dart';

const _account = TradingAccount(
  balance: 1000,
  equity: 1000,
  margin: 0,
  leverage: 100,
  status: 'DEMO',
);

TradingSignal _signal({
  String symbol = 'XAUUSD',
  String? chartId,
  bool ready = true,
  bool veto = false,
}) => TradingSignal(
  chartId: chartId ?? '${symbol}_5_1700000000',
  symbol: symbol,
  entryPrice: 2000,
  slPrice: 1990,
  tpPrices: const [2020, 2030, 2040],
  probability: 0,
  probabilityAvailable: false,
  type: 'BUY',
  status: 'ACTIVE',
  setupReady: ready,
  veto: veto,
  layers: const [
    {'layer': 4},
  ],
);

TradingRoomLoaded _state({
  TradingSignal? signal,
  String symbol = 'XAUUSD',
  String timeframe = '5',
  bool cutoff = false,
}) => TradingRoomLoaded(
  account: _account,
  currentSignal: signal ?? _signal(),
  currentSymbol: symbol,
  currentTimeframe: timeframe,
  isCutoffActive: cutoff,
);

ExecuteTrade _request({
  String chartId = 'XAUUSD_5_1700000000',
  String type = 'BUY',
  double entry = 2000,
  double stop = 1990,
  List<double> targets = const [2020, 2030, 2040],
}) => ExecuteTrade(
  signalChartId: chartId,
  type: type,
  lotSize: 0.1,
  entryPrice: entry,
  slPrice: stop,
  tpPrices: targets,
);

void main() {
  test('accepts only an exact request for the current Hard signal', () {
    expect(isClientTradeRequestAllowed(_state(), _request()), isTrue);
  });

  test('rejects Soft, Veto, cutoff, and cross-symbol states', () {
    expect(
      isClientTradeRequestAllowed(
        _state(signal: _signal(ready: false)),
        _request(),
      ),
      isFalse,
    );
    expect(
      isClientTradeRequestAllowed(
        _state(signal: _signal(veto: true)),
        _request(),
      ),
      isFalse,
    );
    expect(
      isClientTradeRequestAllowed(_state(cutoff: true), _request()),
      isFalse,
    );
    expect(
      isClientTradeRequestAllowed(
        _state(signal: _signal(symbol: 'EURUSD')),
        _request(chartId: 'EURUSD_5_1700000000'),
      ),
      isFalse,
    );
  });

  test('rejects stale identity and altered execution values', () {
    expect(
      isClientTradeRequestAllowed(_state(), _request(chartId: 'stale')),
      isFalse,
    );
    expect(
      isClientTradeRequestAllowed(_state(), _request(type: 'SELL')),
      isFalse,
    );
    expect(
      isClientTradeRequestAllowed(_state(), _request(entry: 2001)),
      isFalse,
    );
    expect(
      isClientTradeRequestAllowed(_state(), _request(stop: 1989)),
      isFalse,
    );
    expect(
      isClientTradeRequestAllowed(
        _state(),
        _request(targets: const [2020, 2030, 2050]),
      ),
      isFalse,
    );
  });

  test('rejects a Hard signal from a previous timeframe', () {
    expect(
      isClientTradeRequestAllowed(_state(timeframe: '15'), _request()),
      isFalse,
    );
  });

  test('accepts a timeframe alias but rejects mismatched chart identity', () {
    expect(
      isClientTradeRequestAllowed(_state(timeframe: 'M5'), _request()),
      isTrue,
    );
    expect(
      isClientTradeRequestAllowed(
        _state(signal: _signal(chartId: 'EURUSD_5_1700000000')),
        _request(chartId: 'EURUSD_5_1700000000'),
      ),
      isFalse,
    );
    expect(
      isClientTradeRequestAllowed(
        _state(signal: _signal(chartId: 'XAUUSD_UNKNOWN_1700000000')),
        _request(chartId: 'XAUUSD_UNKNOWN_1700000000'),
      ),
      isFalse,
    );
  });

  test('timeframe transition removes the previous executable signal', () {
    final next = stateAfterTimeframeChange(_state(), '15');
    expect(next.currentTimeframe, '15');
    expect(next.currentSignal, isNull);
  });

  test('selecting the same timeframe alias preserves the signal', () {
    final current = _state();
    final next = stateAfterTimeframeChange(current, 'M5');
    expect(next.currentSignal, same(current.currentSignal));
  });
}
