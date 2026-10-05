import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_firestore_platform_interface/cloud_firestore_platform_interface.dart'
    as platform;
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:protrading_ai/core/services/fcm_service.dart';

class _User extends Fake implements User {
  @override
  final String uid;
  _User(this.uid);
}

class _Auth extends Fake implements FirebaseAuth {
  final changes = StreamController<User?>.broadcast();
  User? user = _User('alice');
  @override
  User? get currentUser => user;
  @override
  Stream<User?> authStateChanges() => changes.stream;
  void switchTo(String? uid) {
    user = uid == null ? null : _User(uid);
    changes.add(user);
  }
}

class _Permission extends Fake implements NotificationSettings {
  @override
  final AuthorizationStatus authorizationStatus;
  _Permission(this.authorizationStatus);
}

class _Messaging extends Fake implements FirebaseMessaging {
  final refreshed = StreamController<String>.broadcast();
  Future<NotificationSettings> permission = Future.value(
    _Permission(AuthorizationStatus.authorized),
  );
  int permissions = 0, tokenReads = 0, revocations = 0;
  @override
  Future<NotificationSettings> requestPermission({
    bool alert = true,
    bool announcement = false,
    bool badge = true,
    bool carPlay = false,
    bool criticalAlert = false,
    bool provisional = false,
    bool sound = true,
    bool providesAppNotificationSettings = false,
  }) {
    permissions++;
    return permission;
  }

  @override
  Future<String?> getToken({String? vapidKey}) async {
    tokenReads++;
    return 'fixture-token';
  }

  @override
  Stream<String> get onTokenRefresh => refreshed.stream;
  @override
  Future<void> deleteToken() async {
    revocations++;
  }
}

class _Document extends platform.DocumentReferencePlatform {
  final _Firestore fs;
  _Document(this.fs, String id) : super(fs, 'fcm_tokens/$id');
  @override
  Future<void> set(
    Map<String, dynamic> data, [
    platform.SetOptions? options,
  ]) async {
    fs.writes.add({...data});
  }

  @override
  Future<void> delete() async {
    fs.deleted.add(path.split('/').last);
  }
}

class _Collection extends platform.CollectionReferencePlatform {
  final _Firestore fs;
  _Collection(this.fs) : super(fs, 'fcm_tokens');
  @override
  platform.DocumentReferencePlatform doc([String? path]) =>
      _Document(fs, path!);
}

class _App extends Fake implements FirebaseApp {
  @override
  final String name;
  _App(this.name);
}

class _Firestore extends platform.FirebaseFirestorePlatform {
  static int sequence = 0;
  _Firestore() : super(appInstance: _App('fcm-qa-${++sequence}')) {
    platform.FirebaseFirestorePlatform.instance = this;
  }
  final writes = <Map<String, dynamic>>[];
  final deleted = <String>[];
  FirebaseFirestore get instance => FirebaseFirestore.instanceFor(app: app);
  @override
  platform.FirebaseFirestorePlatform delegateFor({
    required FirebaseApp app,
    required String databaseId,
  }) => this;
  @override
  platform.CollectionReferencePlatform collection(String path) =>
      _Collection(this);
}

Future<void> _flush() async {
  for (var i = 0; i < 4; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

void main() {
  test(
    'same-owner enable is single-flight; rotation retires only the prior token',
    () async {
      final auth = _Auth(), messaging = _Messaging(), fs = _Firestore();
      final permission = Completer<NotificationSettings>();
      messaging.permission = permission.future;
      final service = FCMService(
        auth: auth,
        firestore: fs.instance,
        messaging: messaging,
      );
      final first = service.enable('alice'), second = service.enable('alice');
      await _flush();
      expect(messaging.permissions, 1);
      permission.complete(_Permission(AuthorizationStatus.authorized));
      expect(await first, isTrue);
      expect(await second, isTrue);
      messaging.refreshed.add('rotated-fixture');
      await _flush();
      expect(fs.writes.map((record) => record['userId']), ['alice', 'alice']);
      expect(fs.deleted, ['fixture-token']);
      expect(await service.disable(), isTrue);
      expect(fs.deleted.last, 'rotated-fixture');
      messaging.refreshed.add('ignored-fixture');
      await _flush();
      expect(fs.writes, hasLength(2));
      service.dispose();
      await _flush();
      await auth.changes.close();
      await messaging.refreshed.close();
    },
  );
  test(
    'account switch while permission is pending cannot register the old UID',
    () async {
      final auth = _Auth(), messaging = _Messaging(), fs = _Firestore();
      final permission = Completer<NotificationSettings>();
      messaging.permission = permission.future;
      final service = FCMService(
        auth: auth,
        firestore: fs.instance,
        messaging: messaging,
      );
      final pending = service.enable('alice');
      await _flush();
      auth.switchTo('bob');
      await _flush();
      permission.complete(_Permission(AuthorizationStatus.authorized));
      expect(await pending, isFalse);
      expect(messaging.tokenReads, 0);
      expect(fs.writes, isEmpty);
      expect(await service.enable('bob'), isTrue);
      expect(fs.writes.single['userId'], 'bob');
      auth.switchTo(null);
      await _flush();
      expect(messaging.revocations, greaterThanOrEqualTo(2));
      service.dispose();
      await _flush();
      await auth.changes.close();
      await messaging.refreshed.close();
    },
  );
  test('denied consent and foreign UID never request a token', () async {
    final auth = _Auth(), messaging = _Messaging(), fs = _Firestore();
    messaging.permission = Future.value(
      _Permission(AuthorizationStatus.denied),
    );
    final service = FCMService(
      auth: auth,
      firestore: fs.instance,
      messaging: messaging,
    );
    expect(await service.enable('bob'), isFalse);
    expect(await service.enable('alice'), isFalse);
    expect(messaging.tokenReads, 0);
    expect(fs.writes, isEmpty);
    service.dispose();
    await _flush();
    await auth.changes.close();
    await messaging.refreshed.close();
  });
}
