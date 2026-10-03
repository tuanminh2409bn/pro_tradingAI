import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;
import '../../core/constants/backend_endpoints.dart';
import '../models/referral_models.dart';

class ReferralRepository {
  final FirebaseFirestore _firestore;
  final FirebaseAuth _auth;
  final http.Client _client;

  ReferralRepository({
    FirebaseFirestore? firestore,
    FirebaseAuth? auth,
    http.Client? client,
  }) : _firestore = firestore ?? FirebaseFirestore.instance,
       _auth = auth ?? FirebaseAuth.instance,
       _client = client ?? http.Client();

  Future<ReferralIdentity> provisionIdentity() async {
    final user = _auth.currentUser;
    final token = await user?.getIdToken();
    if (user == null ||
        token == null ||
        token.isEmpty ||
        _auth.currentUser?.uid != user.uid) {
      throw StateError('Authentication is required');
    }
    final response = await _client
        .post(
          Uri.parse('${BackendEndpoints.apiBaseUrl}/api/referral/identity'),
          headers: {'Authorization': 'Bearer $token'},
        )
        .timeout(const Duration(seconds: 15));
    if (_auth.currentUser?.uid != user.uid) {
      throw StateError('Identity changed');
    }
    if (response.statusCode != 200) {
      throw StateError('Referral identity unavailable');
    }
    final data = jsonDecode(response.body);
    if (data is! Map<String, dynamic> ||
        data['code'] is! String ||
        data['link'] is! String) {
      throw const FormatException('Invalid referral identity');
    }
    return ReferralIdentity.fromServerLink(
      code: data['code'] as String,
      link: data['link'] as String,
    );
  }

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
      return ReferralStats.fromJson(data);
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
