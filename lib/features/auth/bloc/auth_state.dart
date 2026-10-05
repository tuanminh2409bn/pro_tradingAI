import 'package:equatable/equatable.dart';
import 'package:firebase_auth/firebase_auth.dart';

enum AuthStatus { authenticated, unauthenticated, loading, onboarding }

class AuthState extends Equatable {
  final AuthStatus status;
  final User? user;
  final String? errorMessage;
  final bool registrationReferralPending;
  final bool registrationReferralRetryable;
  final String? registrationReferralMessageKey;
  final int registrationReferralMessageNonce;

  const AuthState._({
    this.status = AuthStatus.loading,
    this.user,
    this.errorMessage,
    this.registrationReferralPending = false,
    this.registrationReferralRetryable = false,
    this.registrationReferralMessageKey,
    this.registrationReferralMessageNonce = 0,
  });

  const AuthState.authenticated(
    User user, {
    bool registrationReferralPending = false,
    bool registrationReferralRetryable = false,
    String? registrationReferralMessageKey,
    int registrationReferralMessageNonce = 0,
  }) : this._(
         status: AuthStatus.authenticated,
         user: user,
         registrationReferralPending: registrationReferralPending,
         registrationReferralRetryable: registrationReferralRetryable,
         registrationReferralMessageKey: registrationReferralMessageKey,
         registrationReferralMessageNonce: registrationReferralMessageNonce,
       );

  const AuthState.unauthenticated({String? errorMessage})
    : this._(status: AuthStatus.unauthenticated, errorMessage: errorMessage);

  const AuthState.loading() : this._(status: AuthStatus.loading);

  const AuthState.onboarding(User user, {String? errorMessage})
    : this._(
        status: AuthStatus.onboarding,
        user: user,
        errorMessage: errorMessage,
      );

  @override
  List<Object?> get props => [
    status,
    user,
    errorMessage,
    registrationReferralPending,
    registrationReferralRetryable,
    registrationReferralMessageKey,
    registrationReferralMessageNonce,
  ];
}
