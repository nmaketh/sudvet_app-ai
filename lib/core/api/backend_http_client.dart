import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'api_client.dart';
import 'base_url_resolver.dart';
import 'session_events.dart' as session;

class BackendHttpClient {
  BackendHttpClient({http.Client? httpClient}) : _http = httpClient ?? http.Client();

  final http.Client _http;

  static const _tokenKey = 'auth_token';
  static const _refreshTokenKey = 'auth_refresh_token';
  static const _requestTimeout = Duration(seconds: 35);

  Future<List<Map<String, dynamic>>> getAnimals({String query = ''}) async {
    final params = <String, String>{};
    if (query.trim().isNotEmpty) {
      params['query'] = query.trim();
      params['q'] = query.trim();
    }
    final decoded = await _request(
      method: 'GET',
      path: '/animals',
      queryParameters: params,
    );
    if (decoded is! List) {
      return const [];
    }
    return decoded.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();
  }

  Future<Map<String, dynamic>?> getAnimalById(String id) async {
    final decoded = await _request(method: 'GET', path: '/animals/$id');
    if (decoded is! Map<String, dynamic>) {
      return null;
    }
    return decoded;
  }

  Future<Map<String, dynamic>> createAnimal({
    String? name,
    DateTime? dob,
    String? location,
    String? notes,
  }) async {
    final decoded = await _request(
      method: 'POST',
      path: '/animals',
      body: {
        'name': _normalize(name),
        'dob': dob?.toIso8601String(),
        'location': _normalize(location),
        'notes': _normalize(notes),
      },
    );
    if (decoded is! Map<String, dynamic>) {
      throw const ApiException('Invalid animal response from backend.');
    }
    return decoded;
  }

  Future<List<Map<String, dynamic>>> getCases({
    String query = '',
    String? animalId,
    String? status,
    String? disease,
    int? limit,
  }) async {
    final params = <String, String>{};
    if (query.trim().isNotEmpty) {
      params['query'] = query.trim();
      params['q'] = query.trim();
    }
    if (animalId != null && animalId.trim().isNotEmpty) {
      params['animalId'] = animalId.trim();
      params['animal_id'] = animalId.trim();
    }
    if (status != null && status.trim().isNotEmpty) {
      params['status'] = status.trim();
    }
    if (disease != null && disease.trim().isNotEmpty) {
      params['disease'] = disease.trim();
    }
    if (limit != null && limit > 0) {
      params['limit'] = '$limit';
    }

    final decoded = await _request(
      method: 'GET',
      path: '/cases',
      queryParameters: params,
    );
    if (decoded is! List) {
      return const [];
    }
    return decoded.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();
  }

  Future<List<Map<String, dynamic>>> getVetInbox({int limit = 50}) async {
    final params = <String, String>{'limit': '$limit'};
    final decoded = await _request(
      method: 'GET',
      path: '/vet/inbox',
      queryParameters: params,
    );
    if (decoded is! List) {
      return const [];
    }
    return decoded.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();
  }

  Future<List<Map<String, dynamic>>> getAssignableVets() async {
    final decoded = await _request(
      method: 'GET',
      path: '/users/assignable',
      queryParameters: const {'role': 'VET'},
    );
    if (decoded is! List) {
      return const [];
    }
    return decoded.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();
  }

  Future<Map<String, dynamic>?> getCaseById(String id) async {
    try {
      final decoded = await _request(method: 'GET', path: '/cases/$id');
      if (decoded is! Map<String, dynamic>) {
        return null;
      }
      return decoded;
    } on ApiException {
      return null;
    }
  }

  Future<Map<String, dynamic>> exportCaseSummary(String caseId) async {
    final decoded = await _request(method: 'GET', path: '/cases/$caseId/export');
    if (decoded is! Map<String, dynamic>) {
      throw const ApiException('Invalid export payload from backend.');
    }
    return decoded;
  }

