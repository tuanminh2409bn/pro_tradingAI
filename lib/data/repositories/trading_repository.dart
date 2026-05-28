import 'dart:async';
import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:http/http.dart' as http;
import '../models/trading_models.dart';

class TradingRepository {
  final FirebaseFirestore _firestore;
  static const String _serverUrl = 'protrading-data-engine-22073478183.asia-southeast1.run.app';
  static const String _wsUrl = 'wss://$_serverUrl/ws/trading';
  static const String _apiBaseUrl = 'https://$_serverUrl';
  
  WebSocketChannel? _channel;
  final _accountController = StreamController<TradingAccount>.broadcast();
  final _candleController = StreamController<List<Candle>>.broadcast();

  List<Candle> _cache = [];

  TradingRepository({FirebaseFirestore? firestore})
      : _firestore = firestore ?? FirebaseFirestore.instance {
    _initWebSocket();
  }

  void _initWebSocket() {
    print('Attempting Global Connection: $_wsUrl');
    try {
      _channel?.sink.close();
      _channel = WebSocketChannel.connect(Uri.parse(_wsUrl));
      _channel!.stream.listen(
        (message) {
          final data = jsonDecode(message);
          print('REPO: Received type: ${data['type']}, candles: ${data['candles']?.length ?? 0}');
          
          if (data['type'] == 'heartbeat') return;

          if (data['account'] != null) {
            final acc = data['account'];
            _accountController.add(TradingAccount(
              balance: (acc['balance'] as num).toDouble(),
              equity: (acc['equity'] as num).toDouble(),
              margin: (acc['margin'] as num).toDouble(),
              leverage: (acc['leverage'] as num).toInt(),
              status: 'LIVE',
            ));
          }

          final List<dynamic>? candlesJson = data['candles'];
          if (candlesJson != null && candlesJson.isNotEmpty) {
            final List<Candle> realCandles = candlesJson.map((c) => Candle(
              timestamp: DateTime.fromMillisecondsSinceEpoch(c['t'] * 1000),
              open: (c['o'] as num).toDouble(),
              high: (c['h'] as num).toDouble(),
              low: (c['l'] as num).toDouble(),
              close: (c['c'] as num).toDouble(),
            )).toList();
            
            _cache = List.from(realCandles);
            _candleController.add(_cache);
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
            currentPrice: (data['entryPrice'] as num?)?.toDouble() ?? entryPrice,
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

  // ─── AI Chat via API ───
  Future<String> sendAIChat({
    required String message, 
    String symbol = 'XAUUSD',
    String timeframe = '5',
    String userId = '',
  }) async {
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
        final data = jsonDecode(response.body);
        return data['response'] ?? 'Không có phản hồi từ AI';
      }
      return 'Lỗi: Server trả về ${response.statusCode}';
    } catch (e) { 
      return 'Lỗi: Không thể kết nối đến AI service'; 
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

  // ─── Request AI Analysis ───
  Future<void> requestAnalysis(String symbol, String timeframe) async {
    try {
      await _firestore.collection('analysis_requests').add({
        'symbol': symbol,
        'timeframe': timeframe,
        'status': 'PENDING',
        'requestedAt': FieldValue.serverTimestamp(),
      });
      print('REPO: Analysis request sent to Firebase for $symbol ($timeframe)');
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
    _channel?.sink.add(jsonEncode({"action": "set_symbol", "symbol": symbol}));
    _cache.clear();
    _candleController.add([]);
  }

  Stream<List<TradingSignal>> getActiveSignals() {
    return _firestore.collection('signals').where('status', isEqualTo: 'ACTIVE').snapshots().map((snapshot) {
      if (snapshot.docs.isEmpty) {
        print('REPO: No active signals found in Firebase.');
        return [];
      }
      
      final signals = snapshot.docs.map((doc) {
        final data = doc.data();
        // Parse layers from Firestore
        List<Map<String, dynamic>> layers = [];
        if (data['layers'] != null) {
          layers = (data['layers'] as List<dynamic>)
              .map((l) => Map<String, dynamic>.from(l as Map))
              .toList();
        }
        // Extract suggested lot from Layer 4 if available
        double suggestedLot = 0.1;
        for (final layer in layers) {
          if (layer['layer'] == 4 && layer['suggested_lot'] != null) {
            suggestedLot = (layer['suggested_lot'] as num).toDouble();
          }
        }
        
        return TradingSignal(
          symbol: data['symbol'] ?? '',
          entryPrice: (data['entryPrice'] ?? 0).toDouble(),
          slPrice: (data['slPrice'] ?? 0).toDouble(),
          tpPrices: List<double>.from(data['tpPrices'] ?? []),
          probability: (data['probability'] ?? 0).toInt(),
          type: data['type'] ?? 'BUY',
          status: data['status'] ?? 'ACTIVE',
          layers: layers,
          suggestedLot: suggestedLot,
        );
      }).toList();
      
      print('REPO: Parsed ${signals.length} active signals with ${signals.first.layers.length} layers');
      return signals;
    });
  }

  void dispose() {
    _channel?.sink.close();
    _accountController.close();
    _candleController.close();
  }
}
