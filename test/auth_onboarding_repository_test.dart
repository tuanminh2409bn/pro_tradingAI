import 'dart:convert';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:protrading_ai/data/repositories/auth_repository.dart';

class _Token extends Fake implements IdTokenResult {
  final String? role;
  _Token(this.role);
  @override
  Map<String, dynamic>? get claims => {'role': role};
}

class _User extends Fake implements User {
  @override
  String get uid => 'alice';
  var refreshed = false;
  String? role = 'standard';
  @override
  Future<String?> getIdToken([bool forceRefresh = false]) async =>
      'offline-token';
  @override
  Future<IdTokenResult> getIdTokenResult([bool forceRefresh = false]) async {
    refreshed = forceRefresh;
    return _Token(role);
  }
}

class _Auth extends Fake implements FirebaseAuth {
  User? account;
  _Auth(this.account);
  @override
  User? get currentUser => account;
}

class _Google extends Fake implements GoogleSignIn {}

void main() {
  test(
    'onboarding sends no role or UID and requires refreshed server claims',
    () async {
      final user = _User();
      final auth = _Auth(user);
      final client = MockClient((request) async {
        expect(request.url.path, '/api/auth/onboarding');
        expect(request.method, 'POST');
        expect(request.headers['Authorization'], 'Bearer offline-token');
        expect(request.body, isEmpty);
        return http.Response(
          jsonEncode({'status': 'ready', 'role': 'standard'}),
          200,
        );
      });
      addTearDown(client.close);
      final repo = AuthRepository(
        firebaseAuth: auth,
        googleSignIn: _Google(),
        client: client,
      );
      await repo.completeWebOnboarding(user);
      expect(user.refreshed, isTrue);
      user.role = null;
      await expectLater(repo.completeWebOnboarding(user), throwsStateError);
    },
  );

  test(
    'changed identity, failed transport and unknown role cannot open dashboard',
    () async {
      final user = _User();
      final auth = _Auth(user);
      var response = http.Response(
        '{"status":"ready","role":"reserved_fifth"}',
        200,
      );
      final client = MockClient((request) async => response);
      addTearDown(client.close);
      final repo = AuthRepository(
        firebaseAuth: auth,
        googleSignIn: _Google(),
        client: client,
      );
      await expectLater(
        repo.completeWebOnboarding(user),
        throwsFormatException,
      );
      response = http.Response('{}', 503);
      await expectLater(repo.completeWebOnboarding(user), throwsStateError);
      auth.account = null;
      await expectLater(repo.completeWebOnboarding(user), throwsStateError);
      expect(user.refreshed, isFalse);
    },
  );
}
