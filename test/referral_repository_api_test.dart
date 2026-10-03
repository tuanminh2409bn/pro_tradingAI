import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:protrading_ai/data/repositories/referral_repository.dart';
import 'package:protrading_ai/data/models/referral_models.dart';
import 'package:protrading_ai/core/utils/referral_link.dart';

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
  test(
    'ref query is unambiguous and registration sends only code with token',
    () async {
      const code = 'abcdefghijklmnopqrstuvwx';
      expect(
        referralCodeFromUri(Uri.parse('https://example.test/?ref=$code')),
        code,
      );
      expect(
        referralCodeFromUri(
          Uri.parse('https://example.test/?ref=$code&ref=$code'),
        ),
        isNull,
      );
      expect(
        referralCodeFromUri(
          Uri.parse('https://example.test/?ref=../users/alice'),
        ),
        isNull,
      );
      final client = MockClient((request) async {
        expect(request.url.path, '/api/referral/registration');
        expect(request.headers['Authorization'], 'Bearer offline-token');
        expect(jsonDecode(request.body), {'code': code});
        return http.Response('{"status":"recorded"}', 200);
      });
      addTearDown(client.close);
      final repository = ReferralRepository(
        firestore: _Firestore(),
        auth: _Auth(),
        client: client,
      );
      expect(
        await repository.recordRegistrationReferral(code),
        ReferralRegistrationStatus.recorded,
      );
    },
  );

  test(
    'provision sends only a token and verifies the returned identity',
    () async {
      const code = 'abcdEFGH0123_-abcdEFGH01';
      var calls = 0;
      final client = MockClient((request) async {
        calls++;
        expect(request.url.path, '/api/referral/identity');
        expect(request.method, 'POST');
        expect(request.headers['Authorization'], 'Bearer offline-token');
        expect(request.body, isEmpty);
        return http.Response(
          jsonEncode({
            'code': code,
            'link': 'https://protrading-ai-2026.web.app/?ref=$code',
          }),
          200,
        );
      });
      addTearDown(client.close);
      final auth = _Auth();
      final repository = ReferralRepository(
        firestore: _Firestore(),
        auth: auth,
        client: client,
      );
      expect((await repository.provisionIdentity()).code, code);
      auth.signedIn = false;
      await expectLater(repository.provisionIdentity(), throwsStateError);
      expect(calls, 1);
    },
  );

  test(
    'invalid link, permission and changed identity do not expose a usable code',
    () async {
      final auth = _Auth();
      var response = http.Response('{}', 403);
      final client = MockClient((request) async => response);
      addTearDown(client.close);
      final repository = ReferralRepository(
        firestore: _Firestore(),
        auth: auth,
        client: client,
      );
      await expectLater(repository.provisionIdentity(), throwsStateError);
      response = http.Response(
        jsonEncode({
          'code': 'abcdEFGH0123_-abcdEFGH01',
          'link': 'https://attacker.test/?ref=abcdEFGH0123_-abcdEFGH01',
        }),
        200,
      );
      await expectLater(repository.provisionIdentity(), throwsArgumentError);
      final switching = MockClient((request) async {
        auth.signedIn = false;
        return response;
      });
      addTearDown(switching.close);
      final repository2 = ReferralRepository(
        firestore: _Firestore(),
        auth: auth,
        client: switching,
      );
      await expectLater(repository2.provisionIdentity(), throwsStateError);
    },
  );
}
