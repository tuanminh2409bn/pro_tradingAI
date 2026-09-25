import 'package:flutter_test/flutter_test.dart';
import 'package:protrading_ai/data/models/trading_models.dart';
import 'package:protrading_ai/features/trading_room/bloc/trading_room_bloc.dart';

Position _position(String id, double profit) => Position(
  id: id,
  symbol: 'XAUUSD',
  type: 'BUY',
  lotSize: 0.1,
  openPrice: 2000,
  profit: profit,
);

void main() {
  const risk = RiskConfig(balance: 1000, riskPerTrade: 1, maxDailyLoss: 5);

  test('cutoff includes realized and floating daily loss', () {
    final positions = [_position('one', -35), _position('two', -10)];
    expect(dailyPnLIncludingFloating(-5, positions), -50);
    expect(
      shouldActivateDailyLossCutoff(
        alreadyActive: false,
        realizedPnL: -5,
        openPositions: positions,
        riskConfig: risk,
      ),
      isTrue,
    );
  });

  test('cutoff stays latched after floating PnL recovers', () {
    expect(
      shouldActivateDailyLossCutoff(
        alreadyActive: true,
        realizedPnL: 0,
        openPositions: [_position('one', 100)],
        riskConfig: risk,
      ),
      isTrue,
    );
  });

  test('loss below threshold does not activate cutoff', () {
    expect(
      shouldActivateDailyLossCutoff(
        alreadyActive: false,
        realizedPnL: -10,
        openPositions: [_position('one', -39.99)],
        riskConfig: risk,
      ),
      isFalse,
    );
  });
}
