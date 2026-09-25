import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:protrading_ai/features/auth/bloc/auth_bloc.dart';

void main() {
  test('authentication errors expose only approved localization keys', () {
    expect(
      authFailureKey(FirebaseAuthException(code: 'user-not-found')),
      'auth_invalid_credentials',
    );
    expect(
      authFailureKey(FirebaseAuthException(code: 'wrong-password')),
      'auth_invalid_credentials',
    );
    expect(
      authFailureKey(FirebaseAuthException(code: 'email-already-in-use')),
      'auth_email_in_use',
    );
    expect(
      authFailureKey(Exception('provider secret detail')),
      'auth_generic_error',
    );
  });
}
