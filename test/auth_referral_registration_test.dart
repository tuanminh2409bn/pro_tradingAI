import 'dart:async';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:protrading_ai/data/models/referral_models.dart';
import 'package:protrading_ai/data/repositories/auth_repository.dart';
import 'package:protrading_ai/data/repositories/profile_repository.dart';
import 'package:protrading_ai/data/repositories/referral_repository.dart';
import 'package:protrading_ai/features/auth/bloc/auth_bloc.dart';
import 'package:protrading_ai/features/auth/bloc/auth_event.dart';
import 'package:protrading_ai/features/auth/bloc/auth_state.dart';

class _User extends Fake implements User {
  final String id;
  _User(this.id);
  @override
  String get uid => id;
}

class _Auth extends Fake implements AuthRepository {
  final users = StreamController<User?>.broadcast();
  @override
  Stream<User?> get user => users.stream;
}

class _Profile extends Fake implements ProfileRepository {
  @override
  Future<void> ensureProfileExists(String uid) async {}
}

class _Referral extends Fake implements ReferralRepository {
  final pending = <Completer<ReferralRegistrationStatus>>[];
  @override
  Future<ReferralRegistrationStatus> recordRegistrationReferral(String code) {
    expect(code, 'abcdefghijklmnopqrstuvwx');
    final result = Completer<ReferralRegistrationStatus>();
    pending.add(result);
    return result.future;
  }
}

void main() {
  Future<AuthBloc> start(_Auth auth, _Referral referral) async {
    final bloc = AuthBloc(
      authRepository: auth,
      profileRepository: _Profile(),
      referralRepository: referral,
      signupReferralCode: 'abcdefghijklmnopqrstuvwx',
    );
    addTearDown(() async {
      for (final pending in referral.pending) {
        if (!pending.isCompleted) {
          pending.complete(ReferralRegistrationStatus.restored);
        }
      }
      await bloc.close();
      await auth.users.close();
    });
    auth.users.add(_User('alice'));
    await bloc.stream.firstWhere(
      (state) =>
          state.status == AuthStatus.authenticated &&
          state.registrationReferralPending,
    );
    return bloc;
  }

  test(
    'pending registration is deduplicated and cannot report another UID result',
    () async {
      final auth = _Auth();
      final referral = _Referral();
      final bloc = await start(auth, referral);
      bloc.add(const AuthRegistrationReferralRequested());
      await Future<void>.delayed(Duration.zero);
      expect(referral.pending.length, 1);
      auth.users.add(_User('bob'));
      await bloc.stream.firstWhere(
        (state) =>
            state.user?.uid == 'bob' && state.registrationReferralPending,
      );
      referral.pending.first.complete(ReferralRegistrationStatus.recorded);
      await Future<void>.delayed(Duration.zero);
      expect(bloc.state.user?.uid, 'bob');
      expect(bloc.state.registrationReferralMessageKey, isNull);
      referral.pending.last.complete(ReferralRegistrationStatus.notEligible);
      await bloc.stream.firstWhere(
        (state) => !state.registrationReferralPending,
      );
      expect(
        bloc.state.registrationReferralMessageKey,
        'referral_registration_not_eligible',
      );
      expect(bloc.state.status, AuthStatus.authenticated);
    },
  );
  test(
    'transport failure retains login and can retry without a second identity',
    () async {
      final auth = _Auth();
      final referral = _Referral();
      final bloc = await start(auth, referral);
      referral.pending.single.completeError(StateError('unavailable'));
      await bloc.stream.firstWhere(
        (state) => state.registrationReferralMessageKey != null,
      );
      expect(bloc.state.status, AuthStatus.authenticated);
      expect(bloc.state.user?.uid, 'alice');
      expect(bloc.state.registrationReferralRetryable, isTrue);
      bloc.add(const AuthRegistrationReferralRequested());
      await bloc.stream.firstWhere(
        (state) => state.registrationReferralPending,
      );
      referral.pending.last.complete(ReferralRegistrationStatus.recorded);
      await bloc.stream.firstWhere(
        (state) =>
            state.registrationReferralMessageKey ==
            'referral_registration_recorded',
      );
      expect(bloc.state.registrationReferralRetryable, isFalse);
    },
  );
  test(
    'a repeated auth event for the same UID keeps the pending result',
    () async {
      final auth = _Auth();
      final referral = _Referral();
      final bloc = await start(auth, referral);
      auth.users.add(_User('alice'));
      await Future<void>.delayed(Duration.zero);
      expect(bloc.state.registrationReferralPending, isTrue);
      expect(referral.pending.length, 1);
      referral.pending.single.complete(ReferralRegistrationStatus.recorded);
      await bloc.stream.firstWhere(
        (state) => !state.registrationReferralPending,
      );
      expect(
        bloc.state.registrationReferralMessageKey,
        'referral_registration_recorded',
      );
    },
  );
  for (final status in [401, 408, 425, 429, 503]) {
    test('HTTP $status retains the referral retry action', () async {
      final auth = _Auth();
      final referral = _Referral();
      final bloc = await start(auth, referral);
      referral.pending.single.completeError(
        ReferralRegistrationException(status),
      );
      await bloc.stream.firstWhere(
        (state) => state.registrationReferralMessageKey != null,
      );
      expect(bloc.state.status, AuthStatus.authenticated);
      expect(bloc.state.registrationReferralRetryable, isTrue);
    });
  }
  test(
    'a denied code is terminal and leaves the signed-in user intact',
    () async {
      final auth = _Auth();
      final referral = _Referral();
      final bloc = await start(auth, referral);
      referral.pending.single.completeError(ReferralRegistrationException(409));
      await bloc.stream.firstWhere(
        (state) => state.registrationReferralMessageKey != null,
      );
      expect(
        bloc.state.registrationReferralMessageKey,
        'referral_registration_denied',
      );
      expect(bloc.state.registrationReferralRetryable, isFalse);
      expect(bloc.state.user?.uid, 'alice');
    },
  );
}
