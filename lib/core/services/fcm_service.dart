import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';

class FCMService {
  final FirebaseFirestore _firestore;
  final FirebaseAuth _auth;
  final FirebaseMessaging _messaging;
  StreamSubscription<String>? _tokenRefreshSubscription;
  StreamSubscription<User?>? _authSubscription;
  String? _owner;
  String? _token;
  bool _enabled = false;
  int _generation = 0;
  Future<bool>? _enabling;
  Future<bool> _cleanup = Future.value(true);

  FCMService({
    FirebaseFirestore? firestore,
    FirebaseAuth? auth,
    FirebaseMessaging? messaging,
  }) : _firestore = firestore ?? FirebaseFirestore.instance,
       _auth = auth ?? FirebaseAuth.instance,
       _messaging = messaging ?? FirebaseMessaging.instance {
    _authSubscription = _auth.authStateChanges().listen((user) {
      if (_owner != null && user?.uid != _owner) unawaited(disable());
    });
  }

  bool _current(String uid, int generation) =>
      generation == _generation &&
      _owner == uid &&
      _auth.currentUser?.uid == uid;

  Future<bool> enable(String? userId) {
    if (userId == null || userId.isEmpty || _auth.currentUser?.uid != userId) {
      return Future.value(false);
    }
    if (_owner == userId && _enabled) return Future.value(true);
    if (_owner == userId && _enabling != null) return _enabling!;
    if (_owner != null && _owner != userId) unawaited(disable());
    _owner = userId;
    final generation = ++_generation;
    final pending = _enable(userId, generation);
    _enabling = pending;
    return pending.whenComplete(() {
      if (generation == _generation) _enabling = null;
    });
  }

  Future<bool> _enable(String uid, int generation) async {
    try {
      await _cleanup;
      if (!_current(uid, generation)) return false;
      final settings = await _messaging.requestPermission(
        alert: true,
        badge: true,
        sound: true,
      );
      if (!_current(uid, generation) ||
          settings.authorizationStatus != AuthorizationStatus.authorized) {
        return false;
      }
      final token = await _messaging.getToken(
        vapidKey: kIsWeb
            ? 'BKKdEbWfwC8UBq9EoXZePzc9z1mNtt_cl2ohtbDnsaLe-501J0ZbMOlo_ZQQfRJWo1WJn2MM7Ur5FZfLZ89YYq8'
            : null,
      );
      if (!_current(uid, generation) || token == null || token.isEmpty) {
        return false;
      }
      _token = token;
      if (!await _save(uid, token, generation)) return false;
      await _tokenRefreshSubscription?.cancel();
      if (!_current(uid, generation)) return false;
      _tokenRefreshSubscription = _messaging.onTokenRefresh.listen((
        next,
      ) async {
        if (!_current(uid, generation) || next.isEmpty) return;
        final previous = _token;
        _token = next;
        if (await _save(uid, next, generation) &&
            previous != null &&
            previous != next &&
            _current(uid, generation)) {
          try {
            await _firestore.collection('fcm_tokens').doc(previous).delete();
          } catch (_) {
            /* Server retires expired tokens. */
          }
        }
      });
      _enabled = true;
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<bool> _save(String uid, String token, int generation) async {
    if (!_current(uid, generation)) return false;
    try {
      await _firestore
          .collection('fcm_tokens')
          .doc(token)
          .set({
            'token': token,
            'userId': uid,
            'deviceType': kIsWeb
                ? 'web'
                : (defaultTargetPlatform == TargetPlatform.iOS
                      ? 'ios'
                      : 'android'),
            'updatedAt': FieldValue.serverTimestamp(),
          })
          .timeout(const Duration(seconds: 15));
      return _current(uid, generation);
    } catch (_) {
      return false;
    }
  }

  Future<bool> disable() {
    final owner = _owner;
    final token = _token;
    ++_generation;
    _owner = null;
    _token = null;
    _enabled = false;
    _enabling = null;
    final subscription = _tokenRefreshSubscription;
    _tokenRefreshSubscription = null;
    _cleanup = _cleanup.then((_) async {
      await subscription?.cancel();
      if (token != null && _auth.currentUser?.uid == owner) {
        try {
          await _firestore
              .collection('fcm_tokens')
              .doc(token)
              .delete()
              .timeout(const Duration(seconds: 10));
        } catch (_) {
          /* Revoking the browser token still prevents future delivery. */
        }
      }
      try {
        await _messaging.deleteToken().timeout(const Duration(seconds: 10));
        return true;
      } catch (_) {
        return false;
      }
    });
    return _cleanup;
  }

  void dispose() {
    _authSubscription?.cancel();
    unawaited(disable());
  }
}
