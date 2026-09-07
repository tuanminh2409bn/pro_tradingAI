import 'dart:async';
import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:http/http.dart' as http;
import '../models/trading_models.dart';

class TradingRepository {
  final FirebaseFirestore _firestore;
  static const String _serverUrl = '103-69-189-243.sslip.io';
  static const String _wsUrl = 'wss://$_serverUrl/ws/trading';
  static const String _apiBaseUrl = 'https://$_serverUrl';

  WebSocketChannel? _channel;
  final _accountController = StreamController<TradingAccount>.broadcast();
  final _candleController = StreamController<List<Candle>>.broadcast();
  final _pricesController = StreamController<Map<String, double>>.broadcast();

  List<Candle> _cache = [];

  /// Mark prices keyed by clean symbol — independent of chart candles.
  final Map<String, double> _symbolPrices = {};
  String _activeSymbol = 'XAUUSD';

  TradingRepository({FirebaseFirestore? firestore})
    : _firestore = firestore ?? FirebaseFirestore.instance {
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
    print('Attempting Global Connection: $_wsUrl');
    try {
      _channel?.sink.close();
      _channel = WebSocketChannel.connect(Uri.parse(_wsUrl));
      _channel!.stream.listen(
        (message) {
          final data = jsonDecode(message);
          final msgType = data['type'] as String? ?? '';

          // ── 1. Heartbeat: ignore completely ──────────────────────
          if (msgType == 'heartbeat') return;

          // ── 2. Account info (only in init/update) ────────────────
          if (data['account'] != null) {
            final acc = data['account'];
            _accountController.add(
              TradingAccount(
                balance: (acc['balance'] as num).toDouble(),
                equity: (acc['equity'] as num).toDouble(),
                margin: (acc['margin'] as num).toDouble(),
                leverage: (acc['leverage'] as num).toInt(),
                status: 'LIVE',
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
              print(
                'REPO: tick delta — ${delta.length} candle(s) merged. Cache: ${_cache.length}',
              );
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
                  ),
                )
                .toList();
            _candleController.add(_cache);
            print('REPO: $msgType — full load ${_cache.length} candles');
          }
        },
        onError: (e) {
          print('REPO: Error: $e');
          _reconnect();
        },
        onDone: () {
          print('REPO: Connection Closed');
          _reconnect();
        },
      );
    } catch (e) {
      print('REPO: Exception: $e');
      _reconnect();
    }
  }

  void _reconnect() {
    _channel?.sink.close();
    Future.delayed(const Duration(seconds: 5), () {
      if (_channel == null || _channel!.closeCode != null) {
        _initWebSocket();
      }
    });
  }

  // ─── Firebase Auth Token Helper ───
  Future<Map<String, String>> _getAuthHeaders() async {
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
    return headers;
  }

