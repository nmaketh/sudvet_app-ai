import 'package:shared_preferences/shared_preferences.dart';
import 'package:google_sign_in/google_sign_in.dart';

import '../../../core/api/api_client.dart';
import '../../../core/models/app_user.dart';
import '../../../core/models/auth_response.dart';
import '../../../core/models/reset_otp_challenge.dart';
import '../../../core/models/signup_otp_challenge.dart';

class AuthRepository {
  AuthRepository({required ApiClient apiClient}) : _apiClient = apiClient;

  final ApiClient _apiClient;
  GoogleSignIn? _googleSignIn;

  static const _tokenKey = 'auth_token';
  static const _refreshTokenKey = 'auth_refresh_token';
  static const _nameKey = 'auth_user_name';
  static const _emailKey = 'auth_user_email';
  static const _roleKey = 'auth_user_role';

  Future<AppUser?> restoreSession() async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString(_tokenKey);

    if (token == null || token.isEmpty) {
      return null;
    }

    final name = prefs.getString(_nameKey) ?? 'Farmer';
    final email = prefs.getString(_emailKey) ?? 'user@cattle.ai';
    final role = prefs.getString(_roleKey) ?? '';
    return AppUser(id: 'saved-user', name: name, email: email, role: role);
  }

  Future<AuthResponse> login({
    required String email,
    required String password,
  }) async {
    final response = await _apiClient.login(email: email, password: password);
    await _persist(response);
    return response;
  }

  Future<AuthResponse> loginWithGoogle() async {
    final clientId = const String.fromEnvironment('GOOGLE_CLIENT_ID', defaultValue: '');
    final serverClientId = const String.fromEnvironment(
      'GOOGLE_SERVER_CLIENT_ID',
      defaultValue: '',
    );
    _googleSignIn ??= GoogleSignIn(
      scopes: const ['email', 'profile'],
      clientId: clientId.isEmpty ? null : clientId,
      serverClientId: serverClientId.isEmpty ? null : serverClientId,
    );
    final account = await _googleSignIn!.signIn();
    if (account == null) {
      throw const ApiException('Google sign-in canceled.');
    }
    final auth = await account.authentication;
    final idToken = auth.idToken;
    if (idToken == null || idToken.trim().isEmpty) {
      throw const ApiException(
        'Google sign-in did not return an ID token. Configure Google OAuth for this app first.',
      );
    }
    final response = await _apiClient.loginWithGoogle(
      idToken: idToken,
      email: account.email,
      name: account.displayName,
      clientId: serverClientId.isNotEmpty
          ? serverClientId
          : (clientId.isEmpty ? null : clientId),
    );
    await _persist(response);
    return response;
  }

  Future<AuthResponse> register({
    required String name,
    required String email,
    required String password,
  }) async {
    final response = await _apiClient.register(
      name: name,
      email: email,
      password: password,
    );
    await _persist(response);
    return response;
  }

  Future<SignupOtpChallenge> requestSignupOtp({
    required String name,
    required String email,
    required String password,
  }) {
    return _apiClient.requestSignupOtp(
      name: name,
      email: email,
      password: password,
    );
  }

  Future<void> resendSignupOtp({required String signupToken}) {
    return _apiClient.resendSignupOtp(signupToken: signupToken);
  }

  Future<AuthResponse> verifySignupOtp({
    required String signupToken,
    required String otp,
  }) async {
    final response = await _apiClient.verifySignupOtp(
      signupToken: signupToken,
      otp: otp,
    );
    await _persist(response);
    return response;
  }

  Future<ResetOtpChallenge> requestPasswordResetOtp({
    required String email,
  }) {
    return _apiClient.requestPasswordResetOtp(email: email);
  }

  Future<void> resetPasswordWithOtp({
    required String resetToken,
    required String otp,
    required String newPassword,
  }) {
    return _apiClient.resetPasswordWithOtp(
      resetToken: resetToken,
      otp: otp,
      newPassword: newPassword,
    );
  }

  Future<void> logout() async {
    try {
      await _googleSignIn?.signOut();
    } catch (_) {
      // Ignore Google sign-out failures; local auth tokens are still cleared.
    }
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_tokenKey);
    await prefs.remove(_refreshTokenKey);
    await prefs.remove(_nameKey);
    await prefs.remove(_emailKey);
    await prefs.remove(_roleKey);
  }

  Future<AppUser?> refreshSessionIfPossible() async {
    final prefs = await SharedPreferences.getInstance();
    final refreshToken = prefs.getString(_refreshTokenKey);
    if (refreshToken == null || refreshToken.isEmpty) {
      return null;
    }
    final response = await _apiClient.refreshSession();
    await _persist(response);
    return response.user;
  }

  Future<void> _persist(AuthResponse response) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_tokenKey, response.token);
    if (response.refreshToken != null && response.refreshToken!.isNotEmpty) {
      await prefs.setString(_refreshTokenKey, response.refreshToken!);
    }
    await prefs.setString(_nameKey, response.user.name);
    await prefs.setString(_emailKey, response.user.email);
    if (response.user.role.isNotEmpty) {
      await prefs.setString(_roleKey, response.user.role);
    }
  }
}
