import 'dart:async';
import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:http/http.dart' as http;
import '../models/trading_models.dart';
import '../../core/constants/backend_endpoints.dart';

/// Only known backend codes are translated; provider details never reach UI.
class AnalysisRequestFailure implements Exception {
  final String messageKey;

  const AnalysisRequestFailure([String? code])
    : messageKey = code == 'quota_exhausted'
          ? 'tr_analysis_quota_exhausted'
          : code == 'account_role_required' || code == 'account_disabled'
          ? 'tr_analysis_account_access_required'
          : code == 'policy_pending'
          ? 'tr_analysis_policy_pending'
          : code == 'timeout'
          ? 'tr_analysis_timeout'
          : 'tr_analysis_request_failed';
}

Future<void> waitForAnalysisRequest(
  Stream<Map<String, dynamic>?> statuses, {
  Duration timeout = const Duration(seconds: 90),
}) async {
  final completed = Completer<void>();
  final subscription = statuses.listen(
    (data) {
      if (completed.isCompleted) return;
      if (data == null || data['status'] == 'ERROR') {
        completed.completeError(
          AnalysisRequestFailure(
            data?['error'] is String ? data!['error'] as String : null,
          ),
        );
      } else if (data['status'] == 'COMPLETED') {
        completed.complete();
      }
    },
    onError: (Object error) {
      if (!completed.isCompleted) {
        completed.completeError(const AnalysisRequestFailure());
      }
    },
    onDone: () {
      if (!completed.isCompleted) {
        completed.completeError(const AnalysisRequestFailure());
      }
    },
  );
  try {
    await completed.future.timeout(
      timeout,
      onTimeout: () => throw const AnalysisRequestFailure('timeout'),
    );
  } finally {
    await subscription.cancel();
  }
}

/// Retains one key while a paper execution's outcome is unknown.
class PaperIntentKeys {
  final Map<String, String> _pending = {};

  String forPayload(Map<String, dynamic> payload, String Function() newKey) =>
      _pending.putIfAbsent(jsonEncode(payload), newKey);

  void complete(Map<String, dynamic> payload) {
    _pending.remove(jsonEncode(payload));
  }
}

List<Map<String, dynamic>> buildPartialTradePayloads({
  required String signalId,
  required String signalChartId,
  required String symbol,
  required String type,
  required double entryPrice,
  required double slPrice,
  required TakeProfitAllocationPlan plan,
  required String userId,
  required String tradingMode,
}) {
  return plan.legs
      .map(
        (leg) => <String, dynamic>{
          'signalId': signalId,
          'signalChartId': signalChartId,
          'userId': userId,
          'action': type,
          'symbol': symbol,
          'volume': leg.volume,
          'entryPrice': entryPrice,
          'slPrice': slPrice,
          'tpPrices': [leg.targetPrice],
          'tradingMode': tradingMode,
        },
      )
      .toList(growable: false);
}

class TradingRepository {
  final FirebaseFirestore _firestore;
  final PaperIntentKeys _paperIntentKeys = PaperIntentKeys();
  static const String _wsUrl = '${BackendEndpoints.wsBaseUrl}/ws/trading';
  static const String _apiBaseUrl = BackendEndpoints.apiBaseUrl;

  WebSocketChannel? _channel;
  final WebSocketChannel Function(Uri) _channelFactory;
  StreamSubscription<dynamic>? _channelSubscription;
  Timer? _reconnectTimer;
  bool _disposed = false;
  final _accountController = StreamController<TradingAccount>.broadcast();
  final _candleController = StreamController<List<Candle>>.broadcast();
  final _pricesController = StreamController<Map<String, double>>.broadcast();

  List<Candle> _cache = [];

  /// Mark prices keyed by clean symbol — independent of chart candles.
  final Map<String, double> _symbolPrices = {};
  String _activeSymbol = 'XAUUSD';
  String _activeTimeframe = '5';

  TradingRepository({
    FirebaseFirestore? firestore,
    WebSocketChannel Function(Uri)? channelFactory,
  }) : _firestore = firestore ?? FirebaseFirestore.instance,
       _channelFactory = channelFactory ?? WebSocketChannel.connect {
    _initWebSocket();
  }

  Map<String, double> get symbolPrices => Map.unmodifiable(_symbolPrices);

  Stream<Map<String, double>> get priceBookStream => _pricesController.stream;

