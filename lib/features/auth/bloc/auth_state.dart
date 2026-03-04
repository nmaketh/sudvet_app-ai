import 'package:equatable/equatable.dart';

import '../../../core/models/app_user.dart';

abstract class AuthState extends Equatable {
  const AuthState();

  @override
  List<Object?> get props => [];
}

class AuthUnknown extends AuthState {
  const AuthUnknown();
}

class AuthUnauthenticated extends AuthState {
  const AuthUnauthenticated();
}

class AuthAuthenticating extends AuthState {
  const AuthAuthenticating({this.checkingSession = false});

  final bool checkingSession;

  @override
  List<Object?> get props => [checkingSession];
}

class AuthAuthenticated extends AuthState {
  const AuthAuthenticated(this.user);

  final AppUser user;

  @override
  List<Object?> get props => [user];
}

class AuthFailure extends AuthState {
  const AuthFailure(this.message);

  final String message;

  @override
  List<Object?> get props => [message];
}

class AuthOtpRequired extends AuthState {
  const AuthOtpRequired({
    required this.signupToken,
    required this.email,
    this.message,
    this.devOtp,
  });

  final String signupToken;
  final String email;
  final String? message;
  final String? devOtp;

  @override
  List<Object?> get props => [signupToken, email, message, devOtp];
}
