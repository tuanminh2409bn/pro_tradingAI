import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/community_models.dart';

class CommunityRepository {
  final FirebaseFirestore _firestore;

  CommunityRepository({FirebaseFirestore? firestore})
      : _firestore = firestore ?? FirebaseFirestore.instance;

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
          userName: data['userName'] ?? 'Anonymous',
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
  Future<void> createPost(CommunityPost post) async {
    await _firestore.collection('community').add({
      'userName': post.userName,
      'avatarUrl': post.avatarUrl,
      'content': post.content,
      'tradeInfo': post.tradeInfo,
      'profit': post.profit,
      'isProfit': post.isProfit,
      'likes': 0,
      'comments': 0,
      'isVerified': post.isVerified,
      'timestamp': FieldValue.serverTimestamp(),
    });
  }

  /// Like một bài viết.
  Future<void> likePost(String postId) async {
    await _firestore.collection('community').doc(postId).update({
      'likes': FieldValue.increment(1),
    });
  }

  /// Chuyển Firestore Timestamp thành chuỗi "X hours ago".
  String _formatTimeAgo(dynamic timestamp) {
    if (timestamp == null) return 'Just now';
    try {
      final dt = (timestamp as dynamic).toDate() as DateTime;
      final diff = DateTime.now().difference(dt);
      if (diff.inMinutes < 1) return 'Just now';
      if (diff.inHours < 1) return '${diff.inMinutes}m ago';
      if (diff.inDays < 1) return '${diff.inHours}h ago';
      return '${diff.inDays}d ago';
    } catch (_) {
      return 'Just now';
    }
  }
}
