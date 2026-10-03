import 'dart:async';
import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:protrading_ai/data/repositories/trading_repository.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

class _Firestore extends Fake implements FirebaseFirestore {}

class _Sink extends Fake implements WebSocketSink {
  final sent = <Map<String, dynamic>>[];
  @override
  void add(Object? value) =>
      sent.add(jsonDecode(value as String) as Map<String, dynamic>);
  @override
  Future<void> close([int? code, String? reason]) async {}
}

class _Channel extends Fake implements WebSocketChannel {
  final incoming = StreamController<dynamic>();
  final output = _Sink();
  @override
  Stream<dynamic> get stream => incoming.stream;
  @override
  WebSocketSink get sink => output;
  @override
  Future<void> get ready async {}
  @override
  int? get closeCode => 1000;
}

Map<String, dynamic> _bars(String symbol) => {
  'type': 'init',
  'symbol': symbol,
  'candles': [
    {'t': 1700000000, 'o': 100, 'h': 101, 'l': 99, 'c': 100, 'v': 20},
  ],
};

void main() {
  test(
    'late full history for another timeframe cannot replace the chart',
    () async {
      final channel = _Channel();
      final repository = TradingRepository(
        firestore: _Firestore(),
        channelFactory: (_) => channel,
      );
      repository.changeTimeframe('15');
      final received = <Object>[];
      final subscription = repository
          .getCandleStream('XAUUSD')
          .listen(received.add);
      channel.incoming.add(jsonEncode({..._bars('XAUUSD'), 'interval': '5'}));
      await Future<void>.delayed(Duration.zero);
      expect(received, isEmpty);
      channel.incoming.add(jsonEncode({..._bars('XAUUSD'), 'interval': '15'}));
      await Future<void>.delayed(Duration.zero);
      expect(received, hasLength(1));
      await subscription.cancel();
      repository.dispose();
      await channel.incoming.close();
    },
  );

  test(
    'late full history for another symbol cannot replace the chart',
    () async {
      final channel = _Channel();
      final repository = TradingRepository(
        firestore: _Firestore(),
        channelFactory: (_) => channel,
      );
      repository.changeSymbol('BTCUSD');
      final received = <Object>[];
      final subscription = repository
          .getCandleStream('BTCUSD')
          .listen(received.add);
      channel.incoming.add(jsonEncode(_bars('XAUUSD')));
      await Future<void>.delayed(Duration.zero);
      expect(received, isEmpty);
      channel.incoming.add(jsonEncode(_bars('BTCUSD')));
      await Future<void>.delayed(Duration.zero);
      expect(received, hasLength(1));
      await subscription.cancel();
      repository.dispose();
      await channel.incoming.close();
    },
  );

  testWidgets(
    'reconnect restores selection and dispose prevents more reconnects',
    (tester) async {
      final channels = <_Channel>[];
      final repository = TradingRepository(
        firestore: _Firestore(),
        channelFactory: (_) {
          final channel = _Channel();
          channels.add(channel);
          return channel;
        },
      );
      repository.changeSymbol('BTCUSD');
      repository.changeTimeframe('15');
      await tester.pump();
      unawaited(channels.first.incoming.close());
      await tester.pump();
      await tester.pump(const Duration(seconds: 5));
      expect(channels, hasLength(2));
      expect(
        channels.last.output.sent,
        containsAll([
          {'action': 'set_symbol', 'symbol': 'BTCUSD'},
          {'action': 'set_interval', 'interval': '15'},
        ]),
      );
      repository.dispose();
      unawaited(channels.last.incoming.close());
      await tester.pump(const Duration(seconds: 10));
      expect(channels, hasLength(2));
    },
  );
}
