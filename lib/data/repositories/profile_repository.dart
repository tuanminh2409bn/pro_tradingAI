import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/profile_models.dart';

class ProfileRepository {
  final FirebaseFirestore _firestore;

  ProfileRepository({FirebaseFirestore? firestore})
      : _firestore = firestore ?? FirebaseFirestore.instance;

  Stream<UserProfile> getUserProfile(String userId) {
    return _firestore
        .collection('users')
        .doc(userId)
        .snapshots()
        .map((snapshot) {
      final data = snapshot.data();
      if (data == null) {
        return const UserProfile(
          username: 'alex.vanguard_42',
          email: 'premium.trader@kinetic.io',
          tier: 'ENTERPRISE',
          totalTrades: 1240,
          winRate: 64.2,
          rank: 12,
          avatarUrl: '',
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
        return const AccessQuota(
          apiUsed: 8420, apiLimit: 10000,
          backtestUsed: 12, backtestLimit: 50,
          storageUsed: 4.2, storageLimit: 20,
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

  Future<void> updateUsername(String userId, String newName) async {
    await _firestore.collection('users').doc(userId).update({'username': newName});
  }

  Future<void> toggle2FA(String userId, bool enabled) async {
    // Logic to manage 2FA settings
  }
}