  void _mergePrices(dynamic raw, {String? tickSymbol, double? tickPrice}) {
    var changed = false;
    if (raw is Map) {
      raw.forEach((key, value) {
        if (value is num && value > 0) {
          final sym = key.toString().toUpperCase();
          if (_symbolPrices[sym] != value.toDouble()) {
            _symbolPrices[sym] = value.toDouble();
            changed = true;
          }
        }
      });
    }
    if (tickSymbol != null && tickPrice != null && tickPrice > 0) {
      final sym = tickSymbol.toUpperCase();
      if (_symbolPrices[sym] != tickPrice) {
        _symbolPrices[sym] = tickPrice;
        changed = true;
      }
    }
    if (changed) {
      _pricesController.add(Map<String, double>.from(_symbolPrices));
    }
  }

  void _initWebSocket() {
    if (_disposed) return;
    try {
      final previous = _channel;
      final channel = _channelFactory(Uri.parse(_wsUrl));
      _channel = channel;
      _channelSubscription?.cancel();
      previous?.sink.close();
      unawaited(
        channel.ready.then<void>(
          (_) {
            if (_disposed || !identical(_channel, channel)) return;
            channel.sink.add(
              jsonEncode({'action': 'set_symbol', 'symbol': _activeSymbol}),
            );
            channel.sink.add(
              jsonEncode({
                'action': 'set_interval',
                'interval': _activeTimeframe,
              }),
            );
          },
          onError: (Object error, StackTrace stack) {
            if (identical(_channel, channel)) _reconnect();
          },
        ),
      );
      _channelSubscription = channel.stream.listen(
        (message) {
          if (_disposed) return;
          final data = jsonDecode(message);
          final msgType = data['type'] as String? ?? '';

          // ── 1. Heartbeat: ignore completely ──────────────────────
          if (msgType == 'heartbeat') return;

          // ── 2. Account info (only in init/update) ────────────────
          if (data['account'] is Map) {
            final acc = data['account'];
            _accountController.add(
              TradingAccount(
                balance: (acc['balance'] as num?)?.toDouble() ?? 0.0,
                equity: (acc['equity'] as num?)?.toDouble() ?? 0.0,
                margin: (acc['margin'] as num?)?.toDouble() ?? 0.0,
                leverage: (acc['leverage'] as num?)?.toInt() ?? 0,
                status: (acc['status'] ?? 'UNAVAILABLE').toString(),
                source: (acc['source'] ?? 'unavailable').toString(),
              ),
            );
          }

          final msgSymbol = (data['symbol'] as String?)?.toUpperCase();
          final msgPrice = (data['price'] as num?)?.toDouble();
          _mergePrices(
            data['prices'],
            tickSymbol: msgSymbol,
            tickPrice: msgPrice,
          );
          // Late full snapshots must have the same guard as candle deltas.
          if (msgSymbol != _activeSymbol ||
              (data['interval'] != null &&
                  data['interval'].toString() != _activeTimeframe)) {
            return;
          }

          // ── 3. TICK (delta) — only changed candles ───────────────
          if (msgType == 'tick') {
            // Ignore ticks for a symbol we are not currently viewing
            if (msgSymbol != null && msgSymbol != _activeSymbol) {
              return;
            }
            final delta = data['delta'] as List<dynamic>?;
            if (delta != null && delta.isNotEmpty && _cache.isNotEmpty) {
              for (final c in delta) {
                final int t = c['t'] as int;
                final updated = Candle(
                  timestamp: DateTime.fromMillisecondsSinceEpoch(t * 1000),
                  open: (c['o'] as num).toDouble(),
                  high: (c['h'] as num).toDouble(),
                  low: (c['l'] as num).toDouble(),
                  close: (c['c'] as num).toDouble(),
                  volume: (c['v'] as num?)?.toDouble() ?? 0.0,
                );
                final idx = _cache.indexWhere(
                  (candle) =>
                      candle.timestamp.millisecondsSinceEpoch ~/ 1000 == t,
                );
                if (idx >= 0) {
                  _cache[idx] = updated;
                } else {
                  _cache.add(updated);
                  if (_cache.length > 3000) _cache.removeAt(0);
                }
              }
              _candleController.add(List.from(_cache));
            }
            return;
          }

          // ── 4. INIT / UPDATE — full candle list ──────────────────
          final List<dynamic>? candlesJson = data['candles'];
          if (candlesJson != null && candlesJson.isNotEmpty) {
            _cache = candlesJson
                .map(
                  (c) => Candle(
                    timestamp: DateTime.fromMillisecondsSinceEpoch(
                      c['t'] * 1000,
                    ),
                    open: (c['o'] as num).toDouble(),
                    high: (c['h'] as num).toDouble(),
                    low: (c['l'] as num).toDouble(),
                    close: (c['c'] as num).toDouble(),
                    volume: (c['v'] as num?)?.toDouble() ?? 0.0,
                  ),
                )
                .toList();
            _candleController.add(_cache);
          }
        },
        onError: (_) {
          if (identical(_channel, channel)) _reconnect();
        },
        onDone: () {
          if (identical(_channel, channel)) _reconnect();
        },
      );
    } catch (_) {
      _reconnect();
    }
  }

