import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;
import '../../core/constants/backend_endpoints.dart';
import '../models/news_models.dart';
import '../models/trading_models.dart';

int? _epochSeconds(dynamic value) {
  if (value is Timestamp) return value.seconds;
  if (value is DateTime) return value.millisecondsSinceEpoch ~/ 1000;
  if (value is num && value > 0) return value.toInt();
  return null;
}

ScheduledNewsEvent? parseScheduledNewsEvent(
  Map<String, dynamic> data, {
  required int nowEpochSeconds,
}) {
  if ((data['impact'] as String?)?.toUpperCase() != 'HIGH') return null;
  final eventId = data['event_id'];
  final startTime = _epochSeconds(data['start_time']);
  final duration = (data['duration_min'] as num?)?.toDouble();
  final rawCurrencies = data['currencies'];
  final rawEvidence = data['evidence'];
  if (eventId is! String ||
      eventId.trim().isEmpty ||
      startTime == null ||
      duration == null ||
      rawCurrencies is! List ||
      rawEvidence is! Map) {
    return null;
  }
  final currencies =
      rawCurrencies
          .whereType<String>()
          .map((value) => value.trim().toUpperCase())
          .where((value) => RegExp(r'^[A-Z]{3}$').hasMatch(value))
          .toSet()
          .toList()
        ..sort();
  if (currencies.isEmpty) return null;
  final evidence = Map<String, dynamic>.from(rawEvidence);
  final evidenceTimestamp = _epochSeconds(evidence['timestamp']);
  if (evidenceTimestamp == null || evidence['source_id'] != eventId) {
    return null;
  }
  evidence['timestamp'] = evidenceTimestamp;
  final event = ScheduledNewsEvent(
    eventId: eventId,
    startTime: startTime,
    durationMinutes: duration,
    label: (data['label'] ?? data['title'] ?? '').toString(),
    color: (data['color'] ?? '').toString(),
    currencies: currencies,
    evidence: evidence,
  );
  final overlay = redZoneOverlayForEvent(event);
  return overlay.isValid && event.endTime > nowEpochSeconds ? event : null;
}

RedZoneOverlay redZoneOverlayForEvent(ScheduledNewsEvent event) =>
    RedZoneOverlay(
      eventId: event.eventId,
      startTime: event.startTime,
      durationMinutes: event.durationMinutes,
      label: event.label,
      color: event.color,
      currencies: List<String>.from(event.currencies),
      evidence: Map<String, dynamic>.from(event.evidence),
    );

RedZoneOverlay? parseScheduledRedZone(
  Map<String, dynamic> data, {
  required int nowEpochSeconds,
}) {
  final event = parseScheduledNewsEvent(data, nowEpochSeconds: nowEpochSeconds);
  return event == null ? null : redZoneOverlayForEvent(event);
}

ScheduledNewsEvent? selectNextScheduledNewsEvent(
  Iterable<Map<String, dynamic>> records, {
  required int nowEpochSeconds,
}) {
  final byEventId = <String, ScheduledNewsEvent>{};
  for (final record in records) {
    final event = parseScheduledNewsEvent(
      record,
      nowEpochSeconds: nowEpochSeconds,
    );
    if (event == null) continue;
    final current = byEventId[event.eventId];
    final eventEvidenceTime = event.evidence['timestamp'] as int;
    final currentEvidenceTime = current?.evidence['timestamp'] as int?;
    if (current == null || eventEvidenceTime > currentEvidenceTime!) {
      byEventId[event.eventId] = event;
    }
  }
  final candidates = byEventId.values.toList()
    ..sort((left, right) {
      final byStart = left.startTime.compareTo(right.startTime);
      return byStart != 0 ? byStart : left.eventId.compareTo(right.eventId);
    });
  return candidates.isEmpty ? null : candidates.first;
}

class NewsRepository {
  final FirebaseFirestore _firestore;
  final FirebaseAuth _auth;
  static const String _serverBaseUrl = BackendEndpoints.apiBaseUrl;

  NewsRepository({FirebaseFirestore? firestore, FirebaseAuth? auth})
    : _firestore = firestore ?? FirebaseFirestore.instance,
      _auth = auth ?? FirebaseAuth.instance;

