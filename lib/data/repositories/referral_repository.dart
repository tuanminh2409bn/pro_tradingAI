import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/referral_models.dart';

class ReferralRepository {
  final FirebaseFirestore _firestore;

  ReferralRepository({FirebaseFirestore? firestore})
    : _firestore = firestore ?? FirebaseFirestore.instance;

  /// Stream referral stats provisioned by the authoritative backend.
  /// Missing data stays unavailable; the client must not derive a code from UID.
  Stream<ReferralStats> getReferralStats(String userId) {
    return _firestore.collection('referrals').doc(userId).snapshots().map((
      snapshot,
    ) {
      if (!snapshot.exists || snapshot.data() == null) {
        return const ReferralStats.unavailable();
      }
      final data = snapshot.data()!;
      return ReferralStats(
        totalEarnings: (data['totalEarnings'] ?? 0).toDouble(),
        f1Count: (data['f1Count'] ?? 0).toInt(),
        f2Count: (data['f2Count'] ?? 0).toInt(),
        referralLink: data['referralLink'] is String
            ? (data['referralLink'] as String).trim()
            : '',
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
              earningsContribution: (data['earningsContribution'] ?? 0)
                  .toDouble(),
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
          return snapshot.docs
              .map((doc) {
                final data = doc.data();
                final date = data['date'];
                final amount = data['amount'];
                if (date is! Timestamp || amount is! num) return null;
                return RewardTransaction(
                  title: (data['title'] ?? '').toString(),
                  date: date.toDate(),
                  amount: amount.toDouble(),
                  status: (data['status'] ?? 'UNKNOWN').toString(),
                  type: (data['type'] ?? 'UNKNOWN').toString(),
                );
              })
              .whereType<RewardTransaction>()
              .toList();
        });
  }
}
