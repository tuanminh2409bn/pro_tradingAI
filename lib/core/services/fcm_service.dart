import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';

class FCMService {
  final FirebaseFirestore _firestore;
  StreamSubscription<String>? _tokenRefreshSubscription;
  static String? _initializedUserId;

  FCMService({FirebaseFirestore? firestore})
    : _firestore = firestore ?? FirebaseFirestore.instance;

  Future<bool> enable(String? userId) async {
    if (userId == null || userId.isEmpty) return false;
    if (_initializedUserId == userId) return true;
    _initializedUserId = userId;

    try {
      // 1. Request notification permission from browser/device
      NotificationSettings settings = await FirebaseMessaging.instance
          .requestPermission(
            alert: true,
            announcement: false,
            badge: true,
            carPlay: false,
            criticalAlert: false,
            provisional: false,
            sound: true,
          );

      if (settings.authorizationStatus == AuthorizationStatus.authorized) {
        // 2. Fetch the FCM token
        String? token;
        try {
          if (kIsWeb) {
            // Note: On Web, Google requires a VAPID public key.
            // If the Firebase project does not have one, you can configure it under settings.
            token = await FirebaseMessaging.instance.getToken(
              vapidKey:
                  'BKKdEbWfwC8UBq9EoXZePzc9z1mNtt_cl2ohtbDnsaLe-501J0ZbMOlo_ZQQfRJWo1WJn2MM7Ur5FZfLZ89YYq8',
            );
          } else {
            token = await FirebaseMessaging.instance.getToken();
          }
        } catch (_) {
          try {
            token = await FirebaseMessaging.instance.getToken();
          } catch (_) {}
        }

        if (token == null || token.isEmpty) {
          _initializedUserId = null;
          return false;
        }
        if (!await _saveTokenToFirestore(userId, token)) {
          _initializedUserId = null;
          return false;
        }

        // 3. Monitor token refreshes
        _tokenRefreshSubscription?.cancel();
        _tokenRefreshSubscription = FirebaseMessaging.instance.onTokenRefresh
            .listen((newToken) {
              _saveTokenToFirestore(userId, newToken);
            });

        // 4. Handle foreground notifications
        FirebaseMessaging.onMessage.listen((RemoteMessage _) {
          // Here foreground notifications can be processed if necessary
        });
        return true;
      }
    } catch (_) {
      _initializedUserId = null;
      return false;
    }
    _initializedUserId = null;
    return false;
  }

  Future<bool> _saveTokenToFirestore(String userId, String token) async {
    try {
      final deviceType = kIsWeb
          ? 'web'
          : (defaultTargetPlatform == TargetPlatform.iOS ? 'ios' : 'android');
      await _firestore.collection('fcm_tokens').doc(token).set({
        'token': token,
        'userId': userId,
        'deviceType': deviceType,
        'updatedAt': FieldValue.serverTimestamp(),
      });
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<bool> disable() async {
    try {
      final token = await FirebaseMessaging.instance.getToken();
      if (token != null && token.isNotEmpty) {
        await _firestore.collection('fcm_tokens').doc(token).delete();
      }
      await FirebaseMessaging.instance.deleteToken();
      await _tokenRefreshSubscription?.cancel();
      _tokenRefreshSubscription = null;
      _initializedUserId = null;
      return true;
    } catch (_) {
      return false;
    }
  }

  void dispose() {
    _tokenRefreshSubscription?.cancel();
  }
}
