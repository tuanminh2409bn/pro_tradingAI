import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/backtest_models.dart';

class BacktestRepository {
  final FirebaseFirestore _firestore;

  BacktestRepository({FirebaseFirestore? firestore})
      : _firestore = firestore ?? FirebaseFirestore.instance;

  Future<BacktestSession> createSession({
    required String symbol,
    required DateTime startTime,
    required DateTime endTime,
    required double balance,
  }) async {
    // In real app, this creates a record in Firestore
    return BacktestSession(
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

  Stream<List<BacktestTrade>> getActiveTrades(String sessionId) {
    // Mocking active trades for simulation
    return Stream.value([]);
  }

  // Simulation controls
  Future<void> pauseSession(String sessionId) async {}
  Future<void> resumeSession(String sessionId) async {}
  Future<void> updateSpeed(String sessionId, int speed) async {}
}