  Stream<List<NewsArticle>> getNewsFeed() {
    return _firestore
        .collection('news')
        .orderBy('timestamp', descending: true)
        .snapshots()
        .map((snapshot) {
          if (snapshot.docs.isEmpty) {
            return <NewsArticle>[];
          }
          return snapshot.docs
              .map((doc) {
                final data = doc.data();
                final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
                final timestamp = data['timestamp'] as Timestamp?;
                final timeStr = timestamp != null
                    ? _formatTimeAgo(timestamp.toDate())
                    : '__TIME_UNAVAILABLE__';
                final title = (data['title'] ?? '').toString().trim();
                final source = (data['source'] ?? '').toString().trim();
                final storedTime = (data['timeAgo'] ?? '').toString().trim();

                return NewsArticle(
                  title: title,
                  source: source.isEmpty ? '__SOURCE_UNAVAILABLE__' : source,
                  timeAgo: storedTime.isEmpty ? timeStr : storedTime,
                  sentimentScore: (data['sentimentScore'] ?? 0).toInt(),
                  type: data['type'] ?? 'ALERT',
                  impact: data['impact'] ?? 'LOW',
                  summary: data['summary'] ?? '',
                  url: data['url'] ?? '',
                  imageUrl: data['imageUrl'] ?? '',
                  scheduledEvent: parseScheduledNewsEvent(
                    data,
                    nowEpochSeconds: now,
                  ),
                );
              })
              .where((article) => article.title.isNotEmpty)
              .toList();
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

  /// Emits only scheduled HIGH-impact events with complete timing and
  /// provenance. RSS headlines are deliberately excluded from chart Red Zones.
  Stream<RedZoneOverlay?> watchNextScheduledHighImpactEvent() {
    return _firestore
        .collection('news')
        .orderBy('timestamp', descending: true)
        .limit(100)
        .snapshots()
        .map((snapshot) {
          final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
          final event = selectNextScheduledNewsEvent(
            snapshot.docs.map((doc) => doc.data()),
            nowEpochSeconds: now,
          );
          return event == null ? null : redZoneOverlayForEvent(event);
        });
  }

  Stream<SentimentPulse> getSentimentPulse() {
    return _firestore.collection('analytics').doc('sentiment').snapshots().map((
      snapshot,
    ) {
      final data = snapshot.data();
      if (data == null) {
        return const SentimentPulse.unavailable();
      }
      final score = data['fearGreedIndex'] ?? data['globalScore'];
      final fear = data['bearish'] ?? data['fearPercent'];
      final neutral = data['neutral'] ?? data['neutralPercent'];
      final greed = data['bullish'] ?? data['greedPercent'];
      final phase = (data['mood'] ?? data['phase'] ?? '').toString().trim();
      if (score is! num ||
          fear is! num ||
          neutral is! num ||
          greed is! num ||
          score < 0 ||
          score > 100 ||
          fear < 0 ||
          fear > 100 ||
          neutral < 0 ||
          neutral > 100 ||
          greed < 0 ||
          greed > 100 ||
          phase.isEmpty) {
        return const SentimentPulse.unavailable();
      }
      return SentimentPulse(
        globalScore: score.toInt(),
        fearPercent: fear.toDouble(),
        neutralPercent: neutral.toDouble(),
        greedPercent: greed.toDouble(),
        phase: phase,
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
    await _firestore
        .collection('chat_history')
        .doc(userId)
        .collection(chatType)
        .doc(message.id)
        .set(message.toMap());
  }

  Future<List<ChatMessage>> loadChatHistory({
    required String userId,
    required String chatType,
    int limit = 50,
  }) async {
    if (userId.isEmpty) return [];
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
  }

  Future<void> clearChatHistory({
    required String userId,
    required String chatType,
  }) async {
    if (userId.isEmpty) return;
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
      final token = await _auth.currentUser?.getIdToken();
      if (token == null || token.isEmpty) return friendly;
      final uri = Uri.parse('$_serverBaseUrl/api/ai/chat');
      final response = await http
          .post(
            uri,
            headers: {
              'Content-Type': 'application/json',
              'Authorization': 'Bearer $token',
            },
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
