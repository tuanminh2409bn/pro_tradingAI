import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:http/http.dart' as http;
import '../models/news_models.dart';

class NewsRepository {
  final FirebaseFirestore _firestore;
  static const String _serverBaseUrl =
      'https://protrading-data-engine-22073478183.asia-southeast1.run.app';

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

  Stream<SentimentPulse> getSentimentPulse() {
    return _firestore
        .collection('analytics')
        .doc('sentiment')
        .snapshots()
        .map((snapshot) {
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
        globalScore: (data['fearGreedIndex'] ?? data['globalScore'] ?? 0).toInt(),
        fearPercent: (data['bearish'] ?? data['fearPercent'] ?? 0.0).toDouble(),
        neutralPercent: (data['neutral'] ?? data['neutralPercent'] ?? 0.0).toDouble(),
        greedPercent: (data['bullish'] ?? data['greedPercent'] ?? 0.0).toDouble(),
        phase: data['mood'] ?? data['phase'] ?? 'NEUTRAL',
      );
    });
  }

  String _formatTimeAgo(DateTime dateTime) {
    final diff = DateTime.now().difference(dateTime);
    if (diff.inDays > 0) return '${diff.inDays}d ago';
    if (diff.inHours > 0) return '${diff.inHours}h ago';
    if (diff.inMinutes > 0) return '${diff.inMinutes}m ago';
    return 'Just now';
  }

  Future<String> getAISentimentAnalysis(String query) async {
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
        // Handle different response formats from server
        if (data is Map<String, dynamic>) {
          return data['response'] ??
              data['message'] ??
              data['reply'] ??
              data['content'] ??
              data['text'] ??
              data.toString();
        }
        return response.body;
      } else {
        return 'DeepSeek AI: Unable to analyze at the moment. Server returned status ${response.statusCode}. Please try again.';
      }
    } catch (e) {
      return 'DeepSeek AI: Connection error — $e. Please check your network and try again.';
    }
  }
}
