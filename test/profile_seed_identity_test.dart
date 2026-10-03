import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_firestore_platform_interface/cloud_firestore_platform_interface.dart'
    as platform;
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:protrading_ai/data/repositories/profile_repository.dart';

class _User extends Fake implements User {
  @override
  final String uid;
  @override
  final String email;
  _User(this.uid) : email = '$uid@example.test';
  @override
  String get displayName => uid;
  @override
  String? get photoURL => null;
}

class _Auth extends Fake implements FirebaseAuth {
  @override
  User? currentUser = _User('alice');
}

class _App extends Fake implements FirebaseApp {
  @override
  final String name;
  _App(this.name);
}

class _Profiles extends platform.FirebaseFirestorePlatform {
  _Profiles(FirebaseApp app) : super(appInstance: app);
  Map<String, dynamic>? record;
  int version = 0;
  int reads = 0;
  int writes = 0;
  FutureOr<void> Function()? afterRead;

  void replace(Map<String, dynamic> data) {
    record = Map.of(data);
    ++version;
  }

  Future<platform.DocumentSnapshotPlatform> read() async {
    ++reads;
    final snapshot = platform.DocumentSnapshotPlatform(
      this,
      'users/alice',
      record == null ? null : Map.of(record!),
      platform.InternalSnapshotMetadata(
        hasPendingWrites: false,
        isFromCache: false,
      ),
    );
    final callback = afterRead;
    afterRead = null;
    await callback?.call();
    return snapshot;
  }

  @override
  platform.FirebaseFirestorePlatform delegateFor({
    required FirebaseApp app,
    required String databaseId,
  }) => this;

  @override
  platform.CollectionReferencePlatform collection(String path) {
    expect(path, 'users');
    return _Collection(this);
  }

  @override
  Future<T?> runTransaction<T>(
    platform.TransactionHandler<T> transactionHandler, {
    Duration timeout = const Duration(seconds: 30),
    int maxAttempts = 5,
  }) async {
    for (var attempt = 0; attempt < maxAttempts; ++attempt) {
      final transaction = _Transaction(this);
      final result = await transactionHandler(transaction);
      if (transaction.readVersion != version) continue;
      if (transaction.pending != null) {
        ++writes;
        replace(
          transaction.merge
              ? {...?record, ...transaction.pending!}
              : transaction.pending!,
        );
      }
      return result;
    }
    throw StateError('local test contention exhausted');
  }
}

class _Collection extends platform.CollectionReferencePlatform {
  final _Profiles profiles;
  _Collection(this.profiles) : super(profiles, 'users');
  @override
  platform.DocumentReferencePlatform doc([String? path]) {
    expect(path, 'alice');
    return _Document(profiles);
  }
}

class _Document extends platform.DocumentReferencePlatform {
  final _Profiles profiles;
  _Document(this.profiles) : super(profiles, 'users/alice');
  @override
  Future<platform.DocumentSnapshotPlatform> get([
    platform.GetOptions options = const platform.GetOptions(),
  ]) => profiles.read();
  @override
  Future<void> set(
    Map<String, dynamic> data, [
    platform.SetOptions? options,
  ]) async {
    ++profiles.writes;
    profiles.replace(data);
  }

  @override
  Future<void> update(Map<platform.FieldPath, dynamic> data) async {
    ++profiles.writes;
    profiles.replace({...?profiles.record, ..._fields(data)});
  }
}

Map<String, dynamic> _fields(Map<platform.FieldPath, dynamic> data) => {
  for (final field in data.entries) field.key.components.single: field.value,
};

class _Transaction extends platform.TransactionPlatform {
  final _Profiles profiles;
  late int readVersion;
  Map<String, dynamic>? pending;
  bool merge = false;
  _Transaction(this.profiles);
  @override
  Future<platform.DocumentSnapshotPlatform> get(String documentPath) async {
    expect(documentPath, 'users/alice');
    readVersion = profiles.version;
    return profiles.read();
  }

  @override
  platform.TransactionPlatform set(
    String documentPath,
    Map<String, dynamic> data, [
    platform.SetOptions? options,
  ]) {
    expect(documentPath, 'users/alice');
    pending = Map.of(data);
    return this;
  }

  @override
  platform.TransactionPlatform update(
    String documentPath,
    Map<platform.FieldPath, dynamic> data,
  ) {
    expect(documentPath, 'users/alice');
    merge = true;
    pending = _fields(data);
    return this;
  }
}

void main() {
  late _Auth auth;
  late _Profiles profiles;
  late ProfileRepository repository;
  var appSequence = 0;
  setUp(() {
    auth = _Auth();
    profiles = _Profiles(_App('profile-seed-${++appSequence}'));
    platform.FirebaseFirestorePlatform.instance = profiles;
    repository = ProfileRepository(
      auth: auth,
      firestore: FirebaseFirestore.instanceFor(app: profiles.app),
    );
  });

  test('another signed-in UID cannot seed the requested profile', () async {
    auth.currentUser = _User('bob');
    await expectLater(
      repository.ensureProfileExists('alice'),
      throwsStateError,
    );
    expect(profiles.reads, 0);
    expect(profiles.writes, 0);
  });

  test('anonymous session cannot seed a profile', () async {
    auth.currentUser = null;
    await expectLater(
      repository.ensureProfileExists('alice'),
      throwsStateError,
    );
    expect(profiles.reads, 0);
    expect(profiles.writes, 0);
  });

  for (final existing in [false, true]) {
    test(
      'identity change during read cannot write, existing=$existing',
      () async {
        if (existing) profiles.replace({'username': 'alice'});
        profiles.afterRead = () {
          auth.currentUser = _User('bob');
        };
        await expectLater(
          repository.ensureProfileExists('alice'),
          throwsStateError,
        );
        expect(profiles.writes, 0);
        expect(profiles.record?['email'], isNull);
      },
    );
  }

  test('concurrent profile creation preserves server-owned fields', () async {
    final authoritative = {
      'tier': 'VIP',
      'brokerLinked': true,
      'totalTrades': 42,
      'winRate': 62.5,
      'rank': 7,
      'username': 'existing',
    };
    profiles.afterRead = () {
      profiles.replace(authoritative);
    };
    await repository.ensureProfileExists('alice');
    expect(
      profiles.record,
      containsPair('lastSeen', isA<platform.FieldValuePlatform>()),
    );
    for (final field in authoritative.entries) {
      expect(profiles.record, containsPair(field.key, field.value));
    }
    expect(profiles.record?['createdAt'], isNull);
    expect(profiles.writes, 1);
  });

  test('new owner profile uses only that captured Auth identity', () async {
    await repository.ensureProfileExists('alice');
    expect(profiles.record, containsPair('email', 'alice@example.test'));
    expect(profiles.record, containsPair('username', 'alice'));
    expect(profiles.record, containsPair('tier', 'FREE'));
    expect(profiles.record, containsPair('brokerLinked', false));
    expect(
      profiles.record,
      containsPair('createdAt', isA<platform.FieldValuePlatform>()),
    );
    expect(profiles.writes, 1);
  });

  test('existing profile only refreshes lastSeen', () async {
    profiles.replace({'username': 'custom-name', 'brokerLinked': true});
    await repository.ensureProfileExists('alice');
    expect(profiles.record, {
      'username': 'custom-name',
      'brokerLinked': true,
      'lastSeen': isA<platform.FieldValuePlatform>(),
    });
    expect(profiles.writes, 1);
  });
}