  Future<Map<String, dynamic>> getCaseTimeline(String caseId) async {
    final decoded = await _request(method: 'GET', path: '/cases/$caseId/timeline');
    if (decoded is! Map<String, dynamic>) {
      throw const ApiException('Invalid timeline payload from backend.');
    }
    return decoded;
  }

  Future<void> addCaseMessage({
    required String caseId,
    required String senderRole,
    String? senderId,
    String? senderName,
    String? senderEmail,
    required String message,
  }) async {
    await _request(
      method: 'POST',
      path: '/cases/$caseId/messages',
      body: {
        'senderRole': senderRole,
        'senderId': _normalize(senderId),
        'senderName': _normalize(senderName),
        'senderEmail': _normalize(senderEmail),
        'message': message.trim(),
      },
    );
  }

  Future<void> escalateCase(
    String caseId, {
    bool? allowAssignment,
    int? requestedVetId,
    String? vetEmail,
    String? requestNote,
  }) async {
    final body = <String, dynamic>{};
    if (allowAssignment != null) {
      body['allowAssignment'] = allowAssignment;
    }
    if (requestedVetId != null) {
      body['requestedVetId'] = requestedVetId;
    }
    if (vetEmail != null && vetEmail.trim().isNotEmpty) {
      body['vetEmail'] = vetEmail.trim();
    }
    if (requestNote != null && requestNote.trim().isNotEmpty) {
      body['requestNote'] = requestNote.trim();
    }
    await _request(
      method: 'POST',
      path: '/cases/$caseId/escalate',
      body: body.isEmpty ? null : body,
    );
  }

  Future<void> claimCase({
    required String caseId,
    String? note,
  }) async {
    final body = <String, dynamic>{};
    if (note != null && note.trim().isNotEmpty) {
      body['note'] = note.trim();
    }
    await _request(
      method: 'POST',
      path: '/cases/$caseId/claim',
      body: body.isEmpty ? null : body,
    );
  }

  Future<Map<String, dynamic>> transferCaseToVet({
    required String caseId,
    String? senderId,
    String? senderName,
    String? senderEmail,
    required String newVetEmail,
    String? newVetId,
    String? newVetName,
    String? reason,
    String? message,
  }) async {
    final decoded = await _request(
      method: 'POST',
      path: '/cases/$caseId/transfer-vet',
      body: {
        'senderRole': 'vet',
        'senderId': _normalize(senderId),
        'senderName': _normalize(senderName),
        'senderEmail': _normalize(senderEmail),
        'newVetEmail': newVetEmail.trim(),
        'vetId': _normalize(newVetId),
        'vetName': _normalize(newVetName),
        'reason': _normalize(reason),
        'message': _normalize(message),
      },
    );
    if (decoded is! Map<String, dynamic>) {
      throw const ApiException('Invalid transfer-vet response from backend.');
    }
    return decoded;
  }

  Future<void> submitVetReview({
    required String caseId,
    String? senderId,
    String? senderName,
    String? senderEmail,
    required String assessment,
    required String plan,
    required String prescription,
    required String followUpDate,
    required String message,
  }) async {
    await _request(
      method: 'POST',
      path: '/cases/$caseId/vet/review',
      body: {
        'assessment': assessment,
        'plan': plan,
        'prescription': prescription,
        'follow_up_date': followUpDate,
        'message': message,
      },
    );
  }

  Future<void> closeCase({
    required String caseId,
    required String outcome,
    required String senderRole,
    String? senderId,
    String? senderName,
    String? senderEmail,
    required String notes,
  }) async {
    await _request(
      method: 'POST',
      path: '/cases/$caseId/close',
      body: {
        'outcome': outcome,
        'senderRole': senderRole,
        'senderId': _normalize(senderId),
        'senderName': _normalize(senderName),
        'senderEmail': _normalize(senderEmail),
        'notes': notes.trim(),
      },
    );
  }

