import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/referral_models.dart';

class ReferralRepository {
  final FirebaseFirestore _firestore;

  ReferralRepository({FirebaseFirestore? firestore})
      : _firestore = firestore ?? FirebaseFirestore.instance;

  Stream<ReferralStats> getReferralStats(String userId) {
    return _firestore
        .collection('referrals')
        .doc(userId)
        .snapshots()
        .map((snapshot) {
      final data = snapshot.data();
      if (data == null) {
        return const ReferralStats(
          totalEarnings: 12840.42,
          f1Count: 24,
          f2Count: 118,
          referralLink: 'kinetic.io/ref/trader_4291',
        );
      }
      return ReferralStats(
        totalEarnings: (data['totalEarnings'] ?? 0).toDouble(),
        f1Count: (data['f1Count'] ?? 0).toInt(),
        f2Count: (data['f2Count'] ?? 0).toInt(),
        referralLink: data['referralLink'] ?? '',
      );
    });
  }

  Stream<List<MemberNode>> getNetwork(String userId) {
    return _firestore
        .collection('referrals')
        .doc(userId)
        .collection('network')
        .snapshots()
        .map((snapshot) {
      if (snapshot.docs.isEmpty) {
        return const [
          MemberNode(id: '1', name: 'ELENA_V', avatarUrl: '', earningsContribution: 4200.0, level: 'F1'),
          MemberNode(id: '2', name: 'MARCUS_K', avatarUrl: '', earningsContribution: 2100.0, level: 'F1'),
        ];
      }
      return snapshot.docs.map((doc) {
        final data = doc.data();
        return MemberNode(
          id: doc.id,
          name: data['name'] ?? '',
          avatarUrl: data['avatarUrl'] ?? '',
          earningsContribution: (data['earningsContribution'] ?? 0).toDouble(),
          level: data['level'] ?? 'F1',
        );
      }).toList();
    });
  }

  Stream<List<RewardTransaction>> getRewardHistory(String userId) {
    return _firestore
        .collection('referrals')
        .doc(userId)
        .collection('transactions')
        .orderBy('date', descending: true)
        .snapshots()
        .map((snapshot) {
      if (snapshot.docs.isEmpty) {
        return [
          RewardTransaction(title: 'F1 Trading Commission - Marcus_K', date: DateTime.now().subtract(const Duration(days: 1)), amount: 142.50, status: 'COMPLETED', type: 'COMMISSION'),
          RewardTransaction(title: 'F2 Network Activity Bonus', date: DateTime.now().subtract(const Duration(days: 2)), amount: 840.12, status: 'COMPLETED', type: 'BONUS'),
          RewardTransaction(title: 'Withdrawal to Wallet (...4x91)', date: DateTime.now().subtract(const Duration(days: 4)), amount: -1500.00, status: 'COMPLETED', type: 'WITHDRAWAL'),
        ];
      }
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

  Future<void> requestWithdrawal(String userId, double amount) async {
    // Logic to create a withdrawal request
  }
}
