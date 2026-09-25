import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;
import '../../core/constants/backend_endpoints.dart';
import '../models/community_models.dart';

class CommunityRepository {
  static const String _serverBaseUrl = BackendEndpoints.apiBaseUrl;
  final FirebaseFirestore _firestore;
  final FirebaseAuth _auth;

  CommunityRepository({FirebaseFirestore? firestore, FirebaseAuth? auth})
    : _firestore = firestore ?? FirebaseFirestore.instance,
      _auth = auth ?? FirebaseAuth.instance;

  /// Stream bài viết cộng đồng — dữ liệu thật từ Firestore.
  /// Nếu chưa có bài viết nào → trả về list rỗng, UI sẽ hiển thị empty state.
  Stream<List<CommunityPost>> getCommunityFeed() {
    return _firestore
        .collection('community')
        .orderBy('timestamp', descending: true)
        .limit(50)
        .snapshots()
        .map((snapshot) {
          return snapshot.docs.map((doc) {
            final data = doc.data();
            return CommunityPost(
              id: doc.id,
              ownerId: data['userId'] as String?,
              userName: data['userName'] ?? 'Community member',
              avatarUrl: data['avatarUrl'] ?? '',
              timeAgo: _formatTimeAgo(data['timestamp']),
              content: data['content'] ?? '',
              tradeInfo: data['tradeInfo'] ?? '',
              profit: (data['profit'] ?? 0).toDouble(),
              isProfit: data['isProfit'] ?? true,
              chartImageUrl: data['chartImageUrl'],
              likes: (data['likes'] ?? 0).toInt(),
              comments: (data['comments'] ?? 0).toInt(),
              isVerified: data['isVerified'] ?? false,
              tradeVerified: data['tradeVerified'] == true,
              verificationReference: data['verificationReference'] as String?,
            );
          }).toList();
        });
  }

  /// Stream bảng xếp hạng — dữ liệu thật từ Firestore.
  Stream<List<LeaderboardEntry>> getLeaderboard() {
    return _firestore
        .collection('leaderboard')
        .orderBy('performance', descending: true)
        .limit(20)
        .snapshots()
        .map((snapshot) {
          return snapshot.docs.asMap().entries.map((entry) {
            final data = entry.value.data();
            return LeaderboardEntry(
              rank: entry.key + 1,
              name: data['name'] ?? 'Trader',
              avatarUrl: data['avatarUrl'] ?? '',
              performance: (data['performance'] ?? 0).toDouble(),
              volume: data['volume'] ?? '0',
            );
          }).toList();
        });
  }

  /// Đăng bài viết mới lên community feed.
  Future<void> createPost(String rawContent) async {
    final user = _auth.currentUser;
    if (user == null) {
      throw StateError('Authentication is required');
    }
    final content = normalizeCommunityPostContent(rawContent);
    if (!isValidCommunityPostContent(content)) {
      throw ArgumentError('Community post content is invalid');
    }
    final displayName = user.displayName?.trim();
    final emailName = user.email?.split('@').first.trim();
    await _firestore.collection('community').add({
      'userId': user.uid,
      'userName': displayName?.isNotEmpty == true
          ? displayName
          : (emailName?.isNotEmpty == true ? emailName : 'Community member'),
      'avatarUrl': user.photoURL ?? '',
      'content': content,
      'likes': 0,
      'comments': 0,
      'isVerified': false,
      'tradeVerified': false,
      'timestamp': FieldValue.serverTimestamp(),
    });
  }

  /// The backend owns the like marker and counter transaction.
  Future<void> likePost(String postId) async {
    final token = await _auth.currentUser?.getIdToken();
    if (token == null || token.isEmpty) {
      throw StateError('Authentication is required');
    }
    final response = await http
        .post(
          Uri.parse('$_serverBaseUrl/api/community/like'),
          headers: {
            'Content-Type': 'application/json',
            'Authorization': 'Bearer $token',
          },
          body: jsonEncode({'postId': postId}),
        )
        .timeout(const Duration(seconds: 10));
    if (response.statusCode != 200) {
      throw StateError('Unable to like this post');
    }
    final data = jsonDecode(response.body);
    if (data is! Map<String, dynamic> || data['liked'] != true) {
      throw StateError('Invalid like response');
    }
  }

  /// Chuyển Firestore Timestamp thành chuỗi "X hours ago".
  String _formatTimeAgo(dynamic timestamp) {
    if (timestamp == null) return '__TIME_UNAVAILABLE__';
    try {
      final dt = (timestamp as dynamic).toDate() as DateTime;
      final diff = DateTime.now().difference(dt);
      if (diff.inMinutes < 1) return 'Just now';
      if (diff.inHours < 1) return '${diff.inMinutes}m ago';
      if (diff.inDays < 1) return '${diff.inHours}h ago';
      return '${diff.inDays}d ago';
    } catch (_) {
      return '__TIME_UNAVAILABLE__';
    }
  }
}
