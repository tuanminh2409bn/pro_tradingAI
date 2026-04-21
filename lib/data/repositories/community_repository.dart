import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/community_models.dart';

class CommunityRepository {
  final FirebaseFirestore _firestore;

  CommunityRepository({FirebaseFirestore? firestore})
      : _firestore = firestore ?? FirebaseFirestore.instance;

  Stream<List<CommunityPost>> getCommunityFeed() {
    return _firestore
        .collection('community')
        .orderBy('timestamp', descending: true)
        .snapshots()
        .map((snapshot) {
      if (snapshot.docs.isEmpty) {
        // Mock data for demo
        return const [
          CommunityPost(
            userName: 'Alex Volkov',
            avatarUrl: '',
            timeAgo: '2 hours ago',
            content: 'Strong rejection at the 2038 level. Entering long with tight SL. Market flow looks bullish.',
            tradeInfo: 'XAUUSD Long',
            profit: 12450.0,
            isProfit: true,
            likes: 142,
            comments: 28,
            isVerified: true,
          ),
          CommunityPost(
            userName: 'Sarah Quant',
            avatarUrl: '',
            timeAgo: '5 hours ago',
            content: 'BTC is hitting major liquidity zones. Watch for a fakeout above 65k.',
            tradeInfo: 'BTCUSD Short',
            profit: -2120.50,
            isProfit: false,
            likes: 84,
            comments: 12,
          ),
        ];
      }
      return snapshot.docs.map((doc) {
        final data = doc.data();
        return CommunityPost(
          userName: data['userName'] ?? 'Anonymous',
          avatarUrl: data['avatarUrl'] ?? '',
          timeAgo: data['timeAgo'] ?? 'Just now',
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

  Stream<List<LeaderboardEntry>> getLeaderboard() {
    return _firestore
        .collection('leaderboard')
        .orderBy('performance', descending: true)
        .limit(10)
        .snapshots()
        .map((snapshot) {
      if (snapshot.docs.isEmpty) {
        return const [
          LeaderboardEntry(rank: 1, name: 'MacroKing', avatarUrl: '', performance: 24.5, volume: '1.2M'),
          LeaderboardEntry(rank: 2, name: 'YieldFarmer', avatarUrl: '', performance: 18.2, volume: '850K'),
          LeaderboardEntry(rank: 3, name: 'ScalpQueen', avatarUrl: '', performance: 15.1, volume: '2.1M'),
        ];
      }
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

  Future<void> createPost(CommunityPost post) async {
    await _firestore.collection('community').add({
      'userName': post.userName,
      'avatarUrl': post.avatarUrl,
      'content': post.content,
      'tradeInfo': post.tradeInfo,
      'profit': post.profit,
      'isProfit': post.isProfit,
      'likes': post.likes,
      'comments': post.comments,
      'isVerified': post.isVerified,
      'timestamp': FieldValue.serverTimestamp(),
    });
  }
}
