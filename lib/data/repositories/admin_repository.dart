import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;
import '../../core/constants/backend_endpoints.dart';
import '../../core/security/admin_access.dart';
import '../models/admin_models.dart';

class AdminRepository {
  final FirebaseFirestore _firestore;
  final FirebaseAuth _auth;
  final http.Client _client;

  AdminRepository({
    FirebaseFirestore? firestore,
    FirebaseAuth? auth,
    http.Client? client,
  }) : _firestore = firestore ?? FirebaseFirestore.instance,
       _auth = auth ?? FirebaseAuth.instance,
       _client = client ?? http.Client();

  Future<void> _requireAdmin() async {
    final user = _auth.currentUser;
    if (user == null) throw StateError('Admin access denied');
    final token = await user.getIdTokenResult();
    if (!hasVerifiedAdminClaim(token.claims)) {
      throw StateError('Admin access denied');
    }
  }

  Stream<SystemStats> getSystemStats() async* {
    await _requireAdmin();
    yield* _firestore.collection('admin').doc('stats').snapshots().map((s) {
      final data = s.data();
      if (data == null) {
        return const SystemStats(
          dau: 0,
          mau: 0,
          growth: 0.0,
          latency: 0,
          pendingAlerts: 0,
        );
      }
      return SystemStats(
        dau: (data['dau'] ?? 0).toInt(),
        mau: (data['mau'] ?? 0).toInt(),
        growth: (data['growth'] ?? 0).toDouble(),
        latency: (data['latency'] ?? 0).toInt(),
        pendingAlerts: (data['pendingAlerts'] ?? 0).toInt(),
        totalTrades: (data['totalTrades'] ?? 0).toInt(),
        activeSessions: (data['activeSignals'] ?? 0).toInt(),
        globalPnl: (data['globalPnl'] ?? 0).toDouble(),
        isAvailable: true,
      );
    });
  }

  Stream<List<PendingRequest>> getPendingRequests() async* {
    await _requireAdmin();
    yield* _firestore
        .collection('admin')
        .doc('requests')
        .collection('pending')
        .where('status', whereIn: ['PENDING', 'APPROVED'])
        .orderBy('date', descending: true)
        .limit(100)
        .snapshots()
        .map(
          (s) => s.docs
              .where((doc) {
                final data = doc.data();
                return (data['status'] == 'PENDING' ||
                        data['type'] == 'REFERRAL_WITHDRAWAL') &&
                    data['userId'] is String &&
                    (data['userId'] as String).isNotEmpty &&
                    data['date'] is Timestamp &&
                    data['amount'] is String;
              })
              .map((doc) {
                final data = doc.data();
                return PendingRequest(
                  id: doc.id,
                  userId: data['userId'] as String,
                  username: data['username'] is String
                      ? data['username'] as String
                      : data['userId'] as String,
                  type: data['type'] ?? 'REQUEST',
                  status: data['status'] is String
                      ? data['status'] as String
                      : 'PENDING',
                  amount: data['amount'] as String,
                  date: (data['date'] as Timestamp).toDate(),
                );
              })
              .toList(),
        );
  }

