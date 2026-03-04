import 'package:equatable/equatable.dart';

class ResetOtpChallenge extends Equatable {
  const ResetOtpChallenge({
    required this.resetToken,
    required this.email,
    this.expiresInSeconds,
  });

  final String resetToken;
  final String email;
  final int? expiresInSeconds;

  @override
  List<Object?> get props => [resetToken, email, expiresInSeconds];
}
