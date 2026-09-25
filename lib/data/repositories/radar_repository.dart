import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/radar_models.dart';

class RadarRepository {
  final FirebaseFirestore _firestore;

  RadarRepository({FirebaseFirestore? firestore})
    : _firestore = firestore ?? FirebaseFirestore.instance;

  /// Stream dữ liệu Radar từ Firestore — backend cập nhật mỗi 60s.
  Stream<List<RadarAsset>> getRadarAssets() {
    return _firestore.collection('radar').snapshots().map((snapshot) {
      return snapshot.docs.map((doc) {
        final data = doc.data();
        final confirmedAt = data['confirmedAt'];
        return RadarAsset(
          symbol: data['symbol'] ?? doc.id,
          fullName: data['fullName'] ?? '',
          price: (data['price'] ?? 0).toDouble(),
          changePercent: (data['changePercent'] ?? 0).toDouble(),
          volatilityStatus: data['volatilityStatus'] ?? 'STABLE',
          hasAiConfirmation: data['hasAiConfirmation'] ?? false,
          aiSignal: data['aiSignal'] ?? 'NEUTRAL',
          sparklineData: List<double>.from(data['sparklineData'] ?? []),
          confirmationId: data['confirmationId'] as String?,
          rationale: data['rationale'] as String?,
          model: data['model'] as String?,
          provider: data['provider'] as String?,
          licenseRef: data['licenseRef'] as String?,
          timeframe: data['timeframe'] as String?,
          confirmedAt: confirmedAt is Timestamp
              ? confirmedAt.toDate()
              : DateTime.tryParse(confirmedAt?.toString() ?? ''),
        );
      }).toList();
    });
  }

  Future<void> toggleAlert(String symbol, bool enabled) async {
    // Logic to manage user alerts for specific symbols
    await _firestore.collection('radar').doc(symbol).update({
      'alertEnabled': enabled,
    });
  }
}
