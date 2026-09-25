import 'package:flutter_test/flutter_test.dart';
import 'package:protrading_ai/data/models/trading_models.dart';

void main() {
  group('TradingSignal execution safety', () {
    test('missing setup state fails closed', () {
      final signal = TradingSignal.fromMap({
        'symbol': 'XAUUSD',
        'entryPrice': 2400.0,
        'slPrice': 2390.0,
        'tpPrices': [2420.0],
        'probability': 80,
        'type': 'BUY',
        'status': 'ACTIVE',
      });

      expect(signal.setupReady, isFalse);
      expect(signal.canExecute, isFalse);
    });

    test('soft and veto signals cannot execute', () {
      const soft = TradingSignal(
        symbol: 'XAUUSD',
        entryPrice: 2400.0,
        slPrice: 2390.0,
        tpPrices: [2420.0],
        probability: 80,
        type: 'BUY',
        status: 'ACTIVE',
        setupReady: false,
      );
      const vetoed = TradingSignal(
        symbol: 'XAUUSD',
        entryPrice: 2400.0,
        slPrice: 2390.0,
        tpPrices: [2420.0],
        probability: 80,
        type: 'BUY',
        status: 'ACTIVE',
        setupReady: true,
        veto: true,
      );

      expect(soft.canExecute, isFalse);
      expect(vetoed.canExecute, isFalse);
    });

    test('hard signal requires complete executable prices', () {
      const valid = TradingSignal(
        symbol: 'XAUUSD',
        entryPrice: 2400.0,
        slPrice: 2390.0,
        tpPrices: [2420.0, 2430.0, 2440.0],
        probability: 80,
        type: 'BUY',
        status: 'ACTIVE',
        setupReady: true,
        layers: [
          {'layer': 4, 'type': 'execution'},
        ],
      );
      const missingTargets = TradingSignal(
        symbol: 'XAUUSD',
        entryPrice: 2400.0,
        slPrice: 2390.0,
        tpPrices: [],
        probability: 80,
        type: 'BUY',
        status: 'ACTIVE',
        setupReady: true,
      );

      expect(valid.canExecute, isTrue);
      expect(missingTargets.canExecute, isFalse);
    });

    test('hard signal enforces symmetric minimum 1:2 reward to risk', () {
      const lowRewardBuy = TradingSignal(
        symbol: 'XAUUSD',
        entryPrice: 100,
        slPrice: 99,
        tpPrices: [101.99, 103, 104],
        probability: 80,
        type: 'BUY',
        status: 'ACTIVE',
        setupReady: true,
        layers: [
          {'layer': 4, 'type': 'execution'},
        ],
      );
      const validSell = TradingSignal(
        symbol: 'XAUUSD',
        entryPrice: 100,
        slPrice: 101,
        tpPrices: [98, 97, 96],
        probability: 80,
        type: 'SELL',
        status: 'ACTIVE',
        setupReady: true,
        layers: [
          {'layer': 4, 'type': 'execution'},
        ],
      );

      expect(lowRewardBuy.canExecute, isFalse);
      expect(validSell.canExecute, isTrue);
    });
  });
}
