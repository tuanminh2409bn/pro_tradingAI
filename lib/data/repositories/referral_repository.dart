import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;
import '../../core/constants/backend_endpoints.dart';
import '../models/referral_models.dart';
import '../models/referral_wallet.dart';

class ReferralRegistrationException implements Exception {
  final int statusCode;
  const ReferralRegistrationException(this.statusCode);
}

class ReferralWithdrawalException implements Exception {
  final int statusCode;
  const ReferralWithdrawalException(this.statusCode);
}

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

  Future<ReferralRegistrationStatus> recordRegistrationReferral(
    String code,
  ) async {
    ReferralIdentity.fromServerLink(
      code: code,
      link: Uri.https('protrading-ai-2026.web.app', '/', {
        'ref': code,
      }).toString(),
    );
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
          Uri.parse('${BackendEndpoints.apiBaseUrl}/api/referral/registration'),
          headers: {
            'Authorization': 'Bearer $token',
            'Content-Type': 'application/json',
          },
          body: jsonEncode({'code': code}),
        )
        .timeout(const Duration(seconds: 15));
    if (_auth.currentUser?.uid != user.uid) {
      throw StateError('Identity changed');
    }
    if (response.statusCode != 200) {
      throw ReferralRegistrationException(response.statusCode);
    }
    final data = jsonDecode(response.body);
    if (data is! Map<String, dynamic>) {
      throw const FormatException('Invalid registration status');
    }
    return switch (data['status']) {
      'recorded' => ReferralRegistrationStatus.recorded,
      'restored' => ReferralRegistrationStatus.restored,
      'not_eligible' => ReferralRegistrationStatus.notEligible,
      _ => throw const FormatException('Invalid registration status'),
    };
  }

  /// Stream referral stats provisioned by the authoritative backend.
  Stream<ReferralWallet?> getWallet(String userId) {
    return _firestore
        .collection('users')
        .doc(userId)
        .collection('meta')
        .doc('referral_wallet')
        .snapshots()
        .map((snapshot) {
          if (_auth.currentUser?.uid != userId || !snapshot.exists) return null;
          return ReferralWallet.fromServer(snapshot.data() ?? const {});
        });
  }

  Future<String> requestWithdrawal({
    required String requestId,
    required int amountMinor,
  }) async {
    final user = _auth.currentUser;
    final token = await user?.getIdToken();
    if (user == null ||
        token == null ||
        token.isEmpty ||
        _auth.currentUser?.uid != user.uid) {
      throw StateError('Authentication required');
    }
    final response = await _client
        .post(
          Uri.parse('${BackendEndpoints.apiBaseUrl}/api/referral/withdrawals'),
          headers: {
            'Authorization': 'Bearer $token',
            'Content-Type': 'application/json',
          },
          body: jsonEncode({
            'requestId': requestId,
            'amountMinor': amountMinor,
          }),
        )
        .timeout(const Duration(seconds: 25));
    if (_auth.currentUser?.uid != user.uid) {
      throw StateError('Identity changed');
    }
    if (response.statusCode != 200) {
      throw ReferralWithdrawalException(response.statusCode);
    }
    final data = jsonDecode(response.body);
    if (data is! Map<String, dynamic> ||
        data['requestId'] is! String ||
        !RegExp(r'^[a-f0-9]{64}$').hasMatch(data['requestId']) ||
        !{'PENDING', 'APPROVED', 'REJECTED', 'PAID'}.contains(data['status'])) {
      throw const FormatException('Invalid withdrawal response');
    }
    return data['status'] as String;
  }

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

  Stream<List<ReferralWithdrawal>> getWithdrawals(String userId) async* {
    if (_auth.currentUser?.uid != userId) {
      throw StateError('Account access denied');
    }
    yield* _firestore
        .collection('users')
        .doc(userId)
        .collection('referral_withdrawals')
        .orderBy('createdAt', descending: true)
        .limit(30)
        .snapshots()
        .map(
          (snapshot) => snapshot.docs
              .map((doc) {
                final data = doc.data();
                final date = data['createdAt'];
                return ReferralWithdrawal.fromServer(
                  doc.id,
                  data,
                  date is Timestamp ? date.toDate() : null,
                );
              })
              .whereType<ReferralWithdrawal>()
              .toList(),
        );
  }

  /// Canonical immutable ledger, never unverified legacy transaction amounts.
  Stream<List<RewardTransaction>> getRewardHistory(String userId) async* {
    if (_auth.currentUser?.uid != userId) {
      throw StateError('Account access denied');
    }
    yield* _firestore
        .collection('users')
        .doc(userId)
        .collection('referral_ledger')
        .orderBy('createdAt', descending: true)
        .limit(50)
        .snapshots()
        .map((snapshot) {
          return snapshot.docs
              .map((doc) {
                final data = doc.data();
                final date = data['createdAt'];
                return RewardTransaction.fromLedger(
                  data,
                  date is Timestamp ? date.toDate() : null,
                );
              })
              .whereType<RewardTransaction>()
              .toList();
        });
  }
}