  Future<Map<String, dynamic>> createCase({
    required String? animalId,
    required Map<String, bool> symptoms,
    required double? temperature,
    required double? severity,
    required List<String> imagePaths,
    List<Uint8List>? imageBytesList,
    List<String>? imageFileNames,
    String? vetEmail,
    String? chwOwnerId,
    String? chwOwnerName,
    String? chwOwnerEmail,
    required List<String> attachments,
    required String? notes,
    required bool shouldAttemptSync,
    bool allowAssignment = false,
  }) async {
    final baseUrl = await _baseUrl();
    if (baseUrl.isEmpty) {
      throw ApiException(_serverUnavailableMessage());
    }
    final uri = Uri.parse(_composeUrl(baseUrl, '/cases'));
    final request = http.MultipartRequest('POST', uri);
    final token = await _token();
    if (token != null && token.isNotEmpty) {
      request.headers['Authorization'] = 'Bearer $token';
    }

    final normalizedImagePaths = imagePaths.where((e) => e.trim().isNotEmpty).toList(growable: false);
    final trimmedNames = (imageFileNames ?? const [])
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList(growable: false);
    final bytesList = (imageBytesList ?? const <Uint8List>[])
        .where((e) => e.isNotEmpty)
        .toList(growable: false);

    final payload = {
      'animalId': animalId,
      'symptoms': symptoms,
      'temperature': temperature,
      'severity': severity,
      'imagePath': normalizedImagePaths.isEmpty ? null : normalizedImagePaths.first,
      'imagePaths': normalizedImagePaths,
      'attachments': attachments,
      'notes': _normalize(notes),
      'vetEmail': _normalize(vetEmail),
      'chwOwnerId': _normalize(chwOwnerId),
      'chwOwnerName': _normalize(chwOwnerName),
      'chwOwnerEmail': _normalize(chwOwnerEmail),
      'shouldAttemptSync': shouldAttemptSync,
      'allowAssignment': allowAssignment,
    };
    request.fields['payload'] = jsonEncode(payload);

    for (var i = 0; i < bytesList.length && i < 3; i++) {
      final name = (i < trimmedNames.length) ? trimmedNames[i] : 'case_image_${i + 1}.jpg';
      final ext = name.split('.').last.toLowerCase();
      const subtypeMap = {'jpg': 'jpeg', 'jpeg': 'jpeg', 'png': 'png', 'webp': 'webp', 'gif': 'gif'};
      final subtype = subtypeMap[ext] ?? 'jpeg';
      request.files.add(http.MultipartFile.fromBytes(
        'files', bytesList[i],
        filename: name,
        contentType: MediaType('image', subtype),
      ));
    }

    http.Response response;
    try {
      final streamed = await request.send().timeout(_requestTimeout);
      response = await http.Response.fromStream(streamed);
    } on TimeoutException {
      throw const ApiException(
        'SudVet server timed out. It may be waking up; retry shortly.',
      );
    } catch (_) {
      throw ApiException(_serverUnavailableMessage());
    }

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw ApiException(_extractError(response.body) ?? 'Backend error (${response.statusCode}).');
    }

    if (response.body.trim().isEmpty) {
      throw const ApiException('Invalid case submission response from backend.');
    }

