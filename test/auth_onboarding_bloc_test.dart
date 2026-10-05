import 'dart:async';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:protrading_ai/data/repositories/auth_repository.dart';
import 'package:protrading_ai/data/repositories/profile_repository.dart';
import 'package:protrading_ai/features/auth/bloc/auth_bloc.dart';
import 'package:protrading_ai/features/auth/bloc/auth_event.dart';
import 'package:protrading_ai/features/auth/bloc/auth_state.dart';

class _User extends Fake implements User {
  @override
  final String uid;
  _User(this.uid);
}

class _Auth extends Fake implements AuthRepository {
  final users = StreamController<User?>.broadcast();
  @override
  Stream<User?> get user => users.stream;
}

class _Profile extends Fake implements ProfileRepository {
  final seeded = <String>[];
  @override
  Future<void> ensureProfileExists(String uid) async => seeded.add(uid);
}

void main() {
  test(
    'dashboard and profile wait for onboarding; repeated event uses one request',
    () async {
      final auth = _Auth();
      final profile = _Profile();
      final pending = Completer<void>();
      var calls = 0;
      final bloc = AuthBloc(
        authRepository: auth,
        profileRepository: profile,
        completeOnboarding: (_) {
          calls++;
          return pending.future;
        },
      );
      auth.users.add(_User('alice'));
      await bloc.stream.firstWhere((s) => s.status == AuthStatus.onboarding);
      auth.users.add(_User('alice'));
      await Future<void>.delayed(Duration.zero);
      expect(calls, 1);
      expect(profile.seeded, isEmpty);
      pending.complete();
      await bloc.stream.firstWhere((s) => s.status == AuthStatus.authenticated);
      await Future<void>.delayed(Duration.zero);
      expect(profile.seeded, ['alice']);
      await bloc.close();
      await auth.users.close();
    },
  );

  test(
    'failure keeps identity for retry without creating another account',
    () async {
      final auth = _Auth();
      final profile = _Profile();
      var calls = 0;
      final bloc = AuthBloc(
        authRepository: auth,
        profileRepository: profile,
        completeOnboarding: (_) async {
          if (++calls == 1) throw StateError('unavailable');
        },
      );
      auth.users.add(_User('alice'));
      await bloc.stream.firstWhere((s) => s.errorMessage != null);
      expect(bloc.state.status, AuthStatus.onboarding);
      expect(bloc.state.user?.uid, 'alice');
      expect(profile.seeded, isEmpty);
      bloc.add(const AuthOnboardingRetryRequested());
      await bloc.stream.firstWhere((s) => s.status == AuthStatus.authenticated);
      expect(calls, 2);
      await bloc.close();
      await auth.users.close();
    },
  );

  test(
    'an old UID completion cannot authenticate or seed after sign out',
    () async {
      final auth = _Auth();
      final profile = _Profile();
      final pending = Completer<void>();
      final bloc = AuthBloc(
        authRepository: auth,
        profileRepository: profile,
        completeOnboarding: (_) => pending.future,
      );
      auth.users.add(_User('alice'));
      await bloc.stream.firstWhere((s) => s.status == AuthStatus.onboarding);
      auth.users.add(null);
      await bloc.stream.firstWhere(
        (s) => s.status == AuthStatus.unauthenticated,
      );
      pending.complete();
      await Future<void>.delayed(Duration.zero);
      expect(bloc.state.user, isNull);
      expect(profile.seeded, isEmpty);
      await bloc.close();
      await auth.users.close();
    },
  );
}
