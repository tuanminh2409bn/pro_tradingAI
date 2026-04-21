import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/news_models.dart';

class NewsRepository {
  final FirebaseFirestore _firestore;

  NewsRepository({FirebaseFirestore? firestore})
      : _firestore = firestore ?? FirebaseFirestore.instance;

  Stream<List<NewsArticle>> getNewsFeed() {
    return _firestore
        .collection('news')
        .orderBy('timestamp', descending: true)
        .snapshots()
        .map((snapshot) {
      if (snapshot.docs.isEmpty) {
        // Mock data if Firestore is empty
        return [
          const NewsArticle(
            title: 'USD Consumer Confidence rises to 108.7, exceeding expectations.',
            source: 'ForexFactory',
            timeAgo: '2m ago',
            sentimentScore: 82,
            type: 'FOREXFACTORY',
            impact: 'HIGH',
          ),
          const NewsArticle(
            title: 'Whale alert: \$420M BTC transferred to Coinbase. Sell-side mounting.',
            source: 'Twitter Analytics',
            timeAgo: '12m ago',
            sentimentScore: 14,
            type: 'TWITTER',
            impact: 'MEDIUM',
          ),
        ];
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
          globalScore: 71,
          fearPercent: 12.4,
          neutralPercent: 16.6,
          greedPercent: 71.0,
          phase: 'GREED',
        );
      }
      return SentimentPulse(
        globalScore: (data['globalScore'] ?? 0).toInt(),
        fearPercent: (data['fearPercent'] ?? 0).toDouble(),
        neutralPercent: (data['neutralPercent'] ?? 0).toDouble(),
        greedPercent: (data['greedPercent'] ?? 0).toDouble(),
        phase: data['phase'] ?? 'NEUTRAL',
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
    // In a real app, this calls DeepSeek V3.2 via Cloud Functions
    await Future.delayed(const Duration(seconds: 1));
    
    if (query.toLowerCase().contains('gold') || query.toLowerCase().contains('xau')) {
      return "DeepSeek V3.2: Gold (XAUUSD) shows a strong bullish structural shift on the 4H timeframe. Liquidity pools at 2032 have been cleared. Targeted resistance: 2055.";
    } else if (query.toLowerCase().contains('btc')) {
      return "DeepSeek V3.2: Bitcoin is experiencing significant sell-side pressure from whale transfers. High probability of a liquidity hunt below 63.5k before any reversal.";
    }
    
    return "DeepSeek V3.2: I've analyzed the current macro environment. Market sentiment is leaning towards risk-on, but watch for the upcoming FOMC statement for volatility spikes.";
  }
}