    final decoded = jsonDecode(response.body);
    if (decoded is! Map<String, dynamic>) {
      throw const ApiException('Invalid case submission response from backend.');
    }
    return decoded;
  }

  Future<Map<String, dynamic>> syncCaseById(String caseId, {bool asyncMode = false}) async {
    final params = <String, String>{};
    if (asyncMode) {
      params['asyncMode'] = 'true';
    }
    final decoded = await _request(
      method: 'POST',
      path: '/cases/$caseId/sync',
      queryParameters: params,
    );
    if (decoded is! Map<String, dynamic>) {
      throw const ApiException('Invalid sync response from backend.');
    }
    return decoded;
  }

  Future<Map<String, dynamic>> syncPending({bool asyncMode = false}) async {
    final params = <String, String>{};
    if (asyncMode) {
      params['asyncMode'] = 'true';
    }
    final decoded = await _request(
      method: 'POST',
      path: '/cases/sync-pending',
      queryParameters: params,
    );
    if (decoded is! Map<String, dynamic>) {
      throw const ApiException('Invalid sync response from backend.');
    }
    return decoded;
  }

  Future<Map<String, dynamic>> getJobStatus(String jobId) async {
    final decoded = await _request(method: 'GET', path: '/jobs/$jobId');
    if (decoded is! Map<String, dynamic>) {
      throw const ApiException('Invalid job status response from backend.');
    }
    return decoded;
  }

  Future<void> updateCaseFollowUp({
    required String caseId,
    required String followUpStatus,
  }) async {
    await _request(
      method: 'PATCH',
      path: '/cases/$caseId/follow-up',
      body: {'followUpStatus': followUpStatus},
    );
  }

  Future<void> updateCaseNotes({
    required String caseId,
    required String notes,
  }) async {
    await _request(
      method: 'PATCH',
      path: '/cases/$caseId/notes',
      body: {'notes': notes.trim()},
    );
  }

  Future<Map<String, dynamic>> rejectCase(String caseId, String reason) async {
    final decoded = await _request(
      method: 'POST',
      path: '/cases/$caseId/reject',
      body: {'reason': reason.trim()},
    );
    if (decoded is! Map<String, dynamic>) {
      throw const ApiException('Invalid reject response from backend.');
    }
    return decoded;
  }

  Future<void> deleteCase(String caseId) async {
    await _request(method: 'DELETE', path: '/cases/$caseId');
  }

  Future<int> getPendingCount() async {
    final decoded = await _request(method: 'GET', path: '/cases/pending-count');
    if (decoded is! Map<String, dynamic>) {
      return 0;
    }
    final value = decoded['count'];
    if (value is num) {
      return value.toInt();
    }
    return int.tryParse(value?.toString() ?? '') ?? 0;
  }

  Future<dynamic> _request({
    required String method,
    required String path,
    Map<String, dynamic>? body,
    Map<String, String>? queryParameters,
  }) async {
    final baseUrl = await _baseUrl();
    if (baseUrl.isEmpty) {
      throw ApiException(_serverUnavailableMessage());
    }

    final uri = Uri.parse(_composeUrl(baseUrl, path)).replace(
      queryParameters: queryParameters == null || queryParameters.isEmpty ? null : queryParameters,
    );

    final headers = await _headers();

    http.Response response;
    try {
      response = await _send(
        method: method,
        uri: uri,
        headers: headers,
        body: body,
      );
    } on TimeoutException {
      throw const ApiException(
        'SudVet server timed out. It may be waking up; retry shortly.',
      );
    } catch (_) {
      throw ApiException(_serverUnavailableMessage());
    }

    if (response.statusCode == 401) {
      final refreshed = await _tryRefreshToken(baseUrl: baseUrl);
      if (refreshed) {
        final retryHeaders = await _headers();
        try {
          response = await _send(
            method: method,
            uri: uri,
            headers: retryHeaders,
            body: body,
          );
        } on TimeoutException {
          throw const ApiException(
            'SudVet server timed out. It may be waking up; retry shortly.',
          );
        } catch (_) {
          throw ApiException(_serverUnavailableMessage());
        }
      }
    }

    if (response.statusCode < 200 || response.statusCode >= 300) {
      if (response.statusCode == 401) {
        // Token is invalid/expired and refresh also failed — force re-login.
        session.signalSessionExpired();
        throw const ApiException('Session expired. Please log in again.');
      }
      if (response.statusCode == 404 &&
          (path.startsWith('/auth') ||
              path.startsWith('/animals') ||
              path.startsWith('/cases') ||
              path.startsWith('/jobs'))) {
        throw const ApiException(
          'Connected server does not expose SudVet backend routes.',
        );
      }
      if (response.statusCode == 502 ||
          response.statusCode == 503 ||
          response.statusCode == 504) {
        throw const ApiException(
          'SudVet server is unavailable or waking up. Retry in a few seconds.',
        );
      }
      throw ApiException(_extractError(response.body) ?? 'Backend error (${response.statusCode}).');
    }

    if (response.body.trim().isEmpty) {
      return null;
    }
    return jsonDecode(response.body);
  }

  Future<Map<String, String>> _headers() async {
    final token = await _token();
    final headers = <String, String>{'Content-Type': 'application/json'};
    if (token != null && token.isNotEmpty) {
      headers['Authorization'] = 'Bearer $token';
    }
    return headers;
  }

  Future<String> _baseUrl() async {
    return BaseUrlResolver.resolve();
  }

  String _serverUnavailableMessage() {
    return 'Unable to reach the SudVet server. Check your internet connection and try again.${BaseUrlResolver.developerHintSuffix()}';
  }

  Future<String?> _token() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_tokenKey);
  }

  Future<String?> _refreshToken() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_refreshTokenKey);
  }

  Future<http.Response> _send({
    required String method,
    required Uri uri,
    required Map<String, String> headers,
    Map<String, dynamic>? body,
  }) async {
    switch (method.toUpperCase()) {
      case 'GET':
        return _http.get(uri, headers: headers).timeout(_requestTimeout);
      case 'POST':
        return _http
            .post(uri, headers: headers, body: jsonEncode(body ?? const {}))
            .timeout(_requestTimeout);
      case 'PATCH':
        return _http
            .patch(uri, headers: headers, body: jsonEncode(body ?? const {}))
            .timeout(_requestTimeout);
      case 'DELETE':
        return _http.delete(uri, headers: headers).timeout(_requestTimeout);
      default:
        throw ApiException('Unsupported HTTP method: $method');
    }
  }

  Future<bool> _tryRefreshToken({required String baseUrl}) async {
    final refreshToken = await _refreshToken();
    if (refreshToken == null || refreshToken.isEmpty) {
      return false;
    }

    final refreshUri = Uri.parse(_composeUrl(baseUrl, '/auth/refresh'));
    try {
      final response = await _http
          .post(
            refreshUri,
            headers: const {'Content-Type': 'application/json'},
            body: jsonEncode({'refreshToken': refreshToken, 'refresh_token': refreshToken}),
          )
          .timeout(_requestTimeout);
      if (response.statusCode < 200 || response.statusCode >= 300) {
        return false;
      }
      final decoded = jsonDecode(response.body);
      if (decoded is! Map<String, dynamic>) {
        return false;
      }

      final newAccess = decoded['token']?.toString().trim();
      final newRefresh = (decoded['refreshToken'] ?? decoded['refresh_token'])
          ?.toString()
          .trim();
      if (newAccess == null || newAccess.isEmpty) {
        return false;
      }

      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_tokenKey, newAccess);
      if (newRefresh != null && newRefresh.isNotEmpty) {
        await prefs.setString(_refreshTokenKey, newRefresh);
      }
      return true;
    } catch (_) {
      return false;
    }
  }

  String _composeUrl(String baseUrl, String path) {
    final normalizedBase = baseUrl.endsWith('/') ? baseUrl.substring(0, baseUrl.length - 1) : baseUrl;
    final normalizedPath = path.startsWith('/') ? path : '/$path';
    return '$normalizedBase$normalizedPath';
  }

  String? _extractError(String body) {
    if (body.trim().isEmpty) {
      return null;
    }
    try {
      final decoded = jsonDecode(body);
      if (decoded is Map<String, dynamic>) {
        final candidates = [decoded['detail'], decoded['message'], decoded['error']];
        for (final item in candidates) {
          final text = item?.toString().trim();
          if (text != null && text.isNotEmpty) {
            return text;
          }
        }
      }
    } catch (_) {
      return null;
    }
    return null;
  }

  String? _normalize(String? value) {
    if (value == null) {
      return null;
    }
    final normalized = value.trim();
    if (normalized.isEmpty) {
      return null;
    }
    return normalized;
  }
}
