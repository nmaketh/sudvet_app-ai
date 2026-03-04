import 'package:equatable/equatable.dart';

class SignupOtpChallenge extends Equatable {
  const SignupOtpChallenge({
    required this.signupToken,
    required this.email,
    this.expiresInSeconds,
    this.devOtp,
  });

  final String signupToken;
  final String email;
  final int? expiresInSeconds;
  /// Only present in dev/local mode when SMTP is not configured.
  final String? devOtp;

  @override
  List<Object?> get props => [signupToken, email, expiresInSeconds, devOtp];
}
