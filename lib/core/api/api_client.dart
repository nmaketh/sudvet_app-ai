import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'base_url_resolver.dart';
import 'session_events.dart' as session;
import '../models/app_user.dart';
import '../models/auth_response.dart';
import '../models/reset_otp_challenge.dart';
import '../models/signup_otp_challenge.dart';

class ApiException implements Exception {
  const ApiException(this.message);

  final String message;

  @override
  String toString() => message;
}

class ApiClient {
  ApiClient({http.Client? httpClient}) : _http = httpClient ?? http.Client();

  final http.Client _http;
  static const _authTokenKey = 'auth_token';
  static const _refreshTokenKey = 'auth_refresh_token';
  static const _requestTimeout = Duration(seconds: 35);
  static const _healthTimeout = Duration(seconds: 12);

  Future<AuthResponse> login({
    required String email,
    required String password,
  }) async {
    final normalizedEmail = email.trim().toLowerCase();
    final baseUrl = await _configuredBaseUrl();

    if (baseUrl.isEmpty) {
      throw ApiException(_serverUnavailableMessage());
    }
    return _loginRemote(baseUrl: baseUrl, email: normalizedEmail, password: password);
  }

  Future<AuthResponse> loginWithGoogle({
    required String idToken,
    required String email,
    String? name,
    String? clientId,
  }) async {
    final baseUrl = await _configuredBaseUrl();
    if (baseUrl.isEmpty) {
      throw ApiException(_serverUnavailableMessage());
    }
    final response = await _postFirstSuccessful(
      baseUrl: baseUrl,
      paths: const ['/auth/google', '/google'],
      body: {
        'idToken': idToken,
        'email': email.trim().toLowerCase(),
        'name': name?.trim(),
        'clientId': (clientId == null || clientId.trim().isEmpty) ? null : clientId.trim(),
      },
    );
    return _authFromJson(
      response,
      fallbackEmail: email.trim().toLowerCase(),
      fallbackName: (name == null || name.trim().isEmpty) ? 'Field User' : name.trim(),
    );
  }

  Future<AuthResponse> register({
    required String name,
    required String email,
    required String password,
  }) async {
    final challenge = await requestSignupOtp(
      name: name,
      email: email,
      password: password,
    );
    throw ApiException(
      'OTP verification required for ${challenge.email}.',
    );
  }

  Future<SignupOtpChallenge> requestSignupOtp({
    required String name,
    required String email,
    required String password,
  }) async {
    final normalizedEmail = email.trim().toLowerCase();
    final baseUrl = await _configuredBaseUrl();

    if (baseUrl.isEmpty) {
      throw ApiException(_serverUnavailableMessage());
    }

    final response = await _registerRemote(
      baseUrl: baseUrl,
      name: name.trim(),
      email: normalizedEmail,
      password: password,
    );
    final signupToken = response['signupToken']?.toString().trim();
    if (signupToken == null || signupToken.isEmpty) {
      throw const ApiException('Signup OTP token missing in server response.');
    }
    return SignupOtpChallenge(
      signupToken: signupToken,
      email: normalizedEmail,
      expiresInSeconds: response['expiresInSeconds'] is num
          ? (response['expiresInSeconds'] as num).toInt()
          : int.tryParse(response['expiresInSeconds']?.toString() ?? ''),
      devOtp: response['devOtp']?.toString().trim().isNotEmpty == true
          ? response['devOtp']!.toString().trim()
          : null,
    );
  }

  Future<void> resendSignupOtp({required String signupToken}) async {
    final baseUrl = await _configuredBaseUrl();
    if (baseUrl.isEmpty) {
      throw ApiException(_serverUnavailableMessage());
    }
    await _postFirstSuccessful(
      baseUrl: baseUrl,
      paths: const ['/auth/signup/resend', '/signup/resend'],
      body: {'signupToken': signupToken},
    );
  }

  Future<AuthResponse> verifySignupOtp({
    required String signupToken,
    required String otp,
  }) async {
    final baseUrl = await _configuredBaseUrl();
    if (baseUrl.isEmpty) {
      throw ApiException(_serverUnavailableMessage());
    }
    final response = await _postFirstSuccessful(
      baseUrl: baseUrl,
      paths: const ['/auth/signup/verify', '/signup/verify'],
      body: {'signupToken': signupToken, 'otp': otp.trim()},
    );
    return _authFromJson(response, fallbackEmail: 'user@cattle.ai');
  }

