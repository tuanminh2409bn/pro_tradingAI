import 'dart:async';
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
  final http.Client _client;
  late final String Function() _operationIdFactory;
  final Map<String, String> _pendingWrites = {};

  CommunityRepository({
    FirebaseFirestore? firestore,
    FirebaseAuth? auth,
    http.Client? client,
    String Function()? operationIdFactory,
  }) : _firestore = firestore ?? FirebaseFirestore.instance,
       _auth = auth ?? FirebaseAuth.instance,
       _client = client ?? http.Client() {
    _operationIdFactory =
        operationIdFactory ?? () => _firestore.collection('community').doc().id;
  }

  /// Stream bài viết cộng đồng — dữ liệu thật từ Firestore.
  /// Nếu chưa có bài viết nào → trả về list rỗng, UI sẽ hiển thị empty state.
  Stream<List<CommunityPost>> getCommunityFeed() {
    return _firestore
        .collection('community')
        .orderBy('timestamp', descending: true)
        .limit(50)
        .snapshots()
        .map((snapshot) {
          return snapshot.docs.map((doc) => _post(doc.id, doc.data())).toList();
        });
  }

  Stream<CommunityPost?> watchPost(String postId) => _firestore
      .collection('community')
      .doc(postId)
      .snapshots()
      .map((doc) => doc.exists ? _post(doc.id, doc.data()!) : null);

  /// Read the latest 100 comments, displayed oldest first within that window.
  Stream<List<CommunityComment>> getComments(String postId) => _firestore
      .collection('community')
      .doc(postId)
      .collection('comments')
      .orderBy('timestamp', descending: true)
      .limit(100)
      .snapshots()
      .map(
        (snapshot) => snapshot.docs.reversed.map((doc) {
          final data = doc.data();
          return CommunityComment(
            id: doc.id,
            ownerId: _text(data['userId']),
            userName: _text(data['userName'], fallback: 'Community member'),
            content: _text(data['content']),
            timeAgo: _formatTimeAgo(data['timestamp']),
          );
        }).toList(),
      );

  CommunityPost _post(String id, Map<String, dynamic> data) => CommunityPost(
    id: id,
    ownerId: _text(data['userId']),
    userName: _text(data['userName'], fallback: 'Community member'),
    avatarUrl: _text(data['avatarUrl']),
    timeAgo: _formatTimeAgo(data['timestamp']),
    content: _text(data['content']),
    tradeInfo: _text(data['tradeInfo']),
    profit: data['profit'] is num && (data['profit'] as num).isFinite
        ? (data['profit'] as num).toDouble()
        : 0,
    isProfit: data['isProfit'] != false,
    chartImageUrl: data['chartImageUrl'] is String
        ? data['chartImageUrl'] as String
        : null,
    likes: _count(data['likes']),
    comments: _count(data['comments']),
    isVerified: data['isVerified'] == true,
    tradeVerified: data['tradeVerified'] == true,
    verificationReference: data['verificationReference'] is String
        ? data['verificationReference'] as String
        : null,
  );

  String _text(Object? value, {String fallback = ''}) =>
      value is String && value.isNotEmpty ? value : fallback;
  int _count(Object? value) => value is int && value >= 0 ? value : 0;

  /// Bảng xếp hạng đã xác minh, chỉ nhận các trường công khai từ API.
  Stream<List<LeaderboardEntry>> getLeaderboard() async* {
    yield await _loadLeaderboard();
    yield* Stream.periodic(
      const Duration(minutes: 5),
    ).asyncMap((_) => _loadLeaderboard());
  }

  Future<List<LeaderboardEntry>> _loadLeaderboard() async {
    final user = _auth.currentUser;
    if (user == null) throw StateError('Authentication required');
    final token = await user.getIdToken();
    if (token == null || token.isEmpty || _auth.currentUser?.uid != user.uid) {
      throw StateError('Authentication required');
    }
    final response = await _client
        .get(
          Uri.parse('$_serverBaseUrl/api/community/leaderboard'),
          headers: {'Authorization': 'Bearer $token'},
        )
        .timeout(const Duration(seconds: 15));
    if (_auth.currentUser?.uid != user.uid) {
      throw StateError('Identity changed');
    }
    if (response.statusCode != 200) throw StateError('Leaderboard unavailable');
    final data = jsonDecode(response.body);
    if (data is! Map<String, dynamic> ||
        data['source'] != 'broker_verified' ||
        data['entries'] is! List ||
        (data['entries'] as List).length > 20) {
      throw const FormatException('Invalid leaderboard response');
    }
    final now = DateTime.now().toUtc();
    final metrics = <VerifiedLeaderboardMetric>[];
    for (final raw in data['entries'] as List) {
      if (raw is! Map<String, dynamic> || raw['publicId'] is! String) continue;
      final publicId = raw['publicId'] as String;
      final fields = Map<String, dynamic>.from(raw)..remove('publicId');
      final date = fields['asOf'];
      final metric = VerifiedLeaderboardMetric.fromServer(
        publicId,
        fields,
        asOf: date is String ? DateTime.tryParse(date)?.toUtc() : null,
        now: now,
      );
      if (metric != null) metrics.add(metric);
    }
    return CommunityLeaderboard.rankVerified(metrics)
        .map(
          (entry) => LeaderboardEntry(
            rank: entry.rank,
            name: entry.displayName,
            avatarUrl: '',
            performance: entry.growthPercent,
            volume: entry.unitVolume.toString(),
          ),
        )
        .toList();
  }

  /// Đăng bài viết mới lên community feed.
  Future<void> createPost(String rawContent) async {
    await _writeContent(rawContent);
  }

  Future<void> createComment(String postId, String rawContent) async {
    if (!RegExp(r'^[A-Za-z0-9_-]{1,128}$').hasMatch(postId)) {
      throw ArgumentError('Invalid post ID');
    }
    await _writeContent(rawContent, postId: postId);
  }

  Future<void> _writeContent(String rawContent, {String? postId}) async {
    final user = _auth.currentUser;
    if (user == null) throw StateError('Authentication is required');
    final content = normalizeCommunityPostContent(rawContent);
    if (content.isEmpty ||
        content.length >
            (postId == null
                ? communityPostMaxLength
                : communityCommentMaxLength)) {
      throw ArgumentError('Invalid community content');
    }
    final token = await user.getIdToken();
    if (token == null || token.isEmpty || _auth.currentUser?.uid != user.uid) {
      throw StateError('Authentication is required');
    }
    final fingerprint = jsonEncode([user.uid, postId, content]);
    final requestId = _pendingWrites.putIfAbsent(
      fingerprint,
      _operationIdFactory,
    );
    final response = await _client
        .post(
          Uri.parse(
            '$_serverBaseUrl/api/community/${postId == null ? 'posts' : 'comments'}',
          ),
          headers: {
            'Content-Type': 'application/json',
            'Authorization': 'Bearer $token',
          },
          body: jsonEncode({
            'requestId': requestId,
            'content': content,
            if (postId != null) 'postId': postId,
          }),
        )
        .timeout(const Duration(seconds: 15));
    if (response.statusCode >= 400 && response.statusCode < 500) {
      _pendingWrites.remove(fingerprint);
    }
    if (response.statusCode != 200) {
      throw StateError('Community write unavailable');
    }
    final data = jsonDecode(response.body);
    final id = data is Map<String, dynamic>
        ? data[postId == null ? 'postId' : 'commentId']
        : null;
    if (id is! String || !RegExp(r'^[a-f0-9]{64}$').hasMatch(id)) {
      throw const FormatException('Invalid community response');
    }
    _pendingWrites.remove(fingerprint);
  }

  /// The backend owns the like marker and counter transaction.
  Future<Set<String>> getLikedPostIds(Iterable<String> postIds) async {
    final user = _auth.currentUser;
    if (user == null) throw StateError('Authentication is required');
    final ids = postIds.toSet();
    if (ids.length > 51 ||
        ids.any((id) => !RegExp(r'^[A-Za-z0-9_-]{1,128}$').hasMatch(id))) {
      throw ArgumentError('Invalid community post IDs');
    }
    final markers = await Future.wait(
      ids.map((id) async {
        final marker = await _firestore
            .collection('community')
            .doc(id)
            .collection('likes')
            .doc(user.uid)
            .get();
        return marker.exists ? id : null;
      }),
    );
    if (_auth.currentUser?.uid != user.uid) {
      throw StateError('Identity changed');
    }
    return markers.whereType<String>().toSet();
  }

  Future<void> likePost(String postId) async {
    final user = _auth.currentUser;
    final token = await user?.getIdToken();
    if (token == null || token.isEmpty || _auth.currentUser?.uid != user?.uid) {
      throw StateError('Authentication is required');
    }
    final response = await _client
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