  Future<void> approveRequest(String requestId) async {
    await _requireAdmin();
    final request = await _firestore
        .collection('admin')
        .doc('requests')
        .collection('pending')
        .doc(requestId)
        .get();
    if (request.data()?['type'] == 'REFERRAL_WITHDRAWAL') {
      await reviewReferralWithdrawal(requestId: requestId, action: 'approve');
      return;
    }
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
    await _requireAdmin();
    final request = await _firestore
        .collection('admin')
        .doc('requests')
        .collection('pending')
        .doc(requestId)
        .get();
    if (request.data()?['type'] == 'REFERRAL_WITHDRAWAL') {
      await reviewReferralWithdrawal(requestId: requestId, action: 'reject');
      return;
    }
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
    await _requireAdmin();
    await _firestore.collection('broadcasts').add({
      'message': message,
      'tier': tier,
      'createdAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> reviewReferralWithdrawal({
    required String requestId,
    required String action,
    String? paymentReference,
  }) async {
    await _requireAdmin();
    final user = _auth.currentUser;
    final token = await user?.getIdToken();
    if (user == null || token == null || _auth.currentUser?.uid != user.uid) {
      throw StateError('Admin access denied');
    }
    final response = await _client
        .post(
          Uri.parse(
            '${BackendEndpoints.apiBaseUrl}/api/admin/referral/withdrawals/review',
          ),
          headers: {
            'Authorization': 'Bearer $token',
            'Content-Type': 'application/json',
          },
          body: jsonEncode({
            'requestId': requestId,
            'action': action,
            if (paymentReference != null) 'paymentReference': paymentReference,
          }),
        )
        .timeout(const Duration(seconds: 25));
    if (_auth.currentUser?.uid != user.uid || response.statusCode != 200) {
      throw StateError('Withdrawal review unavailable');
    }
    final data = jsonDecode(response.body);
    if (data is! Map<String, dynamic> ||
        data['status'] !=
            {
              'approve': 'APPROVED',
              'reject': 'REJECTED',
              'paid': 'PAID',
            }[action]) {
      throw const FormatException('Invalid withdrawal review');
    }
  }

  Future<String> importReferralReceipt({
    required String receiptId,
    required String payerUid,
    required int netMinor,
    required DateTime settledAt,
  }) async {
    final data = await _referralMutation('receipts', {
      'receiptId': receiptId,
      'payerUid': payerUid,
      'netMinor': netMinor,
      'settledAt': settledAt.toUtc().toIso8601String(),
    });
    final id = data['receiptId'];
    if (id is! String ||
        !RegExp(r'^[a-f0-9]{64}$').hasMatch(id) ||
        !{'recorded', 'restored'}.contains(data['status'])) {
      throw const FormatException('Invalid receipt confirmation');
    }
    return id;
  }

  Future<void> reverseReferralReceipt(String receiptId) async {
    final data = await _referralMutation('reversals', {'receiptId': receiptId});
    if (!{'reversed', 'restored'}.contains(data['status'])) {
      throw const FormatException('Invalid reversal confirmation');
    }
  }

  Future<Map<String, dynamic>> _referralMutation(
    String operation,
    Map<String, Object> body,
  ) async {
    await _requireAdmin();
    final user = _auth.currentUser;
    final token = await user?.getIdToken();
    if (user == null || token == null || _auth.currentUser?.uid != user.uid) {
      throw StateError('Admin access denied');
    }
    final response = await _client
        .post(
          Uri.parse(
            '${BackendEndpoints.apiBaseUrl}/api/admin/referral/$operation',
          ),
          headers: {
            'Authorization': 'Bearer $token',
            'Content-Type': 'application/json',
          },
          body: jsonEncode(body),
        )
        .timeout(const Duration(seconds: 25));
    if (_auth.currentUser?.uid != user.uid || response.statusCode != 200) {
      throw StateError('Referral receipt unavailable');
    }
    final data = jsonDecode(response.body);
    if (data is! Map<String, dynamic>) {
      throw const FormatException('Invalid receipt confirmation');
    }
    return data;
  }

  Future<AIConfig?> getAIConfig() async {
    await _requireAdmin();
    final doc = await _firestore
        .collection('AdminSettings')
        .doc('ai_config')
        .get();
    if (!doc.exists || doc.data() == null) return null;
    return AIConfig.fromMap(doc.data()!);
  }

  Future<void> saveAIConfig(AIConfig config) async {
    await _requireAdmin();
    await _firestore.collection('AdminSettings').doc('ai_config').set({
      'ai_master_prompt': config.masterPrompt,
      'lastUpdatedBy': config.lastUpdatedBy,
      'lastUpdatedAt': FieldValue.serverTimestamp(),
    });
  }

  // ─── Global Risk Config ───
  Stream<GlobalRiskConfig> getGlobalRisk() async* {
    await _requireAdmin();
    yield* _firestore.collection('admin').doc('global_risk').snapshots().map((
      s,
    ) {
      if (!s.exists || s.data() == null) {
        return const GlobalRiskConfig.unavailable();
      }
      return GlobalRiskConfig.fromMap(s.data()!);
    });
  }

  Future<void> saveGlobalRisk(GlobalRiskConfig config) async {
    await _requireAdmin();
    await _firestore
        .collection('admin')
        .doc('global_risk')
        .set(config.toMap(), SetOptions(merge: true));
  }

  // ─── Kill Switch ───
  Future<void> toggleKillSwitch(bool enabled) async {
    await _requireAdmin();
    await _firestore.collection('admin').doc('system_config').set({
      'tradingEnabled': enabled,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  Stream<bool> getKillSwitchState() async* {
    await _requireAdmin();
    yield* _firestore.collection('admin').doc('system_config').snapshots().map((
      s,
    ) {
      return (s.data()?['tradingEnabled'] ?? false) as bool;
    });
  }

  // ─── Service Status (from Firestore — backend ghi mỗi 60s) ───
  Stream<List<ServiceStatus>> getServiceStatus() async* {
    await _requireAdmin();
    yield* _firestore.collection('admin').doc('service_status').snapshots().map(
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
  Future<RadarAdminConfig?> getRadarConfig() async {
    await _requireAdmin();
    final snapshot = await _firestore
        .collection('admin')
        .doc('radar_config')
        .get();
    final data = snapshot.data();
    if (data == null) return null;
    final rawSymbols = data['watchlist'];
    final rawSensitivity = data['sensitivity'];
    if (rawSymbols is! List || rawSensitivity is! num) return null;
    final symbols = rawSymbols
        .whereType<String>()
        .map((symbol) => symbol.trim().toUpperCase())
        .where((symbol) => RegExp(r'^[A-Z0-9._-]{2,20}$').hasMatch(symbol))
        .toSet()
        .toList(growable: false);
    final sensitivity = rawSensitivity.toDouble();
    if (symbols.isEmpty || sensitivity < 0 || sensitivity > 1) return null;
    return RadarAdminConfig(symbols: symbols, sensitivity: sensitivity);
  }

  Future<void> saveRadarConfig(List<String> symbols, double sensitivity) async {
    await _requireAdmin();
    final normalizedSymbols = symbols
        .map((symbol) => symbol.trim().toUpperCase())
        .where((symbol) => RegExp(r'^[A-Z0-9._-]{2,20}$').hasMatch(symbol))
        .toSet()
        .toList(growable: false);
    if (normalizedSymbols.isEmpty || sensitivity < 0 || sensitivity > 1) {
      throw ArgumentError('Invalid radar configuration');
    }
    await _firestore.collection('admin').doc('radar_config').set({
      'watchlist': normalizedSymbols,
      'sensitivity': sensitivity,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  // ─── Daily Stats for Analytics Chart (7 ngày) ───
  Future<List<Map<String, dynamic>>> getDailyStats(int days) async {
    await _requireAdmin();
    final snap = await _firestore
        .collection('admin')
        .doc('daily_stats')
        .collection('days')
        .orderBy(FieldPath.documentId, descending: true)
        .limit(days)
        .get();
    return snap.docs.reversed
        .map(
          (doc) => <String, dynamic>{
            'date': doc.id,
            'dau': (doc.data()['dau'] ?? 0).toInt(),
            'mau': (doc.data()['mau'] ?? 0).toInt(),
          },
        )
        .toList(growable: false);
  }
}
