import 'dart:async';
import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:http/http.dart' as http;
import '../models/trading_models.dart';

class TradingRepository {
  final FirebaseFirestore _firestore;
  static const String _serverUrl = 'protrading-data-engine-22073478183.asia-southeast1.run.app';
  static const String _wsUrl = 'wss://$_serverUrl/ws/trading';
  static const String _apiUrl = 'https://$_serverUrl/api/trade';
  
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
            // print('REPO: Received ${realCandles.length} candles. Emitting...');
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

  Future<bool> executeTrade(String symbol, String type, double lotSize) async {
    try {
      final response = await http.post(
        Uri.parse(_apiUrl),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'action': type, 'volume': lotSize, 'symbol': symbol}),
      );
      return response.statusCode == 200;
    } catch (e) { return false; }
  }

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

  Stream<List<TradingSignal>> getActiveSignals() {
    return _firestore.collection('signals').where('status', isEqualTo: 'ACTIVE').snapshots().map((snapshot) {
      if (snapshot.docs.isEmpty) {
        return [const TradingSignal(symbol: 'XAUUSD', entryPrice: 4809.50, slPrice: 4802.10, tpPrices: [4825.0], probability: 85, type: 'BUY', status: 'ACTIVE')];
      }
      return snapshot.docs.map((doc) => TradingSignal(
        symbol: doc.data()['symbol'] ?? '',
        entryPrice: (doc.data()['entryPrice'] ?? 0).toDouble(),
        slPrice: (doc.data()['slPrice'] ?? 0).toDouble(),
        tpPrices: List<double>.from(doc.data()['tpPrices'] ?? []),
        probability: (doc.data()['probability'] ?? 0).toInt(),
        type: doc.data()['type'] ?? 'BUY',
        status: doc.data()['status'] ?? 'ACTIVE',
      )).toList();
    });
  }
}
