import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import '../../core/constants/backend_endpoints.dart';
import '../models/profile_models.dart';

bool brokerLinkRequestAccepted(int statusCode, String responseBody) {
  if (statusCode != 200) return false;
  try {
    final payload = jsonDecode(responseBody);
    return payload is Map<String, dynamic> &&
        payload['status'] == 'success' &&
        payload['accountId'] is String &&
        (payload['accountId'] as String).trim().isNotEmpty;
  } on FormatException {
    return false;
  }
}

class ProfileRepository {
  final FirebaseFirestore _firestore;
  final FirebaseAuth _auth;
  static const String _apiUrl =
      '${BackendEndpoints.apiBaseUrl}/api/account/link';

  ProfileRepository({FirebaseFirestore? firestore, FirebaseAuth? auth})
    : _firestore = firestore ?? FirebaseFirestore.instance,
      _auth = auth ?? FirebaseAuth.instance;

  /// Tự tạo profile document cho user mới nếu chưa tồn tại.
  /// Gọi ngay sau khi đăng nhập thành công.
  Future<void> ensureProfileExists(String userId) async {
    final docRef = _firestore.collection('users').doc(userId);
    final doc = await docRef.get();
    if (doc.exists) {
      // Cập nhật lastSeen để tính DAU
      await docRef.update({'lastSeen': FieldValue.serverTimestamp()});
      return;
    }
    // Lấy thông tin từ Firebase Auth
    final user = _auth.currentUser;
    final email = user?.email ?? '';
    final displayName = user?.displayName ?? '';
    final username = displayName.isNotEmpty
        ? displayName.toLowerCase().replaceAll(' ', '_')
        : email.split('@').first;

    await docRef.set({
      'username': username,
      'email': email,
      'displayName': displayName,
      'tier': 'FREE',
      'totalTrades': 0,
      'winRate': 0.0,
      'rank': 0,
      'avatarUrl': user?.photoURL ?? '',
      'brokerLinked': false,
      'syncGateDismissed': false,
      'manualRiskMode': false,
      'createdAt': FieldValue.serverTimestamp(),
      'lastSeen': FieldValue.serverTimestamp(),
    });
  }

  /// Day 5 Sync Gate flags on `users/{uid}`.
  Future<({bool brokerLinked, bool syncGateDismissed, bool manualRiskMode})>
  getSyncGateState(String userId) async {
    try {
      final doc = await _firestore.collection('users').doc(userId).get();
      final data = doc.data() ?? {};
      return (
        brokerLinked: data['brokerLinked'] == true,
        syncGateDismissed: data['syncGateDismissed'] == true,
        manualRiskMode: data['manualRiskMode'] == true,
      );
    } catch (_) {
      return (
        brokerLinked: false,
        syncGateDismissed: false,
        manualRiskMode: false,
      );
    }
  }

  Future<void> dismissSyncGate(String userId, {bool manualMode = true}) async {
    await _firestore.collection('users').doc(userId).set({
      'syncGateDismissed': true,
      'manualRiskMode': manualMode,
    }, SetOptions(merge: true));
  }

  /// Stream profile — đọc thẳng từ Firestore thật.
  Stream<UserProfile> getUserProfile(String userId) {
    return _firestore.collection('users').doc(userId).snapshots().map((
      snapshot,
    ) {
      final data = snapshot.data();
      if (data == null) {
        // Profile chưa được seed — trả về profile trống (không mock)
        final user = _auth.currentUser;
        return UserProfile(
          username: user?.email?.split('@').first ?? 'trader',
          email: user?.email ?? '',
          tier: 'FREE',
          totalTrades: 0,
          winRate: 0.0,
          rank: 0,
          avatarUrl: user?.photoURL ?? '',
        );
      }
      return UserProfile(
        username: data['username'] ?? '',
        email: data['email'] ?? '',
        tier: data['tier'] ?? 'FREE',
        totalTrades: (data['totalTrades'] ?? 0).toInt(),
        winRate: (data['winRate'] ?? 0).toDouble(),
        rank: (data['rank'] ?? 0).toInt(),
        avatarUrl: data['avatarUrl'] ?? '',
      );
    });
  }

