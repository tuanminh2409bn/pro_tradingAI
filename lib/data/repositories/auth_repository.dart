import 'dart:convert';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:http/http.dart' as http;
import '../../core/constants/backend_endpoints.dart';
import '../../core/constants/local_qa_mode.dart';

class AuthRepository {
  final FirebaseAuth _firebaseAuth;
  final GoogleSignIn _googleSignIn;
  final http.Client _client;

  AuthRepository({
    FirebaseAuth? firebaseAuth,
    GoogleSignIn? googleSignIn,
    http.Client? client,
  }) : _firebaseAuth = firebaseAuth ?? FirebaseAuth.instance,
       _googleSignIn = googleSignIn ?? GoogleSignIn.instance,
       _client = client ?? http.Client();

  Stream<User?> get user => _firebaseAuth.authStateChanges();

  Future<void> completeWebOnboarding(User user) async {
    if (_firebaseAuth.currentUser?.uid != user.uid) {
      throw StateError('Identity changed');
    }
    final token = await user.getIdToken();
    if (token == null ||
        token.isEmpty ||
        _firebaseAuth.currentUser?.uid != user.uid) {
      throw StateError('Authentication required');
    }
    final response = await _client
        .post(
          Uri.parse('${BackendEndpoints.apiBaseUrl}/api/auth/onboarding'),
          headers: {'Authorization': 'Bearer $token'},
        )
        .timeout(const Duration(seconds: 15));
    if (_firebaseAuth.currentUser?.uid != user.uid) {
      throw StateError('Identity changed');
    }
    if (response.statusCode != 200) {
      throw StateError('Account onboarding unavailable');
    }
    final data = jsonDecode(response.body);
    const roles = {
      'standard',
      'verified_partner',
      'professional',
      'enterprise',
    };
    if (data is! Map<String, dynamic> ||
        data['status'] != 'ready' ||
        !roles.contains(data['role'])) {
      throw const FormatException('Invalid onboarding response');
    }
    final refreshed = await user.getIdTokenResult(true);
    if (_firebaseAuth.currentUser?.uid != user.uid) {
      throw StateError('Identity changed');
    }
    if (!roles.contains(refreshed.claims?['role'])) {
      throw StateError('Account role unavailable');
    }
  }

  Future<void> signUp({required String email, required String password}) async {
    try {
      await _firebaseAuth.createUserWithEmailAndPassword(
        email: email,
        password: password,
      );
    } catch (e) {
      rethrow;
    }
  }

  Future<void> logInWithEmailAndPassword({
    required String email,
    required String password,
  }) async {
    try {
      await _firebaseAuth.signInWithEmailAndPassword(
        email: email,
        password: password,
      );
    } catch (e) {
      rethrow;
    }
  }

  Future<UserCredential?> signInWithGoogle() async {
    try {
      if (kIsWeb && LocalQaMode.enabled) {
        throw StateError('Google sign-in is unavailable in local QA mode');
      }
      if (kIsWeb) {
        final GoogleAuthProvider googleProvider = GoogleAuthProvider();
        return await _firebaseAuth.signInWithPopup(googleProvider);
      } else {
        // Native Google Sign In
        final GoogleSignInAccount googleUser = await _googleSignIn
            .authenticate();

        final GoogleSignInAuthentication googleAuth = googleUser.authentication;

        final OAuthCredential credential = GoogleAuthProvider.credential(
          idToken: googleAuth.idToken,
        );

        return await _firebaseAuth.signInWithCredential(credential);
      }
    } catch (e) {
      rethrow;
    }
  }

  Future<void> logOut() async {
    try {
      await _firebaseAuth.signOut();
      if (!(kIsWeb && LocalQaMode.enabled)) {
        await _googleSignIn.signOut();
      }
    } catch (e) {
      rethrow;
    }
  }
}
