import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/radar_models.dart';

class RadarRepository {
  final FirebaseFirestore _firestore;

  RadarRepository({FirebaseFirestore? firestore})
      : _firestore = firestore ?? FirebaseFirestore.instance;

  Stream<List<RadarAsset>> getRadarAssets() {
    return _firestore
        .collection('radar')
        .snapshots()
        .map((snapshot) {
      if (snapshot.docs.isEmpty) {
        // Mock data for initial state
        return [
          const RadarAsset(symbol: 'BTCUSD', fullName: 'Bitcoin / USD', price: 64210.50, changePercent: 4.28, volatilityStatus: 'HIGH', hasAiConfirmation: true, aiSignal: 'BUY', sparklineData: [0, 5, 2, 8, 5, 10]),
          const RadarAsset(symbol: 'XAUUSD', fullName: 'Gold / USD', price: 2042.12, changePercent: 0.12, volatilityStatus: 'STABLE', hasAiConfirmation: false, aiSignal: 'NEUTRAL', sparklineData: [5, 6, 5, 7, 5, 4]),
          const RadarAsset(symbol: 'ETHUSD', fullName: 'Ethereum / USD', price: 3456.88, changePercent: -2.45, volatilityStatus: 'HIGH', hasAiConfirmation: true, aiSignal: 'SELL', sparklineData: [10, 8, 9, 4, 6, 2]),
        ];
      }
      return snapshot.docs.map((doc) {
        final data = doc.data();
        return RadarAsset(
          symbol: data['symbol'] ?? '',
          fullName: data['fullName'] ?? '',
          price: (data['price'] ?? 0).toDouble(),
          changePercent: (data['changePercent'] ?? 0).toDouble(),
          volatilityStatus: data['volatilityStatus'] ?? 'STABLE',
          hasAiConfirmation: data['hasAiConfirmation'] ?? false,
          aiSignal: data['aiSignal'] ?? 'NEUTRAL',
          sparklineData: List<double>.from(data['sparklineData'] ?? []),
        );
      }).toList();
    });
  }

  Future<void> toggleAlert(String symbol, bool enabled) async {
    // Logic to manage user alerts for specific symbols
  }
}
