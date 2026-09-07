import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import '../models/profile_models.dart';

class ProfileRepository {
  final FirebaseFirestore _firestore;
  final FirebaseAuth _auth;
  static const String _apiUrl =
      'https://103-69-189-243.sslip.io/api/account/link';

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

  Future<void> markBrokerLinked(String userId, {bool linked = true}) async {
    await _firestore.collection('users').doc(userId).set({
      'brokerLinked': linked,
      if (linked) 'syncGateDismissed': true,
      if (linked) 'manualRiskMode': false,
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
            // Quota mặc định cho user FREE (số thật, không phải 8420/10000 fake)
            return const AccessQuota(
              apiUsed: 0,
              apiLimit: 1000,
              backtestUsed: 0,
              backtestLimit: 10,
              storageUsed: 0.0,
              storageLimit: 1.0,
            );
          }
          return AccessQuota(
            apiUsed: (data['apiUsed'] ?? 0).toInt(),
            apiLimit: (data['apiLimit'] ?? 1000).toInt(),
            backtestUsed: (data['backtestUsed'] ?? 0).toInt(),
            backtestLimit: (data['backtestLimit'] ?? 10).toInt(),
            storageUsed: (data['storageUsed'] ?? 0).toDouble(),
            storageLimit: (data['storageLimit'] ?? 1).toDouble(),
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
      final response = await http.post(
        Uri.parse(_apiUrl),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'userId': userId,
          'platform': platform,
          'server': server,
          'login': login,
          'password': password,
        }),
      );
      if (response.statusCode == 200) {
        await markBrokerLinked(userId, linked: true);
        return true;
      }
      return false;
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
    if (pushNotifications != null)
      data['pushNotificationsEnabled'] = pushNotifications;
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
            (data?['pushNotificationsEnabled'] ?? true) as bool,
        'dataSharing': (data?['dataSharingEnabled'] ?? true) as bool,
        '2fa': (data?['2fa'] ?? false) as bool,
      };
    } catch (_) {
      return {'pushNotifications': true, 'dataSharing': true, '2fa': false};
    }
  }
}