  void _reconnect() {
    if (_disposed || _reconnectTimer?.isActive == true) return;
    _reconnectTimer = Timer(const Duration(seconds: 5), _initWebSocket);
    _channel?.sink.close();
  }

  // ─── Firebase Auth Token Helper ───
  Future<Map<String, String>> _getAuthHeaders({
    bool requiredAuth = false,
  }) async {
    final Map<String, String> headers = {'Content-Type': 'application/json'};
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user != null) {
        final token = await user.getIdToken();
        if (token != null) {
          headers['Authorization'] = 'Bearer $token';
        }
      }
    } catch (_) {
      // Không có token → gửi request không có auth (fallback)
    }
    if (requiredAuth && !headers.containsKey('Authorization')) {
      throw StateError('Authentication required');
    }
    return headers;
  }

  // ─── Execute Trade via API ───
  Future<Position?> executeTrade({
    required String signalId,
    required String signalChartId,
    required String symbol,
    required String type,
    required double lotSize,
    double entryPrice = 0.0,
    double slPrice = 0.0,
    List<double> tpPrices = const [],
    String userId = '',
    String tradingMode = 'scalping',
  }) async {
    return _postTradePayload({
      'signalId': signalId,
      'signalChartId': signalChartId,
      'userId': userId,
      'action': type,
      'symbol': symbol,
      'volume': lotSize,
      'entryPrice': entryPrice,
      'slPrice': slPrice,
      'tpPrices': tpPrices,
      'tradingMode': tradingMode,
    });
  }

  /// Sends one existing paper-trade request per TP leg without changing the
  /// public `/api/trade` payload contract.
  Future<List<Position>> executePartialTakeProfitTrade({
    required String signalId,
    required String signalChartId,
    required String symbol,
    required String type,
    required double entryPrice,
    required double slPrice,
    required TakeProfitAllocationPlan plan,
    String userId = '',
    String tradingMode = 'scalping',
  }) async {
    final positions = <Position>[];
    final payloads = buildPartialTradePayloads(
      signalId: signalId,
      signalChartId: signalChartId,
      symbol: symbol,
      type: type,
      entryPrice: entryPrice,
      slPrice: slPrice,
      plan: plan,
      userId: userId,
      tradingMode: tradingMode,
    );
    for (final payload in payloads) {
      final position = await _postTradePayload(payload);
      if (position == null) break;
      positions.add(position);
    }
    return positions;
  }

  Future<Position?> _postTradePayload(Map<String, dynamic> payload) async {
    try {
      final headers = await _getAuthHeaders(requiredAuth: true);
      headers['Idempotency-Key'] = _paperIntentKeys.forPayload(
        payload,
        () => _firestore.collection('_intent_ids').doc().id,
      );
      final response = await http.post(
        Uri.parse('$_apiBaseUrl/api/trade'),
        headers: headers,
        body: jsonEncode(payload),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['status'] == 'success') {
          _paperIntentKeys.complete(payload);
          final tpPrices = (payload['tpPrices'] as List<dynamic>)
              .map((price) => (price as num).toDouble())
              .toList(growable: false);
          return Position(
            id: data['tradeId'] ?? '',
            symbol: payload['symbol'] as String,
            type: payload['action'] as String,
            lotSize: (payload['volume'] as num).toDouble(),
            openPrice:
                (data['entryPrice'] as num?)?.toDouble() ??
                (payload['entryPrice'] as num).toDouble(),
            currentPrice:
                (data['entryPrice'] as num?)?.toDouble() ??
                (payload['entryPrice'] as num).toDouble(),
            sl: (payload['slPrice'] as num).toDouble(),
            tp: tpPrices.isNotEmpty ? tpPrices.first : 0.0,
            tpLevels: tpPrices,
            profit: 0.0,
            status: 'OPEN',
            tradingMode: payload['tradingMode'] as String,
            openTime: DateTime.now(),
          );
        }
      }
      if (response.statusCode >= 400 && response.statusCode < 500) {
        _paperIntentKeys.complete(payload);
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  // ─── Close Trade via API ───
  Future<double?> closeTrade(String tradeId, {String userId = ''}) async {
    try {
      final headers = await _getAuthHeaders(requiredAuth: true);
      final response = await http.post(
        Uri.parse('$_apiBaseUrl/api/trade/close'),
        headers: headers,
        body: jsonEncode({'userId': userId, 'tradeId': tradeId}),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['status'] == 'success') {
          return (data['profit'] as num?)?.toDouble() ?? 0.0;
        }
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  // ─── AI Chat via API (Day 5: structured + fallback flag) ───
  Future<({String response, bool fallback, bool success})> sendAIChat({
    required String message,
    String symbol = 'XAUUSD',
    String timeframe = '5',
    String userId = '',
  }) async {
    const friendly =
        'Hệ thống AI đang thực hiện phân tích kỹ thuật tạm thời. Vui lòng thử lại sau vài giây.';
    try {
      final headers = await _getAuthHeaders(requiredAuth: true);
      final response = await http.post(
        Uri.parse('$_apiBaseUrl/api/ai/chat'),
        headers: headers,
        body: jsonEncode({
          'userId': userId,
          'message': message,
          'symbol': symbol,
          'timeframe': timeframe,
        }),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        final text = (data['response'] ?? data['message'] ?? friendly)
            .toString();
        final fallback = data['fallback'] == true || data['status'] == 'error';
        return (
          response: text,
          fallback: fallback,
          success: data['status'] == 'success',
        );
      }
      return (response: friendly, fallback: true, success: false);
    } catch (e) {
      return (response: friendly, fallback: true, success: false);
    }
  }

  // ─── Risk Config ───
  Future<DailyCutoffStatus> getDailyCutoffStatus(String userId) async {
    if (userId.isEmpty) throw StateError('Authentication required');
    final response = await http.get(
      Uri.parse('$_apiBaseUrl/api/risk/cutoff/$userId'),
      headers: await _getAuthHeaders(requiredAuth: true),
    );
    return _parseDailyCutoffResponse(response);
  }

  Future<DailyCutoffStatus> reviewDailyCutoff(String userId) =>
      _postDailyCutoff(userId, 'review');

  Future<DailyCutoffStatus> acknowledgeDailyCutoff(String userId) =>
      _postDailyCutoff(userId, 'ack');

  Future<DailyCutoffStatus> _postDailyCutoff(
    String userId,
    String action,
  ) async {
    if (userId.isEmpty) throw StateError('Authentication required');
    final response = await http.post(
      Uri.parse('$_apiBaseUrl/api/risk/cutoff/$action'),
      headers: await _getAuthHeaders(requiredAuth: true),
      body: jsonEncode({'userId': userId}),
    );
    return _parseDailyCutoffResponse(response);
  }

  DailyCutoffStatus _parseDailyCutoffResponse(http.Response response) {
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw StateError('Cutoff status unavailable');
    }
    final decoded = jsonDecode(response.body);
    if (decoded is! Map) throw StateError('Cutoff status unavailable');
    return DailyCutoffStatus.fromMap(Map<String, dynamic>.from(decoded));
  }

  Future<void> saveRiskConfig(String userId, RiskConfig config) async {
    if (userId.isEmpty) throw StateError('Authentication required');
    final headers = await _getAuthHeaders(requiredAuth: true);
    final response = await http.post(
      Uri.parse('$_apiBaseUrl/api/risk-config'),
      headers: headers,
      body: jsonEncode({
        'userId': userId,
        'balance': config.balance,
        'riskPerTrade': config.riskPerTrade,
        'maxDailyLoss': config.maxDailyLoss,
      }),
    );
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw StateError('Risk configuration request failed');
    }
    final data = jsonDecode(response.body);
    if (data is! Map || data['status'] != 'success') {
      throw StateError('Risk configuration was not saved');
    }
  }

  Future<RiskConfig?> getRiskConfig(String userId) async {
    if (userId.isEmpty) throw StateError('Authentication required');
    final headers = await _getAuthHeaders(requiredAuth: true);
    final response = await http.get(
      Uri.parse('$_apiBaseUrl/api/risk-config/$userId'),
      headers: headers,
    );
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw StateError('Risk configuration request failed');
    }
    final data = jsonDecode(response.body);
    if (data is! Map || data['status'] != 'success') {
      throw StateError('Risk configuration unavailable');
    }
    final config = data['config'];
    if (config == null) return null;
    if (config is! Map) throw StateError('Invalid risk configuration');
    return RiskConfig.fromMap(Map<String, dynamic>.from(config));
  }

  // ─── Open Positions ───
  Future<List<Position>> getOpenPositions(String userId) async {
    if (userId.isEmpty) throw StateError('Authentication required');
    final headers = await _getAuthHeaders(requiredAuth: true);
    final response = await http.get(
      Uri.parse('$_apiBaseUrl/api/trades/$userId'),
      headers: headers,
    );
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw StateError('Position request failed');
    }
    final data = jsonDecode(response.body);
    if (data is! Map ||
        data['status'] != 'success' ||
        data['trades'] is! List) {
      throw StateError('Position data unavailable');
    }
    return (data['trades'] as List)
        .whereType<Map>()
        .map((trade) => Position.fromMap(Map<String, dynamic>.from(trade)))
        .toList(growable: false);
  }

  // ─── Request AI Analysis (Day 4 MTF payload) ───
  Future<void> requestAnalysis(
    String symbol,
    String timeframe, {
    String userId = '',
    String? tradingMode,
  }) async {
    if (userId.isEmpty) throw StateError('Authentication required');
    final request = await _firestore.collection('analysis_requests').add({
      'symbol': symbol,
      'timeframe': timeframe,
      'execution_tf': timeframe,
      'userId': userId,
      'status': 'PENDING',
      'requestedAt': FieldValue.serverTimestamp(),
      if (tradingMode != null) 'trading_mode': tradingMode,
    });
    await waitForAnalysisRequest(
      request.snapshots().map((snapshot) => snapshot.data()),
    );
  }

  // ─── Streams ───
  Stream<TradingAccount> getTradingAccount(String userId) async* {
    yield* _accountController.stream;
  }

  Stream<List<Candle>> getCandleStream(String symbol) async* {
    if (_cache.isNotEmpty) yield _cache;
    yield* _candleController.stream;
  }

  void changeTimeframe(String tf) {
    if (_disposed || tf == _activeTimeframe) return;
    _activeTimeframe = tf;
    _cache.clear();
    _candleController.add([]);
    _channel?.sink.add(jsonEncode({"action": "set_interval", "interval": tf}));
  }

  void changeSymbol(String symbol) {
    if (_disposed || symbol.toUpperCase() == _activeSymbol) return;
    _activeSymbol = symbol.toUpperCase();
    _channel?.sink.add(
      jsonEncode({"action": "set_symbol", "symbol": _activeSymbol}),
    );
    _cache.clear();
    _candleController.add([]);
  }

  Stream<List<TradingSignal>> getActiveSignals(String userId) {
    // Filter by userId so each account only sees its own AI analysis
    Query<Map<String, dynamic>> query = _firestore
        .collection('signals')
        .where('status', isEqualTo: 'ACTIVE');
    if (userId.isNotEmpty) {
      query = query.where('userId', isEqualTo: userId);
    }
    return query.snapshots().map((snapshot) {
      if (snapshot.docs.isEmpty) {
        return <TradingSignal>[];
      }

      final signals = snapshot.docs
          .map(
            (doc) => TradingSignal.fromMap({...doc.data(), 'signalId': doc.id}),
          )
          .toList();

      return signals;
    });
  }

  // ─── Chat History (Firestore) ───

  /// Save a single chat message to Firestore
  Future<void> saveChatMessage({
    required String userId,
    required String chatType, // 'trading_room' | 'news_feed'
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

  /// Load chat history (most recent [limit] messages, ordered by timestamp asc)
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

  /// Delete all chat history for a user's specific chat type
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

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _reconnectTimer?.cancel();
    _channelSubscription?.cancel();
    _channel?.sink.close();
    _accountController.close();
    _candleController.close();
    _pricesController.close();
  }
}
