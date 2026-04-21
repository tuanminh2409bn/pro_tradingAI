import 'package:equatable/equatable.dart';
import 'package:firebase_auth/firebase_auth.dart';

enum AuthStatus { authenticated, unauthenticated, loading }

class AuthState extends Equatable {
  final AuthStatus status;
  final User? user;
  final String? errorMessage;

  const AuthState._({
    this.status = AuthStatus.loading,
    this.user,
    this.errorMessage,
  });

  const AuthState.authenticated(User user)
      : this._(status: AuthStatus.authenticated, user: user);

  const AuthState.unauthenticated({String? errorMessage})
      : this._(status: AuthStatus.unauthenticated, errorMessage: errorMessage);

  const AuthState.loading() : this._(status: AuthStatus.loading);

  @override
  List<Object?> get props => [status, user, errorMessage];
}
