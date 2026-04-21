import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/admin_models.dart';

class AdminRepository {
  final FirebaseFirestore _firestore;

  AdminRepository({FirebaseFirestore? firestore})
      : _firestore = firestore ?? FirebaseFirestore.instance;

  Stream<SystemStats> getSystemStats() {
    return _firestore
        .collection('admin')
        .doc('stats')
        .snapshots()
        .map((snapshot) {
      final data = snapshot.data();
      if (data == null) {
        return const SystemStats(dau: 1402, mau: 42000, growth: 12.4, latency: 24, pendingAlerts: 14);
      }
      return SystemStats(
        dau: (data['dau'] ?? 0).toInt(),
        mau: (data['mau'] ?? 0).toInt(),
        growth: (data['growth'] ?? 0).toDouble(),
        latency: (data['latency'] ?? 0).toInt(),
        pendingAlerts: (data['pendingAlerts'] ?? 0).toInt(),
      );
    });
  }

  Stream<List<PendingRequest>> getPendingRequests() {
    return _firestore
        .collection('admin')
        .doc('requests')
        .collection('pending')
        .orderBy('date', descending: true)
        .snapshots()
        .map((snapshot) {
      if (snapshot.docs.isEmpty) {
        return [
          PendingRequest(userId: '1', username: '@alex_trader', type: 'WITHDRAWAL', amount: '\$12,400.00', date: DateTime.now()),
          PendingRequest(userId: '2', username: '@zen_master', type: 'REWARD GRANT', amount: '2,500 KNT', date: DateTime.now()),
          PendingRequest(userId: '3', username: '@whale_99', type: 'WITHDRAWAL', amount: '\$154,200.00', date: DateTime.now()),
        ];
      }
      return snapshot.docs.map((doc) {
        final data = doc.data();
        return PendingRequest(
          userId: doc.id,
          username: data['username'] ?? '',
          type: data['type'] ?? '',
          amount: data['amount'] ?? '',
          date: (data['date'] as Timestamp).toDate(),
        );
      }).toList();
    });
  }

  Future<void> approveRequest(String requestId) async {
    // Approval logic
  }

  Future<void> rejectRequest(String requestId) async {
    // Rejection logic
  }

  Future<void> broadcastSignal(String message, String tier) async {
    // Logic to send global notifications
  }
}