  Future<ResetOtpChallenge> requestPasswordResetOtp({
    required String email,
  }) async {
    final normalizedEmail = email.trim().toLowerCase();
    final baseUrl = await _configuredBaseUrl();
    if (baseUrl.isEmpty) {
      throw ApiException(_serverUnavailableMessage());
    }

    final response = await _postFirstSuccessful(
      baseUrl: baseUrl,
      paths: const ['/auth/forgot-password', '/forgot-password'],
      body: {'email': normalizedEmail},
    );
    final resetToken = response['resetToken']?.toString().trim();
    if (resetToken == null || resetToken.isEmpty) {
      throw const ApiException('Reset token missing in server response.');
    }
    return ResetOtpChallenge(
      resetToken: resetToken,
      email: normalizedEmail,
      expiresInSeconds: response['expiresInSeconds'] is num
          ? (response['expiresInSeconds'] as num).toInt()
          : int.tryParse(response['expiresInSeconds']?.toString() ?? ''),
    );
  }

  Future<void> resetPasswordWithOtp({
    required String resetToken,
    required String otp,
    required String newPassword,
  }) async {
    final baseUrl = await _configuredBaseUrl();
    if (baseUrl.isEmpty) {
      throw ApiException(_serverUnavailableMessage());
    }

    await _postFirstSuccessful(
      baseUrl: baseUrl,
      paths: const ['/auth/reset-password', '/reset-password'],
      body: {
        'resetToken': resetToken,
        'otp': otp.trim(),
        'newPassword': newPassword,
      },
    );
  }

  Future<AuthResponse> refreshSession() async {
    final baseUrl = await _configuredBaseUrl();
    if (baseUrl.isEmpty) {
      throw ApiException(_serverUnavailableMessage());
    }
    final refreshToken = await _savedRefreshToken();
    if (refreshToken == null || refreshToken.isEmpty) {
      throw const ApiException('No refresh token available. Please login again.');
    }

    final response = await _postFirstSuccessful(
      baseUrl: baseUrl,
      paths: const ['/auth/refresh', '/refresh'],
      body: {'refreshToken': refreshToken, 'refresh_token': refreshToken},
    );
    return _authFromJson(response, fallbackEmail: 'user@cattle.ai');
  }

  Future<Map<String, dynamic>> predict({
    required String baseUrl,
    required Map<String, bool> symptoms,
    double? temperature,
    String? imagePath,
    String? animalId,
    bool allowFallbackOnEmptyBaseUrl = true,
  }) async {
    final normalizedBaseUrl = baseUrl.trim();

    if (normalizedBaseUrl.isEmpty) {
      throw ApiException(_serverUnavailableMessage());
    }

    final uri = Uri.parse(_composeUrl(normalizedBaseUrl, '/predict/full'));
    final request = http.MultipartRequest('POST', uri);
    final authToken = await _savedAuthToken();
    if (authToken != null && authToken.isNotEmpty) {
      request.headers['Authorization'] = 'Bearer $authToken';
    }

    final symptomPayload = <String, dynamic>{
      'symptoms': {
        for (final symptom in symptoms.entries)
          symptom.key: symptom.value ? 1 : 0,
      },
      if (temperature != null) 'temperature': double.parse(temperature.toStringAsFixed(1)),
      if (animalId != null && animalId.trim().isNotEmpty) 'animal_id': animalId,
    };
    request.fields['payload'] = jsonEncode(symptomPayload);

    if (imagePath != null && imagePath.trim().isNotEmpty) {
      try {
        request.files.add(await http.MultipartFile.fromPath('file', imagePath));
      } catch (_) {
        // Keep request valid even if attachment cannot be resolved on this platform.
      }
    }

    try {
      final streamed = await _http.send(request).timeout(_requestTimeout);
      final response = await http.Response.fromStream(streamed);

      if (response.statusCode < 200 || response.statusCode >= 300) {
        if (response.statusCode == 401 || response.statusCode == 403) {
          session.signalSessionExpired();
          throw const ApiException('Session expired. Please log in again.');
        }
        if (response.statusCode == 502 ||
            response.statusCode == 503 ||
            response.statusCode == 504) {
          throw const ApiException(
            'Prediction service is waking up. Retry in a few seconds.',
          );
        }
        throw ApiException('Predict failed (${response.statusCode}).');
      }

      final decoded = jsonDecode(response.body) as Map<String, dynamic>;
      final prediction = (decoded['display_label'] ??
              decoded['final_label'] ??
              decoded['prediction'] ??
              decoded['disease'])
          ?.toString();
      final confidenceRaw =
          decoded['confidence'] ??
          decoded['probability'] ??
          decoded['score'] ??
          decoded['conf'];

      final confidence = confidenceRaw is num
          ? confidenceRaw.toDouble()
          : double.tryParse(confidenceRaw?.toString() ?? '');

      final method = (decoded['method'] ?? decoded['source'] ?? 'Hybrid Model')
          .toString();

      final gradcamPath =
          ((decoded['explain'] is Map<String, dynamic> ? (decoded['explain'] as Map<String, dynamic>)['gradcam_path'] : null) ??
                  decoded['gradcam_path'] ??
                  decoded['gradcam'] ??
                  decoded['cam'])
              ?.toString();

      final recommendations = _extractRecommendations(decoded);

      return {
        'prediction': prediction ?? 'Unknown',
        'confidence': confidence,
        'method': method,
        'gradcamPath': gradcamPath,
        'recommendations': recommendations,
        'raw': decoded,
      };
    } on TimeoutException {
      throw const ApiException(
        'SudVet server timed out. It may be waking up; retry shortly.',
      );
    } on ApiException {
      rethrow;
    } catch (_) {
      throw const ApiException(
        'Unable to reach the SudVet server. The case was saved and kept pending.',
      );
    }
  }

