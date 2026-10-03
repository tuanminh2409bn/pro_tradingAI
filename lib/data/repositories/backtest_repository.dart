import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;
import '../../core/constants/backend_endpoints.dart';
import '../models/backtest_models.dart';

class BacktestRequestException implements Exception {
  final String errorKey;
  const BacktestRequestException(this.errorKey);
}

class BacktestRepository {
  final FirebaseFirestore _firestore;
  final FirebaseAuth _auth;
  final http.Client _client;
  late final String Function() _operationIdFactory;
  String? _pendingCreationId;
  String? _pendingCreationFingerprint;

  BacktestRepository({
    FirebaseFirestore? firestore,
    FirebaseAuth? auth,
    http.Client? client,
    String Function()? operationIdFactory,
  }) : _firestore = firestore ?? FirebaseFirestore.instance,
       _auth = auth ?? FirebaseAuth.instance,
       _client = client ?? http.Client() {
    _operationIdFactory =
        operationIdFactory ??
        () => _firestore.collection('backtest_sessions').doc().id;
  }

  Future<BacktestRecording?> loadRecording({
    required String userId,
    required String symbol,
  }) async {
    final sessions = await _firestore
        .collection('backtest_sessions')
        .where('userId', isEqualTo: userId)
        .orderBy('createdAt', descending: true)
        .limit(20)
        .get();
    for (final session in sessions.docs) {
      final data = session.data();
      if (data['symbol'] != symbol.toUpperCase() || data['recording'] == null) {
        continue;
      }
      final raw = data['recording'];
      if (raw is! Map) {
        throw const FormatException('Invalid backtest recording');
      }
      final recording = BacktestRecording.fromMap(
        Map<String, dynamic>.from(raw),
        sessionId: session.id,
      );
      if (recording.simulation.replay.symbol != symbol.toUpperCase()) {
        throw const FormatException('Backtest recording identity mismatch');
      }
      return recording;
    }
    return null;
  }

  Future<void> saveRecording(
    BacktestRecording recording, {
    bool includeHistory = false,
  }) async {
    final snapshot = recording.simulation;
    final equity =
        snapshot.balance +
        snapshot.trades.fold<double>(
          0,
          (total, trade) =>
              total +
              trade.floatingPnl(recording.bars[snapshot.replay.cursor].close),
        );
    final data = <String, dynamic>{
      if (includeHistory)
        'recording': recording.toMap()
      else
        'recording.simulation': snapshot.toMap(),
      'currentBalance': snapshot.balance,
      'equity': equity,
      'openPL': equity - snapshot.balance,
      'speed': snapshot.replay.speed,
      'isPlaying': snapshot.replay.isPlaying,
      'isLocked': snapshot.isLocked,
      'status': snapshot.isLocked ? 'REVIEW_REQUIRED' : 'ACTIVE',
    };
    if (utf8.encode(jsonEncode(data)).length > 800000) {
      throw const FormatException('Backtest recording is too large');
    }
    data['updatedAt'] = FieldValue.serverTimestamp();
    await _firestore
        .collection('backtest_sessions')
        .doc(snapshot.replay.sessionId)
        .update(data);
  }

  /// Tạo session backtest mới trong Firestore và trả về object.
  Future<BacktestSession> createSession({
    required String symbol,
    required DateTime startTime,
    required DateTime endTime,
    required double balance,
    required String userId,
  }) async {
    final currentUser = _auth.currentUser;
    if (currentUser == null || currentUser.uid != userId) {
      throw const BacktestRequestException('backtest_auth_required');
    }
    final token = await currentUser.getIdToken();
    if (token == null || token.isEmpty) {
      throw const BacktestRequestException('backtest_auth_required');
    }
    final intent = <String, Object>{
      'userId': userId,
      'symbol': symbol,
      'startTime': startTime.toUtc().toIso8601String(),
      'endTime': endTime.toUtc().toIso8601String(),
      'balance': balance,
    };
    final fingerprint = jsonEncode(intent);
    if (_pendingCreationFingerprint != fingerprint) {
      _pendingCreationFingerprint = fingerprint;
      _pendingCreationId = _operationIdFactory();
    }
    final response = await _client
        .post(
          Uri.parse('${BackendEndpoints.apiBaseUrl}/api/backtest/sessions'),
          headers: {
            'Content-Type': 'application/json',
            'Authorization': 'Bearer $token',
          },
          body: jsonEncode({...intent, 'requestId': _pendingCreationId}),
        )
        .timeout(const Duration(seconds: 20));
    if (response.statusCode != 200) {
      if (response.statusCode >= 400 && response.statusCode < 500) {
        _pendingCreationFingerprint = null;
        _pendingCreationId = null;
      }
      throw BacktestRequestException(
        response.statusCode == 429
            ? 'backtest_quota_exhausted'
            : response.statusCode == 401
            ? 'backtest_auth_required'
            : response.statusCode == 403
            ? 'backtest_access_denied'
            : 'backtest_creation_failed',
      );
    }
    final decoded = jsonDecode(response.body);
    if (decoded is! Map ||
        decoded['status'] != 'success' ||
        decoded['sessionId'] is! String ||
        !RegExp(r'^[a-f0-9]{64}$').hasMatch(decoded['sessionId'] as String)) {
      throw const BacktestRequestException('backtest_creation_failed');
    }
    _pendingCreationFingerprint = null;
    _pendingCreationId = null;

    return BacktestSession(
      id: decoded['sessionId'] as String,
      symbol: symbol,
      startTime: startTime,
      endTime: endTime,
      initialBalance: balance,
      currentBalance: balance,
      equity: balance,
      openPL: 0,
      speed: 1,
      isPlaying: false,
    );
  }

