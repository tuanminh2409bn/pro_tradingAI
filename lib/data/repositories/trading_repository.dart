import 'dart:async';
import 'dart:math' as math;
import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/trading_models.dart';

class TradingRepository {
  final FirebaseFirestore _firestore;

  TradingRepository({FirebaseFirestore? firestore})
      : _firestore = firestore ?? FirebaseFirestore.instance;

  Stream<TradingAccount> getTradingAccount(String userId) {
    return _firestore
        .collection('accounts')
        .doc(userId)
        .snapshots()
        .map((snapshot) {
      final data = snapshot.data();
      if (data == null) {
        return const TradingAccount(
          balance: 38204.12,
          equity: 42050.00,
          margin: 840,
          leverage: 500,
          status: 'LIVE',
        );
      }
      return TradingAccount(
        balance: (data['balance'] ?? 0).toDouble(),
        equity: (data['equity'] ?? 0).toDouble(),
        margin: (data['margin'] ?? 0).toDouble(),
        leverage: (data['leverage'] ?? 0).toInt(),
        status: data['status'] ?? 'DEMO',
      );
    });
  }

  Stream<List<TradingSignal>> getActiveSignals() {
    return _firestore
        .collection('signals')
        .where('status', isEqualTo: 'ACTIVE')
        .snapshots()
        .map((snapshot) {
      if (snapshot.docs.isEmpty) {
        // Return mock signal if empty for demo
        return [
          const TradingSignal(
            symbol: 'XAUUSD',
            entryPrice: 2038.50,
            slPrice: 2032.10,
            tpPrices: [2055.00],
            probability: 85,
            type: 'BUY',
            status: 'ACTIVE',
          )
        ];
      }
      return snapshot.docs.map((doc) {
        final data = doc.data();
        return TradingSignal(
          symbol: data['symbol'] ?? '',
          entryPrice: (data['entryPrice'] ?? 0).toDouble(),
          slPrice: (data['slPrice'] ?? 0).toDouble(),
          tpPrices: List<double>.from(data['tpPrices'] ?? []),
          probability: (data['probability'] ?? 0).toInt(),
          type: data['type'] ?? 'BUY',
          status: data['status'] ?? 'ACTIVE',
        );
      }).toList();
    });
  }

  // Simulated Real-time Candle Stream
  Stream<List<Candle>> getCandleStream(String symbol) async* {
    List<Candle> candles = [];
    double lastClose = 2040.0;
    
    // Initial 50 candles
    for (int i = 50; i >= 0; i--) {
      final candle = _generateNextCandle(
        symbol, 
        lastClose, 
        DateTime.now().subtract(Duration(minutes: i * 5)),
      );
      candles.add(candle);
      lastClose = candle.close;
    }

    yield List.from(candles);

    // Update every 5 seconds
    while (true) {
      await Future.delayed(const Duration(seconds: 5));
      final nextCandle = _generateNextCandle(symbol, lastClose, DateTime.now());
      candles.removeAt(0);
      candles.add(nextCandle);
      lastClose = nextCandle.close;
      yield List.from(candles);
    }
  }

  Candle _generateNextCandle(String symbol, double lastClose, DateTime time) {
    final rand = math.Random();
    double change = (rand.nextDouble() - 0.5) * 5.0;
    double open = lastClose;
    double close = open + change;
    double high = math.max(open, close) + rand.nextDouble() * 2.0;
    double low = math.min(open, close) - rand.nextDouble() * 2.0;

    return Candle(
      timestamp: time,
      open: open,
      high: high,
      low: low,
      close: close,
    );
  }
}
