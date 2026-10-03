import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:protrading_ai/data/repositories/backtest_repository.dart';

class _User extends Fake implements User {
  @override
  String get uid => 'alice';
  @override
  Future<String?> getIdToken([bool forceRefresh = false]) async =>
      'offline-token';
}

class _Auth extends Fake implements FirebaseAuth {
  bool signedIn = true;
  @override
  User? get currentUser => signedIn ? _User() : null;
}

class _Firestore extends Fake implements FirebaseFirestore {}

void main() {
  Future<void> create(BacktestRepository repository) =>
      repository.createSession(
        symbol: 'BTCUSD',
        startTime: DateTime.utc(2026, 10, 1),
        endTime: DateTime.utc(2026, 10, 2),
        balance: 1000,
        userId: 'alice',
      );

  test(
    'Session creation uses token API and recovers the same operation after transport loss',
    () async {
      final intents = <Map<String, dynamic>>[];
      final client = MockClient((request) async {
        expect(request.url.path, '/api/backtest/sessions');
        expect(request.headers['Authorization'], 'Bearer offline-token');
        final intent = jsonDecode(request.body) as Map<String, dynamic>;
        expect(intent['userId'], 'alice');
        expect(intent['balance'], 1000);
        expect(intent['startTime'], endsWith('Z'));
        intents.add(intent);
        if (intents.length == 1) throw http.ClientException('offline');
        return http.Response(
          jsonEncode({'status': 'success', 'sessionId': 'a' * 64}),
          200,
        );
      });
      addTearDown(client.close);
      final repository = BacktestRepository(
        firestore: _Firestore(),
        auth: _Auth(),
        client: client,
        operationIdFactory: () => 'creation_request_12345678',
      );
      await expectLater(
        create(repository),
        throwsA(isA<http.ClientException>()),
      );
      await create(repository);
      expect(intents, hasLength(2));
      expect(intents[0]['requestId'], intents[1]['requestId']);
    },
  );

  test(
    'Quota denial is localized and missing identity never reaches API',
    () async {
      var requests = 0;
      final client = MockClient((request) async {
        requests++;
        return http.Response('{"detail":"quota_exhausted"}', 429);
      });
      addTearDown(client.close);
      final auth = _Auth();
      final repository = BacktestRepository(
        firestore: _Firestore(),
        auth: auth,
        client: client,
        operationIdFactory: () => 'creation_request_12345678',
      );
      await expectLater(
        create(repository),
        throwsA(
          isA<BacktestRequestException>().having(
            (e) => e.errorKey,
            'message',
            'backtest_quota_exhausted',
          ),
        ),
      );
      auth.signedIn = false;
      await expectLater(
        create(repository),
        throwsA(
          isA<BacktestRequestException>().having(
            (e) => e.errorKey,
            'message',
            'backtest_auth_required',
          ),
        ),
      );
      expect(requests, 1);
    },
  );
}
