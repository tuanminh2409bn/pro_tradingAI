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

  Future<void> initialize(String? userId) async {
    if (userId == null || userId.isEmpty) return;
    if (_initializedUserId == userId) return; // Prevent double initialization
    _initializedUserId = userId;

    try {
      // 1. Request notification permission from browser/device
      NotificationSettings settings = await FirebaseMessaging.instance.requestPermission(
        alert: true,
        announcement: false,
        badge: true,
        carPlay: false,
        criticalAlert: false,
        provisional: false,
        sound: true,
      );

      if (settings.authorizationStatus == AuthorizationStatus.authorized) {
        if (kDebugMode) {
          print('FCM: Notification permission granted');
        }

        // 2. Fetch the FCM token
        String? token;
        try {
          if (kIsWeb) {
            // Note: On Web, Google requires a VAPID public key.
            // If the Firebase project does not have one, you can configure it under settings.
            token = await FirebaseMessaging.instance.getToken(
              vapidKey: 'BKKdEbWfwC8UBq9EoXZePzc9z1mNtt_cl2ohtbDnsaLe-501J0ZbMOlo_ZQQfRJWo1WJn2MM7Ur5FZfLZ89YYq8',
            );
          } else {
            token = await FirebaseMessaging.instance.getToken();
          }
        } catch (e) {
          if (kDebugMode) {
            print('FCM: VAPID Key error or token fetch failed, attempting default getToken: $e');
          }
          try {
            token = await FirebaseMessaging.instance.getToken();
          } catch (e2) {
            if (kDebugMode) {
              print('FCM: Default getToken failed: $e2');
            }
          }
        }

        if (token != null) {
          await _saveTokenToFirestore(userId, token);
        }

        // 3. Monitor token refreshes
        _tokenRefreshSubscription?.cancel();
        _tokenRefreshSubscription = FirebaseMessaging.instance.onTokenRefresh.listen((newToken) {
          _saveTokenToFirestore(userId, newToken);
        });

        // 4. Handle foreground notifications
        FirebaseMessaging.onMessage.listen((RemoteMessage message) {
          if (kDebugMode) {
            print('FCM: Received foreground notification: ${message.notification?.title}');
          }
          // Here foreground notifications can be processed if necessary
        });
      } else {
        if (kDebugMode) {
          print('FCM: Permission denied or not determined');
        }
      }
    } catch (e) {
      if (kDebugMode) {
        print('FCM: Error initializing FCM service: $e');
      }
    }
  }

  Future<void> _saveTokenToFirestore(String userId, String token) async {
    try {
      final deviceType = kIsWeb ? 'web' : (defaultTargetPlatform == TargetPlatform.iOS ? 'ios' : 'android');
      await _firestore.collection('fcm_tokens').doc(token).set({
        'token': token,
        'userId': userId,
        'deviceType': deviceType,
        'updatedAt': FieldValue.serverTimestamp(),
      });
      if (kDebugMode) {
        print('FCM: Successfully registered FCM Token in Firestore');
      }
    } catch (e) {
      if (kDebugMode) {
        print('FCM: Failed to save FCM Token to Firestore: $e');
      }
    }
  }

  Future<void> removeToken(String token) async {
    try {
      await _firestore.collection('fcm_tokens').doc(token).delete();
    } catch (e) {
      if (kDebugMode) {
        print('FCM: Error removing token: $e');
      }
    }
  }

  void dispose() {
    _tokenRefreshSubscription?.cancel();
  }
}