  Future<bool> testConnection({required String baseUrl}) async {
    final normalized = baseUrl.trim();
    if (normalized.isEmpty) {
      return false;
    }

    final uris = [
      Uri.parse(_composeUrl(normalized, '/health')),
      Uri.parse(_composeUrl(normalized, '/docs')),
      Uri.parse(_composeUrl(normalized, '/openapi.json')),
    ];

    for (final uri in uris) {
      try {
        final response = await _http.get(uri).timeout(_healthTimeout);
        if (response.statusCode >= 200 && response.statusCode < 400) {
          return true;
        }
      } catch (_) {
        // Continue with next probe.
      }
    }

    try {
      final predictUri = Uri.parse(_composeUrl(normalized, '/predict/full'));
      final request = http.MultipartRequest('POST', predictUri)
        ..fields['payload'] = jsonEncode({'symptoms': {'fever': 1}});
      final streamed = await _http.send(request).timeout(_healthTimeout);
      final response = await http.Response.fromStream(streamed);
      return response.statusCode < 500;
    } catch (_) {
      return false;
    }
  }

  List<String> _extractRecommendations(Map<String, dynamic> json) {
    final direct = json['recommendations'];
    if (direct is List) {
      return direct.map((entry) => entry.toString()).toList(growable: false);
    }

    final fallback = json['next_steps'];
    if (fallback is List) {
      return fallback.map((entry) => entry.toString()).toList(growable: false);
    }

    return const [];
  }

  String _composeUrl(String baseUrl, String path) {
    final normalizedBase = baseUrl.endsWith('/')
        ? baseUrl.substring(0, baseUrl.length - 1)
        : baseUrl;
    final normalizedPath = path.startsWith('/') ? path : '/$path';
    return '$normalizedBase$normalizedPath';
  }

  Future<String> _configuredBaseUrl() async {
    return BaseUrlResolver.resolve();
  }

  String _serverUnavailableMessage() {
    return 'Unable to reach the SudVet server. Check your internet connection and try again.${BaseUrlResolver.developerHintSuffix()}';
  }

