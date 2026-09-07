import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/admin_models.dart';

class AdminRepository {
  final FirebaseFirestore _firestore;

  AdminRepository({FirebaseFirestore? firestore})
    : _firestore = firestore ?? FirebaseFirestore.instance;

  Stream<SystemStats> getSystemStats() {
    return _firestore.collection('admin').doc('stats').snapshots().map((s) {
      final data = s.data();
      if (data == null)
        return const SystemStats(
          dau: 0,
          mau: 0,
          growth: 0.0,
          latency: 0,
          pendingAlerts: 0,
        );
      return SystemStats(
        dau: (data['dau'] ?? 0).toInt(),
        mau: (data['mau'] ?? 0).toInt(),
        growth: (data['growth'] ?? 0).toDouble(),
        latency: (data['latency'] ?? 0).toInt(),
        pendingAlerts: (data['pendingAlerts'] ?? 0).toInt(),
        totalTrades: (data['totalTrades'] ?? 0).toInt(),
        activeSessions: (data['activeSignals'] ?? 0).toInt(),
        globalPnl: (data['globalPnl'] ?? 0).toDouble(),
      );
    });
  }

  Stream<List<PendingRequest>> getPendingRequests() {
    return _firestore
        .collection('admin')
        .doc('requests')
        .collection('pending')
        .where('status', isEqualTo: 'PENDING')
        .orderBy('date', descending: true)
        .limit(100)
        .snapshots()
        .map(
          (s) => s.docs.map((doc) {
            final data = doc.data();
            return PendingRequest(
              userId: data['userId'] ?? doc.id,
              username: data['username'] ?? '@unknown',
              type: data['type'] ?? 'REQUEST',
              amount: data['amount'] ?? '0',
              date: data['date'] != null
                  ? (data['date'] as Timestamp).toDate()
                  : DateTime.now(),
            );
          }).toList(),
        );
  }

  Future<void> approveRequest(String requestId) async {
    await _firestore
        .collection('admin')
        .doc('requests')
        .collection('pending')
        .doc(requestId)
        .update({
          'status': 'APPROVED',
          'processedAt': FieldValue.serverTimestamp(),
        });
  }

  Future<void> rejectRequest(String requestId) async {
    await _firestore
        .collection('admin')
        .doc('requests')
        .collection('pending')
        .doc(requestId)
        .update({
          'status': 'REJECTED',
          'processedAt': FieldValue.serverTimestamp(),
        });
  }

  Future<void> broadcastSignal(String message, String tier) async {
    await _firestore.collection('broadcasts').add({
      'message': message,
      'tier': tier,
      'createdAt': FieldValue.serverTimestamp(),
    });
  }

  Future<AIConfig?> getAIConfig() async {
    final doc = await _firestore
        .collection('AdminSettings')
        .doc('ai_config')
        .get();
    if (!doc.exists || doc.data() == null) return null;
    return AIConfig.fromMap(doc.data()!);
  }

  Future<void> saveAIConfig(AIConfig config) async {
    await _firestore.collection('AdminSettings').doc('ai_config').set({
      'ai_master_prompt': config.masterPrompt,
      'lastUpdatedBy': config.lastUpdatedBy,
      'lastUpdatedAt': FieldValue.serverTimestamp(),
    });
  }

  // ─── Global Risk Config ───
  Stream<GlobalRiskConfig> getGlobalRisk() {
    return _firestore.collection('admin').doc('global_risk').snapshots().map((
      s,
    ) {
      if (!s.exists || s.data() == null) return const GlobalRiskConfig();
      return GlobalRiskConfig.fromMap(s.data()!);
    });
  }

  Future<void> saveGlobalRisk(GlobalRiskConfig config) async {
    await _firestore
        .collection('admin')
        .doc('global_risk')
        .set(config.toMap(), SetOptions(merge: true));
  }

  // ─── Kill Switch ───
  Future<void> toggleKillSwitch(bool enabled) async {
    await _firestore.collection('admin').doc('system_config').set({
      'tradingEnabled': enabled,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  Stream<bool> getKillSwitchState() {
    return _firestore.collection('admin').doc('system_config').snapshots().map((
      s,
    ) {
      return (s.data()?['tradingEnabled'] ?? true) as bool;
    });
  }

  // ─── Service Status (from Firestore — backend ghi mỗi 60s) ───
  Stream<List<ServiceStatus>> getServiceStatus() {
    return _firestore.collection('admin').doc('service_status').snapshots().map(
      (s) {
        final data = s.data();
        if (data == null) return _defaultServiceStatus();
        final backend = (data['redis_backend'] ?? 'unknown').toString();
        return [
          ServiceStatus(
            name: 'MT4 Bridge',
            isOnline: data['mt4_online'] ?? false,
            latencyMs: (data['mt4_latency'] ?? 0).toInt(),
          ),
          ServiceStatus(
            name: 'AI Analyzer',
            isOnline: data['ai_online'] ?? false,
            latencyMs: (data['ai_latency'] ?? 0).toInt(),
          ),
          ServiceStatus(
            name: 'Data Feeder',
            isOnline: data['data_online'] ?? false,
            latencyMs: (data['data_latency'] ?? 0).toInt(),
          ),
          ServiceStatus(
            name: 'Analysis Cache ($backend)',
            isOnline: data['redis_online'] ?? false,
            latencyMs: (data['redis_latency'] ?? 0).toInt(),
          ),
        ];
      },
    );
  }

  List<ServiceStatus> _defaultServiceStatus() => const [
    ServiceStatus(name: 'MT4 Bridge', isOnline: false, latencyMs: 0),
    ServiceStatus(name: 'AI Analyzer', isOnline: false, latencyMs: 0),
    ServiceStatus(name: 'Data Feeder', isOnline: false, latencyMs: 0),
    ServiceStatus(name: 'Analysis Cache', isOnline: false, latencyMs: 0),
  ];

  // ─── Radar Config ───
  Future<void> saveRadarConfig(List<String> symbols, double sensitivity) async {
    await _firestore.collection('admin').doc('radar_config').set({
      'watchlist': symbols,
      'sensitivity': sensitivity,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  // ─── Daily Stats for Analytics Chart (7 ngày) ───
  Future<List<Map<String, dynamic>>> getDailyStats(int days) async {
    final results = <Map<String, dynamic>>[];
    final now = DateTime.now();
    for (int i = days - 1; i >= 0; i--) {
      final date = now.subtract(Duration(days: i));
      final key =
          '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
      results.add({'date': key, 'dau': 0, 'mau': 0});
    }
    try {
      final snap = await _firestore
          .collection('admin')
          .doc('daily_stats')
          .collection('days')
          .orderBy(FieldPath.documentId, descending: true)
          .limit(days)
          .get();
      for (final doc in snap.docs) {
        final idx = results.indexWhere((r) => r['date'] == doc.id);
        if (idx >= 0) {
          results[idx]['dau'] = (doc.data()['dau'] ?? 0).toInt();
          results[idx]['mau'] = (doc.data()['mau'] ?? 0).toInt();
        }
      }
    } catch (_) {}
    return results;
  }
}