  /// Stream broker accounts.
  Stream<List<BrokerAccount>> getBrokerAccounts(String userId) {
    return _firestore
        .collection('users')
        .doc(userId)
        .collection('broker_accounts')
        .snapshots()
        .map((snapshot) {
          return snapshot.docs.map((doc) {
            final data = doc.data();
            return BrokerAccount(
              accountId: doc.id,
              platform: data['platform'] ?? 'mt4',
              server: data['server'] ?? '',
              login: data['login'] ?? '',
              status: data['status'] ?? 'DISCONNECTED',
            );
          }).toList();
        });
  }

  /// Stream access quota.
  Stream<AccessQuota> getAccessQuota(String userId) {
    return _firestore
        .collection('users')
        .doc(userId)
        .collection('meta')
        .doc('quota')
        .snapshots()
        .map((snapshot) {
          final data = snapshot.data();
          if (data == null) {
            return const AccessQuota.unavailable();
          }
          final resetAt = data['resetAt'];
          return AccessQuota(
            apiUsed: (data['apiUsed'] ?? 0).toInt(),
            apiLimit: (data['apiLimit'] ?? 0).toInt(),
            backtestUsed: (data['backtestUsed'] ?? 0).toInt(),
            backtestLimit: (data['backtestLimit'] ?? 0).toInt(),
            storageUsed: (data['storageUsed'] ?? 0).toDouble(),
            storageLimit: (data['storageLimit'] ?? 0).toDouble(),
            source: data['source'] is String ? data['source'] as String : null,
            resetAt: resetAt is Timestamp ? resetAt.toDate().toUtc() : null,
          );
        });
  }

  /// Liên kết tài khoản broker MT4/MT5.
  Future<bool> linkBrokerAccount({
    required String userId,
    required String platform,
    required String server,
    required String login,
    required String password,
  }) async {
    try {
      final user = _auth.currentUser;
      final token = await user?.getIdToken();
      if (user == null ||
          user.uid != userId ||
          token == null ||
          token.isEmpty) {
        return false;
      }
      final response = await http.post(
        Uri.parse(_apiUrl),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
        body: jsonEncode({
          'userId': userId,
          'platform': platform,
          'server': server,
          'login': login,
          'password': password,
        }),
      );
      // Account creation is pending provider connection, not a linked account.
      return brokerLinkRequestAccepted(response.statusCode, response.body);
    } catch (e) {
      return false;
    }
  }

  Future<void> updateUsername(String userId, String newName) async {
    await _firestore.collection('users').doc(userId).update({
      'username': newName,
    });
  }

  Future<void> toggle2FA(String userId, bool enabled) async {
    await _firestore.collection('users').doc(userId).update({'2fa': enabled});
  }

  Future<void> savePreferences(
    String userId, {
    bool? pushNotifications,
    bool? dataSharing,
  }) async {
    final Map<String, dynamic> data = {};
    if (pushNotifications != null) {
      data['pushNotificationsEnabled'] = pushNotifications;
    }
    if (dataSharing != null) data['dataSharingEnabled'] = dataSharing;
    if (data.isNotEmpty) {
      await _firestore
          .collection('users')
          .doc(userId)
          .set(data, SetOptions(merge: true));
    }
  }

  /// Đọc preferences từ Firestore khi load profile
  Future<Map<String, bool>> getPreferences(String userId) async {
    try {
      final doc = await _firestore.collection('users').doc(userId).get();
      final data = doc.data();
      return {
        'pushNotifications':
            (data?['pushNotificationsEnabled'] ?? false) as bool,
        'dataSharing': (data?['dataSharingEnabled'] ?? false) as bool,
        '2fa': (data?['2fa'] ?? false) as bool,
      };
    } catch (_) {
      return {'pushNotifications': false, 'dataSharing': false, '2fa': false};
    }
  }
}
