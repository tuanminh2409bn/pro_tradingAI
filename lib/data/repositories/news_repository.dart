import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:http/http.dart' as http;
import '../models/news_models.dart';
import '../models/trading_models.dart';

class NewsRepository {
  final FirebaseFirestore _firestore;
  static const String _serverBaseUrl = 'https://103-69-189-243.sslip.io';

  NewsRepository({FirebaseFirestore? firestore})
    : _firestore = firestore ?? FirebaseFirestore.instance;

  Stream<List<NewsArticle>> getNewsFeed() {
    return _firestore
        .collection('news')
        .orderBy('timestamp', descending: true)
        .snapshots()
        .map((snapshot) {
          if (snapshot.docs.isEmpty) {
            return <NewsArticle>[];
          }
          return snapshot.docs.map((doc) {
            final data = doc.data();
            final timestamp = data['timestamp'] as Timestamp?;
            final timeStr = timestamp != null
                ? _formatTimeAgo(timestamp.toDate())
                : 'Just now';

            return NewsArticle(
              title: data['title'] ?? '',
              source: data['source'] ?? 'AI Analyst',
              timeAgo: data['timeAgo'] ?? timeStr,
              sentimentScore: (data['sentimentScore'] ?? 0).toInt(),
              type: data['type'] ?? 'ALERT',
              impact: data['impact'] ?? 'LOW',
              summary: data['summary'] ?? '',
              url: data['url'] ?? '',
              imageUrl: data['imageUrl'] ?? '',
            );
          }).toList();
        });
  }

  /// Day 6 — stream latest HIGH-impact headlines for chart Red Zone.
  Stream<NewsArticle?> watchLatestHighImpactNews() {
    return getNewsFeed().map((articles) {
      for (final a in articles) {
        if (a.impact.toUpperCase() == 'HIGH') return a;
      }
      return null;
    });
  }

  Stream<SentimentPulse> getSentimentPulse() {
    return _firestore.collection('analytics').doc('sentiment').snapshots().map((
      snapshot,
    ) {
      final data = snapshot.data();
      if (data == null) {
        return const SentimentPulse(
          globalScore: 0,
          fearPercent: 0.0,
          neutralPercent: 0.0,
          greedPercent: 0.0,
          phase: 'NEUTRAL',
        );
      }
      return SentimentPulse(
        globalScore: (data['fearGreedIndex'] ?? data['globalScore'] ?? 0)
            .toInt(),
        fearPercent: (data['bearish'] ?? data['fearPercent'] ?? 0.0).toDouble(),
        neutralPercent: (data['neutral'] ?? data['neutralPercent'] ?? 0.0)
            .toDouble(),
        greedPercent: (data['bullish'] ?? data['greedPercent'] ?? 0.0)
            .toDouble(),
        phase: data['mood'] ?? data['phase'] ?? 'NEUTRAL',
      );
    });
  }

  // ─── Chat History (Firestore) ───

  Future<void> saveChatMessage({
    required String userId,
    required String chatType,
    required ChatMessage message,
  }) async {
    if (userId.isEmpty) return;
    try {
      await _firestore
          .collection('chat_history')
          .doc(userId)
          .collection(chatType)
          .doc(message.id)
          .set(message.toMap());
    } catch (e) {
      print('NewsRepo: saveChatMessage error: $e');
    }
  }

  Future<List<ChatMessage>> loadChatHistory({
    required String userId,
    required String chatType,
    int limit = 50,
  }) async {
    if (userId.isEmpty) return [];
    try {
      final snapshot = await _firestore
          .collection('chat_history')
          .doc(userId)
          .collection(chatType)
          .orderBy('timestamp', descending: true)
          .limit(limit)
          .get();
      final messages = snapshot.docs
          .map((doc) => ChatMessage.fromMap(doc.data()))
          .toList();
      return messages.reversed.toList();
    } catch (e) {
      print('NewsRepo: loadChatHistory error: $e');
      return [];
    }
  }

  Future<void> clearChatHistory({
    required String userId,
    required String chatType,
  }) async {
    if (userId.isEmpty) return;
    try {
      final batch = _firestore.batch();
      final snapshot = await _firestore
          .collection('chat_history')
          .doc(userId)
          .collection(chatType)
          .get();
      for (final doc in snapshot.docs) {
        batch.delete(doc.reference);
      }
      await batch.commit();
    } catch (e) {
      print('NewsRepo: clearChatHistory error: $e');
    }
  }

  String _formatTimeAgo(DateTime dateTime) {
    final diff = DateTime.now().difference(dateTime);
    if (diff.inDays > 0) return '${diff.inDays}d ago';
    if (diff.inHours > 0) return '${diff.inHours}h ago';
    if (diff.inMinutes > 0) return '${diff.inMinutes}m ago';
    return 'Just now';
  }

  Future<String> getAISentimentAnalysis(String query) async {
    const friendly =
        'Hệ thống AI đang thực hiện phân tích kỹ thuật tạm thời. Vui lòng thử lại sau vài giây.';
    try {
      final uri = Uri.parse('$_serverBaseUrl/api/ai/chat');
      final response = await http
          .post(
            uri,
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              'message': 'Analyze this for trading impact: $query',
              'symbol': 'XAUUSD',
              'timeframe': '5',
            }),
          )
          .timeout(const Duration(seconds: 30));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data is Map<String, dynamic>) {
          if (data['fallback'] == true || data['status'] == 'error') {
            return (data['response'] ?? data['message'] ?? friendly).toString();
          }
          return data['response'] ??
              data['message'] ??
              data['reply'] ??
              data['content'] ??
              data['text'] ??
              friendly;
        }
        return friendly;
      } else {
        return friendly;
      }
    } catch (e) {
      return friendly;
    }
  }
}
