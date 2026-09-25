import 'package:flutter_test/flutter_test.dart';
import 'package:protrading_ai/data/models/trading_models.dart';
import 'package:protrading_ai/features/trading_room/bloc/trading_room_bloc.dart';
import 'package:protrading_ai/features/trading_room/bloc/trading_room_state.dart';

void main() {
  test('symbol change resets chart state without cross-symbol P&L bleed', () {
    const xau = Position(
      id: 'xau-1',
      symbol: 'XAUUSD',
      type: 'BUY',
      lotSize: 0.1,
      openPrice: 2000,
    );
    const eur = Position(
      id: 'eur-1',
      symbol: 'EURUSD',
      type: 'SELL',
      lotSize: 0.1,
      openPrice: 1.1,
    );
    const signal = TradingSignal(
      symbol: 'XAUUSD',
      entryPrice: 2000,
      slPrice: 1990,
      tpPrices: [2020, 2030, 2040],
      probability: 0,
      type: 'BUY',
      status: 'ACTIVE',
      setupReady: true,
    );
    final current = TradingRoomLoaded(
      account: const TradingAccount(
        balance: 1000,
        equity: 1000,
        margin: 0,
        leverage: 100,
        status: 'DEMO',
      ),
      currentSignal: signal,
      currentSymbol: 'XAUUSD',
      candles: [
        Candle(
          timestamp: DateTime.fromMillisecondsSinceEpoch(1700000000 * 1000),
          open: 1,
          high: 1,
          low: 1,
          close: 1,
        ),
      ],
      positions: [xau, eur],
      symbolPrices: {'XAUUSD': 2010, 'EURUSD': 1.095},
      panelResetNonce: 4,
      selectedTakeProfitIndex: 0,
    );

    final next = stateAfterSymbolChange(current, 'EURUSD');

    expect(next.currentSymbol, 'EURUSD');
    expect(next.currentSignal, isNull);
    expect(next.candles, isEmpty);
    expect(next.panelResetNonce, 5);
    expect(next.selectedTakeProfitIndex, 2);
    expect(next.positions, hasLength(2));
    expect(next.positions[0].currentPrice, 2010);
    expect(next.positions[1].currentPrice, 1.095);
    expect(next.positions[0].profit, isNot(next.positions[1].profit));
  });
}
