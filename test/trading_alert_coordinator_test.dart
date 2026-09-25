import 'package:flutter_test/flutter_test.dart';
import 'package:protrading_ai/data/models/trading_models.dart';
import 'package:protrading_ai/features/trading_room/services/trading_alert_coordinator.dart';

TradingSignal _signal({required bool ready, bool veto = false}) {
  return TradingSignal(
    chartId: 'XAUUSD_M5_1700000000',
    symbol: 'XAUUSD',
    entryPrice: ready ? 100 : 0,
    slPrice: ready ? 99 : 0,
    tpPrices: ready ? const [102, 103, 104] : const [],
    probability: 0,
    type: 'BUY',
    status: 'ACTIVE',
    setupReady: ready,
    veto: veto,
    layers: [
      const {
        'layer': 1,
        'items': [
          {'type': 'solid_box', 'y_top': 101, 'y_bottom': 99.5},
        ],
      },
      if (ready) const {'layer': 4, 'active': true},
    ],
  );
}

void main() {
  test('level one fires once when price enters a waiting zone', () {
    final coordinator = TradingAlertCoordinator();
    expect(
      coordinator.evaluate(
        signal: _signal(ready: false),
        currentPrice: 102,
        alertsEnabled: true,
      ),
      isEmpty,
    );
    final first = coordinator.evaluate(
      signal: _signal(ready: false),
      currentPrice: 100,
      alertsEnabled: true,
    );
    expect(first.single.level, TradingAlertLevel.waitingZone);
    expect(first.single.vibrate, isTrue);
    expect(first.single.siren, isFalse);
    expect(
      coordinator.evaluate(
        signal: _signal(ready: false),
        currentPrice: 100,
        alertsEnabled: true,
      ),
      isEmpty,
    );
  });

  test('hard transition fires level two once for the same chart', () {
    final coordinator = TradingAlertCoordinator();
    coordinator.evaluate(
      signal: _signal(ready: false),
      currentPrice: 100,
      alertsEnabled: true,
    );

    final hard = coordinator.evaluate(
      signal: _signal(ready: true),
      currentPrice: 100,
      alertsEnabled: true,
    );
    expect(hard.single.level, TradingAlertLevel.hardSetup);
    expect(hard.single.vibrate, isTrue);
    expect(hard.single.siren, isTrue);
    expect(
      coordinator.evaluate(
        signal: _signal(ready: true),
        currentPrice: 100,
        alertsEnabled: true,
      ),
      isEmpty,
    );
  });

  test('veto and user opt-out suppress every alert', () {
    final coordinator = TradingAlertCoordinator();
    expect(
      coordinator.evaluate(
        signal: _signal(ready: true, veto: true),
        currentPrice: 100,
        alertsEnabled: true,
      ),
      isEmpty,
    );
    expect(
      coordinator.evaluate(
        signal: _signal(ready: true),
        currentPrice: 100,
        alertsEnabled: false,
      ),
      isEmpty,
    );
  });
}
