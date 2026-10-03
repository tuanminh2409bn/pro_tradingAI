import 'dart:async';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../../../data/repositories/auth_repository.dart';
import '../../../data/repositories/profile_repository.dart';
import '../../../data/repositories/referral_repository.dart';
import '../../../data/models/referral_models.dart';
import 'auth_event.dart';
import 'auth_state.dart';

String authFailureKey(Object error) {
  if (error is! FirebaseAuthException) return 'auth_generic_error';
  return switch (error.code) {
    'invalid-credential' ||
    'wrong-password' ||
    'user-not-found' ||
    'invalid-email' => 'auth_invalid_credentials',
    'email-already-in-use' => 'auth_email_in_use',
    'weak-password' => 'auth_weak_password',
    'too-many-requests' => 'auth_too_many_requests',
    'popup-closed-by-user' ||
    'canceled-popup-request' ||
    'popup-blocked' => 'auth_popup_cancelled',
    _ => 'auth_generic_error',
  };
}

class AuthBloc extends Bloc<AuthEvent, AuthState> {
  final AuthRepository _authRepository;
  final ProfileRepository _profileRepository;
  final ReferralRepository? _referralRepository;
  final String? _signupReferralCode;
  final Set<String> _registrationPending = {};
  final Set<String> _registrationAttempted = {};
  int _identityGeneration = 0;
  int _referralFeedbackSequence = 0;
  StreamSubscription? _userSubscription;

  AuthBloc({
    required AuthRepository authRepository,
    required ProfileRepository profileRepository,
    ReferralRepository? referralRepository,
    String? signupReferralCode,
  }) : _authRepository = authRepository,
       _profileRepository = profileRepository,
       _referralRepository = referralRepository,
       _signupReferralCode = signupReferralCode,
       super(const AuthState.loading()) {
    on<AuthUserChanged>(_onUserChanged);
    on<AuthLogoutRequested>(_onLogoutRequested);
    on<AuthGoogleSignInRequested>(_onGoogleSignInRequested);
    on<AuthLoginRequested>(_onLoginRequested);
    on<AuthRegisterRequested>(_onRegisterRequested);
    on<AuthRegistrationReferralRequested>(_onRegistrationReferral);

    _userSubscription = _authRepository.user.listen(
      (user) => add(AuthUserChanged(user)),
    );
  }

  Future<void> _onUserChanged(
    AuthUserChanged event,
    Emitter<AuthState> emit,
  ) async {
    final previous = state;
    final sameUser =
        event.user != null &&
        previous.status == AuthStatus.authenticated &&
        previous.user?.uid == event.user!.uid;
    if (!sameUser) ++_identityGeneration;
    if (event.user != null) {
      emit(
        AuthState.authenticated(
          event.user!,
          registrationReferralPending:
              sameUser && previous.registrationReferralPending,
          registrationReferralRetryable:
              sameUser && previous.registrationReferralRetryable,
          registrationReferralMessageKey: sameUser
              ? previous.registrationReferralMessageKey
              : null,
          registrationReferralMessageNonce: sameUser
              ? previous.registrationReferralMessageNonce
              : 0,
        ),
      );
      if (_signupReferralCode != null && _referralRepository != null) {
        add(const AuthRegistrationReferralRequested());
      }
      // Tự động seed profile + cập nhật lastSeen sau khi login
      try {
        await _profileRepository.ensureProfileExists(event.user!.uid);
      } catch (e) {
        // Không block auth flow nếu seeding thất bại
      }
    } else {
      _registrationAttempted.clear();
      emit(const AuthState.unauthenticated());
    }
  }

  Future<void> _onRegistrationReferral(
    AuthRegistrationReferralRequested event,
    Emitter<AuthState> emit,
  ) async {
    final user = state.user;
    final repository = _referralRepository;
    final code = _signupReferralCode;
    if (state.status != AuthStatus.authenticated ||
        user == null ||
        repository == null ||
        code == null) {
      return;
    }
    final key = '${user.uid}:$code';
    if (_registrationPending.contains(key) ||
        _registrationAttempted.contains(key)) {
      return;
    }
    final generation = _identityGeneration;
    _registrationPending.add(key);
    _registrationAttempted.add(key);
    emit(AuthState.authenticated(user, registrationReferralPending: true));
    String? message;
    bool retryable = false;
    try {
      final status = await repository.recordRegistrationReferral(code);
      message = switch (status) {
        ReferralRegistrationStatus.recorded => 'referral_registration_recorded',
        ReferralRegistrationStatus.restored => null,
        ReferralRegistrationStatus.notEligible =>
          'referral_registration_not_eligible',
      };
    } catch (error) {
      final terminal =
          error is ReferralRegistrationException &&
          error.statusCode >= 400 &&
          error.statusCode < 500 &&
          !{401, 408, 425, 429}.contains(error.statusCode);
      retryable = !terminal;
      if (retryable) _registrationAttempted.remove(key);
      message = terminal
          ? 'referral_registration_denied'
          : 'referral_registration_unavailable';
    } finally {
      _registrationPending.remove(key);
      if (!isClosed &&
          generation != _identityGeneration &&
          state.user?.uid == user.uid &&
          state.status == AuthStatus.authenticated &&
          !_registrationAttempted.contains(key)) {
        add(const AuthRegistrationReferralRequested());
      }
    }
    if (emit.isDone ||
        generation != _identityGeneration ||
        state.status != AuthStatus.authenticated ||
        state.user?.uid != user.uid) {
      return;
    }
    emit(
      AuthState.authenticated(
        user,
        registrationReferralMessageKey: message,
        registrationReferralRetryable: retryable,
        registrationReferralMessageNonce: ++_referralFeedbackSequence,
      ),
    );
  }

  Future<void> _onLogoutRequested(
    AuthLogoutRequested event,
    Emitter<AuthState> emit,
  ) async {
    await _authRepository.logOut();
  }

  Future<void> _onGoogleSignInRequested(
    AuthGoogleSignInRequested event,
    Emitter<AuthState> emit,
  ) async {
    try {
      emit(const AuthState.loading());
      await _authRepository.signInWithGoogle();
    } catch (error) {
      emit(AuthState.unauthenticated(errorMessage: authFailureKey(error)));
    }
  }

  Future<void> _onLoginRequested(
    AuthLoginRequested event,
    Emitter<AuthState> emit,
  ) async {
    try {
      emit(const AuthState.loading());
      await _authRepository.logInWithEmailAndPassword(
        email: event.email,
        password: event.password,
      );
    } catch (error) {
      emit(AuthState.unauthenticated(errorMessage: authFailureKey(error)));
    }
  }

  Future<void> _onRegisterRequested(
    AuthRegisterRequested event,
    Emitter<AuthState> emit,
  ) async {
    try {
      emit(const AuthState.loading());
      await _authRepository.signUp(
        email: event.email,
        password: event.password,
      );
    } catch (error) {
      emit(AuthState.unauthenticated(errorMessage: authFailureKey(error)));
    }
  }

  @override
  Future<void> close() {
    _userSubscription?.cancel();
    return super.close();
  }
}
