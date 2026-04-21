import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/journal_models.dart';

class JournalRepository {
  final FirebaseFirestore _firestore;

  JournalRepository({FirebaseFirestore? firestore})
      : _firestore = firestore ?? FirebaseFirestore.instance;

  Stream<List<TradeRecord>> getTradeHistory(String userId) {
    return _firestore
        .collection('users')
        .doc(userId)
        .collection('trades')
        .orderBy('closeTime', descending: true)
        .snapshots()
        .map((snapshot) {
      if (snapshot.docs.isEmpty) {
        // Mock historical trades for demo
        return [
          TradeRecord(
            symbol: 'XAUUSD',
            action: 'LONG',
            lotSize: 2.50,
            entryPrice: 2042.12,
            exitPrice: 2058.45,
            netProfit: 4120.00,
            closeTime: DateTime.now().subtract(const Duration(days: 1)),
            swap: -12.50,
            slippage: 0.2,
          ),
          TradeRecord(
            symbol: 'BTCUSD',
            action: 'SHORT',
            lotSize: 0.15,
            entryPrice: 68421.00,
            exitPrice: 69120.50,
            netProfit: -1054.20,
            closeTime: DateTime.now().subtract(const Duration(days: 2)),
            swap: 0.0,
            slippage: 5.0,
          ),
        ];
      }
      return snapshot.docs.map((doc) {
        final data = doc.data();
        return TradeRecord(
          symbol: data['symbol'] ?? '',
          action: data['action'] ?? 'LONG',
          lotSize: (data['lotSize'] ?? 0).toDouble(),
          entryPrice: (data['entryPrice'] ?? 0).toDouble(),
          exitPrice: (data['exitPrice'] ?? 0).toDouble(),
          netProfit: (data['netProfit'] ?? 0).toDouble(),
          closeTime: (data['closeTime'] as Timestamp).toDate(),
          swap: (data['swap'] ?? 0).toDouble(),
          slippage: (data['slippage'] ?? 0).toDouble(),
        );
      }).toList();
    });
  }

  Stream<JournalStats> getJournalStats(String userId) {
    // In a real app, this would be computed by a Cloud Function or calculated here
    return Stream.value(const JournalStats(
      totalProfit: 14210.42,
      winRate: 64.2,
      profitFactor: 2.18,
      rrRatio: '1:2.45',
      equityData: [10000, 10500, 10200, 11800, 11500, 14210],
    ));
  }
}
