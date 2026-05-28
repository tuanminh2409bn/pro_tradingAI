import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/referral_models.dart';

class ReferralRepository {
  final FirebaseFirestore _firestore;

  ReferralRepository({FirebaseFirestore? firestore})
      : _firestore = firestore ?? FirebaseFirestore.instance;

  /// Stream thống kê referral — tự tạo document nếu chưa tồn tại.
  Stream<ReferralStats> getReferralStats(String userId) {
    return _firestore
        .collection('referrals')
        .doc(userId)
        .snapshots()
        .asyncMap((snapshot) async {
      if (!snapshot.exists || snapshot.data() == null) {
        // Tự tạo referral document cho user mới
        final newStats = {
          'totalEarnings': 0.0,
          'f1Count': 0,
          'f2Count': 0,
          'referralLink': 'protrading.ai/ref/${userId.substring(0, 8)}',
          'createdAt': FieldValue.serverTimestamp(),
        };
        await _firestore.collection('referrals').doc(userId).set(newStats);
        return ReferralStats(
          totalEarnings: 0.0,
          f1Count: 0,
          f2Count: 0,
          referralLink: 'protrading.ai/ref/${userId.substring(0, 8)}',
        );
      }
      final data = snapshot.data()!;
      return ReferralStats(
        totalEarnings: (data['totalEarnings'] ?? 0).toDouble(),
        f1Count: (data['f1Count'] ?? 0).toInt(),
        f2Count: (data['f2Count'] ?? 0).toInt(),
        referralLink: data['referralLink'] ?? 'protrading.ai/ref/${userId.substring(0, 8)}',
      );
    });
  }

  /// Stream danh sách thành viên đã giới thiệu.
  Stream<List<MemberNode>> getNetwork(String userId) {
    return _firestore
        .collection('referrals')
        .doc(userId)
        .collection('network')
        .orderBy('earningsContribution', descending: true)
        .snapshots()
        .map((snapshot) {
      return snapshot.docs.map((doc) {
        final data = doc.data();
        return MemberNode(
          id: doc.id,
          name: data['name'] ?? 'Trader',
          avatarUrl: data['avatarUrl'] ?? '',
          earningsContribution: (data['earningsContribution'] ?? 0).toDouble(),
          level: data['level'] ?? 'F1',
        );
      }).toList();
    });
  }

  /// Stream lịch sử giao dịch hoa hồng.
  Stream<List<RewardTransaction>> getRewardHistory(String userId) {
    return _firestore
        .collection('referrals')
        .doc(userId)
        .collection('transactions')
        .orderBy('date', descending: true)
        .limit(50)
        .snapshots()
        .map((snapshot) {
      return snapshot.docs.map((doc) {
        final data = doc.data();
        return RewardTransaction(
          title: data['title'] ?? '',
          date: (data['date'] as Timestamp).toDate(),
          amount: (data['amount'] ?? 0).toDouble(),
          status: data['status'] ?? 'COMPLETED',
          type: data['type'] ?? 'COMMISSION',
        );
      }).toList();
    });
  }

  /// Tạo yêu cầu rút tiền.
  Future<void> requestWithdrawal(String userId, double amount) async {
    await _firestore
        .collection('admin')
        .doc('requests')
        .collection('pending')
        .add({
      'userId': userId,
      'type': 'WITHDRAWAL',
      'amount': '\$${amount.toStringAsFixed(2)}',
      'status': 'PENDING',
      'date': FieldValue.serverTimestamp(),
    });
  }
}