  /// Stream trade đang mở trong một session — từ Firestore thật.
  Stream<List<BacktestTrade>> getActiveTrades(String sessionId) {
    return _firestore
        .collection('backtest_sessions')
        .doc(sessionId)
        .collection('trades')
        .where('status', isEqualTo: 'OPEN')
        .snapshots()
        .map((snapshot) {
          return snapshot.docs.map((doc) {
            final data = doc.data();
            return BacktestTrade(
              id: doc.id,
              symbol: data['symbol'] ?? '',
              type: data['type'] ?? 'BUY',
              entryPrice: (data['entryPrice'] ?? 0).toDouble(),
              currentPrice: (data['currentPrice'] ?? 0).toDouble(),
              volume: (data['volume'] ?? 0.1).toDouble(),
              profit: (data['profit'] ?? 0).toDouble(),
              openTime: data['openTime'] != null
                  ? (data['openTime'] as Timestamp).toDate()
                  : DateTime.now(),
            );
          }).toList();
        });
  }

  /// Stream lịch sử trades đã đóng.
  Stream<List<BacktestTrade>> getTradeHistory(String sessionId) {
    return _firestore
        .collection('backtest_sessions')
        .doc(sessionId)
        .collection('trades')
        .where('status', isEqualTo: 'CLOSED')
        .orderBy('closeTime', descending: true)
        .snapshots()
        .map((snapshot) {
          return snapshot.docs.map((doc) {
            final data = doc.data();
            return BacktestTrade(
              id: doc.id,
              symbol: data['symbol'] ?? '',
              type: data['type'] ?? 'BUY',
              entryPrice: (data['entryPrice'] ?? 0).toDouble(),
              currentPrice: (data['closePrice'] ?? 0).toDouble(),
              volume: (data['volume'] ?? 0.1).toDouble(),
              profit: (data['profit'] ?? 0).toDouble(),
              openTime: data['openTime'] != null
                  ? (data['openTime'] as Timestamp).toDate()
                  : DateTime.now(),
            );
          }).toList();
        });
  }

  /// Stream các sessions của một user.
  Stream<List<BacktestSession>> getUserSessions(String userId) {
    return _firestore
        .collection('backtest_sessions')
        .where('userId', isEqualTo: userId)
        .orderBy('createdAt', descending: true)
        .limit(20)
        .snapshots()
        .map((snapshot) {
          return snapshot.docs.map((doc) {
            final data = doc.data();
            return BacktestSession(
              id: doc.id,
              symbol: data['symbol'] ?? '',
              startTime: DateTime.parse(
                data['startTime'] ?? DateTime.now().toIso8601String(),
              ),
              endTime: DateTime.parse(
                data['endTime'] ?? DateTime.now().toIso8601String(),
              ),
              initialBalance: (data['initialBalance'] ?? 0).toDouble(),
              currentBalance: (data['currentBalance'] ?? 0).toDouble(),
              equity: (data['equity'] ?? 0).toDouble(),
              openPL: (data['openPL'] ?? 0).toDouble(),
              speed: (data['speed'] ?? 1).toInt(),
              isPlaying: data['isPlaying'] ?? false,
            );
          }).toList();
        });
  }

  Future<void> pauseSession(String sessionId) async {
    await _firestore.collection('backtest_sessions').doc(sessionId).update({
      'isPlaying': false,
    });
  }

  Future<void> resumeSession(String sessionId) async {
    await _firestore.collection('backtest_sessions').doc(sessionId).update({
      'isPlaying': true,
    });
  }

  Future<void> updateSpeed(String sessionId, int speed) async {
    await _firestore.collection('backtest_sessions').doc(sessionId).update({
      'speed': speed,
    });
  }
}
