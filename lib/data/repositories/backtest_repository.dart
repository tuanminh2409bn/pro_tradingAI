import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/backtest_models.dart';

class BacktestRepository {
  final FirebaseFirestore _firestore;

  BacktestRepository({FirebaseFirestore? firestore})
    : _firestore = firestore ?? FirebaseFirestore.instance;

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
    final docRef = await _firestore.collection('backtest_sessions').add({
      'userId': userId,
      'symbol': symbol,
      'startTime': startTime.toIso8601String(),
      'endTime': endTime.toIso8601String(),
      'initialBalance': balance,
      'currentBalance': balance,
      'equity': balance,
      'openPL': 0.0,
      'speed': 1,
      'isPlaying': false,
      'status': 'CREATED',
      'createdAt': FieldValue.serverTimestamp(),
    });

    return BacktestSession(
      id: docRef.id,
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