  // ─── Execute Trade via API ───
  Future<Position?> executeTrade({
    required String symbol,
    required String type,
    required double lotSize,
    double entryPrice = 0.0,
    double slPrice = 0.0,
    List<double> tpPrices = const [],
    String userId = '',
    String tradingMode = 'scalping',
  }) async {
    try {
      final headers = await _getAuthHeaders();
      final response = await http.post(
        Uri.parse('$_apiBaseUrl/api/trade'),
        headers: headers,
        body: jsonEncode({
          'userId': userId,
          'action': type,
          'symbol': symbol,
          'volume': lotSize,
          'entryPrice': entryPrice,
          'slPrice': slPrice,
          'tpPrices': tpPrices,
          'tradingMode': tradingMode,
        }),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['status'] == 'success') {
          return Position(
            id: data['tradeId'] ?? '',
            symbol: symbol,
            type: type,
            lotSize: lotSize,
            openPrice: (data['entryPrice'] as num?)?.toDouble() ?? entryPrice,
            currentPrice:
                (data['entryPrice'] as num?)?.toDouble() ?? entryPrice,
            sl: slPrice,
            tp: tpPrices.isNotEmpty ? tpPrices.first : 0.0,
            tpLevels: tpPrices,
            profit: 0.0,
            status: 'OPEN',
            tradingMode: tradingMode,
            openTime: DateTime.now(),
          );
        }
      }
      return null;
    } catch (e) {
      print('REPO: Trade execution error: $e');
      return null;
    }
  }

  // ─── Close Trade via API ───
  Future<double?> closeTrade(String tradeId, {String userId = ''}) async {
    try {
      final headers = await _getAuthHeaders();
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
    } catch (e) {
      print('REPO: Close trade error: $e');
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
      final headers = await _getAuthHeaders();
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
        final text = (data['response'] ?? data['message'] ?? friendly).toString();
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
  Future<void> saveRiskConfig(String userId, RiskConfig config) async {
    try {
      await http.post(
        Uri.parse('$_apiBaseUrl/api/risk-config'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'userId': userId,
          'balance': config.balance,
          'riskPerTrade': config.riskPerTrade,
          'maxDailyLoss': config.maxDailyLoss,
        }),
      );
    } catch (e) {
      print('REPO: Save risk config error: $e');
    }
  }

  Future<RiskConfig?> getRiskConfig(String userId) async {
    try {
      final response = await http.get(
        Uri.parse('$_apiBaseUrl/api/risk-config/$userId'),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['config'] != null) {
          return RiskConfig.fromMap(data['config']);
        }
      }
      return null;
    } catch (e) {
      print('REPO: Get risk config error: $e');
      return null;
    }
  }

  // ─── Open Positions ───
  Future<List<Position>> getOpenPositions(String userId) async {
    try {
      final response = await http.get(
        Uri.parse('$_apiBaseUrl/api/trades/$userId'),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['trades'] != null) {
          return (data['trades'] as List)
              .map((t) => Position.fromMap(t))
              .toList();
        }
      }
      return [];
    } catch (e) {
      print('REPO: Get open positions error: $e');
      return [];
    }
  }

  // ─── Request AI Analysis (Day 4 MTF payload) ───
  Future<void> requestAnalysis(
    String symbol,
    String timeframe, {
    String userId = '',
    List<Map<String, dynamic>>? candlesExecution,
    List<Map<String, dynamic>>? candlesHtf1,
    List<Map<String, dynamic>>? candlesHtf2,
    Map<String, dynamic>? accountContext,
    String? tradingMode,
  }) async {
    try {
      await _firestore.collection('analysis_requests').add({
        'symbol': symbol,
        'timeframe': timeframe,
        'userId': userId,
        'status': 'PENDING',
        'requestedAt': FieldValue.serverTimestamp(),
        if (tradingMode != null) 'trading_mode': tradingMode,
        if (candlesExecution != null) 'candles_execution': candlesExecution,
        if (candlesHtf1 != null) 'candles_htf_1': candlesHtf1,
        if (candlesHtf2 != null) 'candles_htf_2': candlesHtf2,
        if (accountContext != null) 'account_context': accountContext,
      });
      print(
        'REPO: Analysis request sent for $symbol ($timeframe) '
        'candles=${candlesExecution?.length ?? 0} userId=$userId',
      );
    } catch (e) {
      print('REPO: Error sending analysis request: $e');
    }
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
    _channel?.sink.add(jsonEncode({"action": "set_interval", "interval": tf}));
  }

  void changeSymbol(String symbol) {
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
        print('REPO: No active signals for user $userId.');
        return <TradingSignal>[];
      }

      final signals = snapshot.docs
          .map((doc) => TradingSignal.fromMap(doc.data()))
          .toList();

      print('REPO: Parsed ${signals.length} active signals for user $userId');
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
    try {
      await _firestore
          .collection('chat_history')
          .doc(userId)
          .collection(chatType)
          .doc(message.id)
          .set(message.toMap());
    } catch (e) {
      print('REPO: saveChatMessage error: $e');
    }
  }

  /// Load chat history (most recent [limit] messages, ordered by timestamp asc)
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
      // Reverse so oldest is first (chat display order)
      return messages.reversed.toList();
    } catch (e) {
      print('REPO: loadChatHistory error: $e');
      return [];
    }
  }

  /// Delete all chat history for a user's specific chat type
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
      print('REPO: clearChatHistory error: $e');
    }
  }

  void dispose() {
    _channel?.sink.close();
    _accountController.close();
    _candleController.close();
    _pricesController.close();
  }
}
