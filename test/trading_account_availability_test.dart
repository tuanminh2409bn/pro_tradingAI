import 'package:flutter_test/flutter_test.dart';
import 'package:protrading_ai/data/models/trading_models.dart';

void main() {
  test(
    'broker data is authoritative only with live status and named source',
    () {
      const unavailable = TradingAccount(
        balance: 0,
        equity: 0,
        margin: 0,
        leverage: 0,
        status: 'UNAVAILABLE',
      );
      const manualOnly = TradingAccount(
        balance: 10000,
        equity: 10000,
        margin: 0,
        leverage: 500,
        status: 'LIVE',
      );
      const broker = TradingAccount(
        balance: 10000,
        equity: 9950,
        margin: 250,
        leverage: 100,
        status: 'LIVE',
        source: 'metaapi:account-information',
      );

      expect(unavailable.hasAuthoritativeBrokerData, isFalse);
      expect(manualOnly.hasAuthoritativeBrokerData, isFalse);
      expect(broker.hasAuthoritativeBrokerData, isTrue);
    },
  );
}