  Future<String?> _savedAuthToken() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_authTokenKey);
  }

  Future<String?> _savedRefreshToken() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_refreshTokenKey);
  }

  Future<AuthResponse> _loginRemote({
    required String baseUrl,
    required String email,
    required String password,
  }) async {
    final body = {'email': email, 'password': password};
    final response = await _postFirstSuccessful(
      baseUrl: baseUrl,
      paths: const ['/auth/login', '/login'],
      body: body,
    );
    return _authFromJson(response, fallbackEmail: email);
  }

  Future<Map<String, dynamic>> _registerRemote({
    required String baseUrl,
    required String name,
    required String email,
    required String password,
  }) async {
    final body = {'name': name, 'email': email, 'password': password};
    return _postFirstSuccessful(
      baseUrl: baseUrl,
      // OTP-only signup: do not fall back to direct /register endpoints.
      paths: const ['/auth/signup', '/signup'],
      body: body,
    );
  }

  Future<Map<String, dynamic>> _postFirstSuccessful({
    required String baseUrl,
    required List<String> paths,
    required Map<String, dynamic> body,
  }) async {
    String? last4xxMessage;
    bool sawUnauthorized = false;
    bool sawTimeout = false;
    bool sawNotFound = false;

    for (final path in paths) {
      final uri = Uri.parse(_composeUrl(baseUrl, path));
      http.Response response;
      try {
        response = await _http
            .post(
              uri,
              headers: const {'Content-Type': 'application/json'},
              body: jsonEncode(body),
            )
            .timeout(_requestTimeout);
      } on TimeoutException {
        sawTimeout = true;
        continue;
      } catch (_) {
        continue;
      }

      if (response.statusCode >= 200 && response.statusCode < 300) {
        final decoded = jsonDecode(response.body);
        if (decoded is Map<String, dynamic>) {
          return decoded;
        }
        throw const ApiException('Invalid response from auth server.');
      }

      final message = _extractErrorMessage(response.body);
      if (response.statusCode == 401 || response.statusCode == 403) {
        sawUnauthorized = true;
        last4xxMessage = message ?? 'Invalid credentials.';
      } else if (response.statusCode == 404) {
        sawNotFound = true;
      } else if (response.statusCode >= 400 && response.statusCode < 500) {
        last4xxMessage = message ?? 'Authentication request failed.';
      } else if (response.statusCode >= 500) {
        // Server error — don't fall through to alternative paths; surface the error.
        throw ApiException(message ?? 'Server error. Please try again.');
      }
    }

    if (last4xxMessage != null) {
      throw ApiException(last4xxMessage);
    }
    if (sawUnauthorized) {
      throw const ApiException('Invalid credentials.');
    }
    if (sawNotFound) {
      throw ApiException(
        'Connected server does not expose SudVet auth routes.${BaseUrlResolver.developerHintSuffix()}',
      );
    }
    if (sawTimeout) {
      throw const ApiException(
        'SudVet server timed out. It may be waking up; retry in a few seconds.',
      );
    }

    throw ApiException(_serverUnavailableMessage());
  }

  String? _extractErrorMessage(String body) {
    if (body.trim().isEmpty) {
      return null;
    }
    try {
      final decoded = jsonDecode(body);
      if (decoded is Map<String, dynamic>) {
        final candidates = [
          decoded['detail'],
          decoded['message'],
          decoded['error'],
          decoded['description'],
        ];
        for (final item in candidates) {
          final value = item?.toString().trim();
          if (value != null && value.isNotEmpty) {
            return value;
          }
        }
      }
    } catch (_) {
      // Ignore non-json payload.
    }
    return null;
  }

  AuthResponse _authFromJson(
    Map<String, dynamic> json, {
    required String fallbackEmail,
    String fallbackName = 'Field User',
  }) {
    final token = (json['token'] ?? json['access_token'] ?? json['jwt'])
        ?.toString()
        .trim();
    final refreshToken = (json['refreshToken'] ?? json['refresh_token'])
        ?.toString()
        .trim();
    if (token == null || token.isEmpty) {
      throw const ApiException('Auth token missing in server response.');
    }

    final userPayload = json['user'];
    String? id;
    String? name;
    String? email;
    String? role;

    if (userPayload is Map<String, dynamic>) {
      id = userPayload['id']?.toString().trim();
      name = userPayload['name']?.toString().trim();
      email = (userPayload['email'] ?? userPayload['username'])
          ?.toString()
          .trim();
      role = userPayload['role']?.toString().trim().toUpperCase();
    }

    id ??= (json['user_id'] ?? json['id'])?.toString().trim();
    name ??= (json['name'] ?? json['full_name'])?.toString().trim();
    email ??= (json['email'] ?? json['username'])?.toString().trim();
    role ??= json['role']?.toString().trim().toUpperCase();

    return AuthResponse(
      token: token,
      refreshToken: (refreshToken == null || refreshToken.isEmpty) ? null : refreshToken,
      user: AppUser(
        id: (id == null || id.isEmpty) ? 'u-${DateTime.now().millisecondsSinceEpoch}' : id,
        name: (name == null || name.isEmpty) ? fallbackName : name,
        email: (email == null || email.isEmpty) ? fallbackEmail : email.toLowerCase(),
        role: (role == null || role.isEmpty) ? '' : role,
      ),
    );
  }
}
