import 'package:equatable/equatable.dart';

abstract class AuthEvent extends Equatable {
  const AuthEvent();

  @override
  List<Object?> get props => [];
}

class AuthSessionCheckRequested extends AuthEvent {
  const AuthSessionCheckRequested();
}

class AuthLoginRequested extends AuthEvent {
  const AuthLoginRequested({required this.email, required this.password});

  final String email;
  final String password;

  @override
  List<Object?> get props => [email, password];
}

class AuthGoogleRequested extends AuthEvent {
  const AuthGoogleRequested();
}

class AuthSignupRequested extends AuthEvent {
  const AuthSignupRequested({
    required this.name,
    required this.email,
    required this.password,
  });

  final String name;
  final String email;
  final String password;

  @override
  List<Object?> get props => [name, email, password];
}

class AuthSignupOtpVerificationRequested extends AuthEvent {
  const AuthSignupOtpVerificationRequested({
    required this.signupToken,
    required this.otp,
  });

  final String signupToken;
  final String otp;

  @override
  List<Object?> get props => [signupToken, otp];
}

class AuthSignupOtpResendRequested extends AuthEvent {
  const AuthSignupOtpResendRequested({required this.signupToken});

  final String signupToken;

  @override
  List<Object?> get props => [signupToken];
}

class AuthLogoutRequested extends AuthEvent {
  const AuthLogoutRequested();
}
