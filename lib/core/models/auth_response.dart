import 'package:equatable/equatable.dart';

import 'app_user.dart';

class AuthResponse extends Equatable {
  const AuthResponse({
    required this.token,
    required this.user,
    this.refreshToken,
  });

  final String token;
  final AppUser user;
  final String? refreshToken;

  @override
  List<Object?> get props => [token, user, refreshToken];
}
