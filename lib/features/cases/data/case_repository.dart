import 'dart:async';
import 'dart:typed_data';

import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/api/api_client.dart';
import '../../../core/api/backend_http_client.dart';
import '../model/case_record.dart';
import '../model/dashboard_stats.dart';

class CaseSubmitResult {
  const CaseSubmitResult({
    required this.record,
    required this.syncedImmediately,
    this.warningMessage,
  });

  final CaseRecord record;
  final bool syncedImmediately;
  final String? warningMessage;
}

class SyncResult {
  const SyncResult({
    required this.syncedCount,
    required this.failedCount,
    this.errorMessage,
  });

  final int syncedCount;
  final int failedCount;
  final String? errorMessage;
}

class CaseRepository {
  CaseRepository({required BackendHttpClient backendClient}) : _backendClient = backendClient;

  final BackendHttpClient _backendClient;
  bool _initialized = false;
  static const _authNameKey = 'auth_user_name';
  static const _authEmailKey = 'auth_user_email';

  Future<void> initialize() async {
    if (_initialized) {
      return;
    }
    _initialized = true;
  }

  Future<DashboardStats> getDashboardStats() async {
    await initialize();
    final cases = await _getAllCases();

    final total = cases.length;
    final pending = cases.where((c) => c.status == CaseStatus.pending).length;
    final synced = cases.where((c) => c.status == CaseStatus.synced).length;
    final failed = cases.where((c) => c.status == CaseStatus.failed).length;

    DateTime? lastSync;
    for (final item in cases) {
      if (item.syncedAt == null) {
        continue;
      }
      if (lastSync == null || item.syncedAt!.isAfter(lastSync)) {
        lastSync = item.syncedAt;
      }
    }

    final diseaseCounts = <String, int>{};
    for (final item in cases) {
      diseaseCounts[item.diseaseKey] = (diseaseCounts[item.diseaseKey] ?? 0) + 1;
    }

    return DashboardStats(
      totalCases: total,
      pendingCases: pending,
      syncedCases: synced,
      failedCases: failed,
      lastSyncAt: lastSync,
      diseaseCounts: diseaseCounts,
      weeklyTrend: _buildWeeklyTrend(cases),
    );
  }

  Future<List<CaseRecord>> getRecentCases({int limit = 5}) async {
    await initialize();
    final rows = await _backendClient.getCases(limit: limit);
    return rows.map(_mapCase).toList(growable: false);
  }

  Future<List<CaseRecord>> getVetInbox({int limit = 50}) async {
    await initialize();
    final rows = await _backendClient.getVetInbox(limit: limit);
    return rows.map(_mapCase).toList(growable: false);
  }

  Future<List<Map<String, dynamic>>> getAssignableVets() async {
    await initialize();
    return _backendClient.getAssignableVets();
  }

  Future<List<CaseRecord>> getHistory({
    String query = '',
    String? animalId,
    CaseStatusFilter statusFilter = CaseStatusFilter.all,
    DiseaseFilter diseaseFilter = DiseaseFilter.all,
  }) async {
    await initialize();
    final rows = await _backendClient.getCases(
      query: query,
      animalId: animalId,
      status: statusFilter.status?.dbValue,
      disease: diseaseFilter.diseaseKey,
    );
    return rows.map(_mapCase).toList(growable: false);
  }

  Future<List<CaseRecord>> getCasesForAnimal(String animalId) async {
    await initialize();
    final rows = await _backendClient.getCases(animalId: animalId);
    return rows.map(_mapCase).toList(growable: false);
  }

  Future<CaseRecord?> getCaseById(String id) async {
    await initialize();
    final row = await _backendClient.getCaseById(id);
    if (row == null) {
      return null;
    }
    return _mapCase(row);
  }

  Future<CaseSubmitResult> submitCase({
    required String? animalId,
    required Map<String, bool> symptoms,
    required double? temperature,
    required double? severity,
    required List<String> imagePaths,
    List<Uint8List>? imageBytesList,
    List<String>? imageFileNames,
    String? vetEmail,
    required List<String> attachments,
    required String? notes,
    required bool shouldAttemptSync,
    bool allowAssignment = false,
    required String apiBaseUrl,
  }) async {
    await initialize();
    final actor = await _loadActorIdentity();

    final response = await _backendClient.createCase(
      animalId: animalId,
      symptoms: symptoms,
      temperature: temperature,
      severity: severity,
      imagePaths: imagePaths,
      imageBytesList: imageBytesList,
      imageFileNames: imageFileNames,
      vetEmail: vetEmail,
      chwOwnerName: actor['name'],
      chwOwnerEmail: actor['email'],
      attachments: attachments,
      notes: notes,
      shouldAttemptSync: shouldAttemptSync,
      allowAssignment: allowAssignment,
    );

    final recordSource = response['case'] is Map ? response['case'] : response;
    if (recordSource is! Map) {
      throw const ApiException('Invalid case payload received from backend.');
    }
    final record = _mapCase(Map<String, dynamic>.from(recordSource));

    return CaseSubmitResult(
      record: record,
      syncedImmediately: response['syncedImmediately'] == true || response['case'] == null,
      warningMessage: response['warningMessage']?.toString(),
    );
  }

  Future<void> updateFollowUpStatus({
    required String caseId,
    required FollowUpStatus followUpStatus,
  }) async {
    await initialize();
    await _backendClient.updateCaseFollowUp(
      caseId: caseId,
      followUpStatus: followUpStatus.dbValue,
    );
  }

  Future<void> updateCaseNotes({
    required String caseId,
    required String notes,
  }) async {
    await initialize();
    await _backendClient.updateCaseNotes(caseId: caseId, notes: notes);
  }

  Future<CaseRecord> rejectCase({
    required String caseId,
    required String reason,
  }) async {
    await initialize();
    final row = await _backendClient.rejectCase(caseId, reason);
    return _mapCase(row);
  }

  Future<void> deleteCase(String caseId) async {
    await initialize();
    await _backendClient.deleteCase(caseId);
  }

  Future<Map<String, dynamic>> exportCaseSummary(String caseId) async {
    await initialize();
    return _backendClient.exportCaseSummary(caseId);
  }

  Future<Map<String, dynamic>> getCaseTimeline(String caseId) async {
    await initialize();
    return _backendClient.getCaseTimeline(caseId);
  }

  Future<void> addCaseMessage({
    required String caseId,
    required String senderRole,
    String? senderId,
    String? senderName,
    String? senderEmail,
    required String message,
  }) async {
    await initialize();
    final actor = await _loadActorIdentity();
    await _backendClient.addCaseMessage(
      caseId: caseId,
      senderRole: senderRole,
      senderId: senderId,
      senderName: senderName ?? actor['name'],
      senderEmail: senderEmail ?? actor['email'],
      message: message,
    );
  }

  Future<void> escalateCase(
    String caseId, {
    bool? allowAssignment,
    int? requestedVetId,
    String? vetEmail,
    String? requestNote,
  }) async {
    await initialize();
    await _backendClient.escalateCase(
      caseId,
      allowAssignment: allowAssignment,
      requestedVetId: requestedVetId,
      vetEmail: vetEmail,
      requestNote: requestNote,
    );
  }

  Future<void> claimCase({
    required String caseId,
    String? note,
  }) async {
    await initialize();
    await _backendClient.claimCase(
      caseId: caseId,
      note: note,
    );
  }

  Future<void> transferCaseToVet({
    required String caseId,
    String? senderId,
    String? senderName,
    String? senderEmail,
    required String newVetEmail,
    String? newVetName,
    String? reason,
    String? message,
  }) async {
    await initialize();
    final actor = await _loadActorIdentity();
    await _backendClient.transferCaseToVet(
      caseId: caseId,
      senderId: senderId,
      senderName: senderName ?? actor['name'],
      senderEmail: senderEmail ?? actor['email'],
      newVetEmail: newVetEmail,
      newVetName: newVetName,
      reason: reason,
      message: message,
    );
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
    await initialize();
    final actor = await _loadActorIdentity();
    await _backendClient.submitVetReview(
      caseId: caseId,
      senderId: senderId,
      senderName: senderName ?? actor['name'],
      senderEmail: senderEmail ?? actor['email'],
      assessment: assessment,
      plan: plan,
      prescription: prescription,
      followUpDate: followUpDate,
      message: message,
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
    await initialize();
    final actor = await _loadActorIdentity();
    await _backendClient.closeCase(
      caseId: caseId,
      outcome: outcome,
      senderRole: senderRole,
      senderId: senderId,
      senderName: senderName ?? actor['name'],
      senderEmail: senderEmail ?? actor['email'],
      notes: notes,
    );
  }

  Future<Map<String, String?>> _loadActorIdentity() async {
    final prefs = await SharedPreferences.getInstance();
    final name = prefs.getString(_authNameKey)?.trim();
    final email = prefs.getString(_authEmailKey)?.trim().toLowerCase();
    return {
      'name': (name == null || name.isEmpty) ? null : name,
      'email': (email == null || email.isEmpty) ? null : email,
    };
  }

  Future<int> getPendingCount() async {
    await initialize();
    return _backendClient.getPendingCount();
  }

  Future<SyncResult> syncCaseById({
    required String caseId,
    required String apiBaseUrl,
    required bool offlineOnly,
  }) async {
    await initialize();
    if (offlineOnly) {
      return const SyncResult(
        syncedCount: 0,
        failedCount: 0,
        errorMessage: 'Offline-only mode is enabled. Disable it to sync.',
      );
    }

    try {
      Map<String, dynamic> response;
      try {
        response = await _backendClient.syncCaseById(caseId, asyncMode: true);
      } on ApiException {
        response = await _backendClient.syncCaseById(caseId);
      }
      if (response['queued'] == true) {
        final jobId = response['jobId']?.toString();
        if (jobId == null || jobId.isEmpty) {
          return const SyncResult(
            syncedCount: 0,
            failedCount: 1,
            errorMessage: 'Sync was queued but no job ID was returned.',
          );
        }
        return _waitForJobs([jobId]);
      }
      if (response.containsKey('id')) {
        return const SyncResult(syncedCount: 1, failedCount: 0);
      }
      return SyncResult(
        syncedCount: _toInt(response['syncedCount'] ?? response['synced']),
        failedCount: _toInt(response['failedCount'] ?? response['failed']),
        errorMessage: response['errorMessage']?.toString(),
      );
    } on ApiException catch (e) {
      return SyncResult(syncedCount: 0, failedCount: 1, errorMessage: e.message);
    }
  }

  Future<SyncResult> syncPending({
    required bool offlineOnly,
    required String apiBaseUrl,
  }) async {
    await initialize();
    if (offlineOnly) {
      return const SyncResult(
        syncedCount: 0,
        failedCount: 0,
        errorMessage: 'Offline-only mode is enabled. Disable it to sync.',
      );
    }

    try {
      Map<String, dynamic> response;
      try {
        response = await _backendClient.syncPending(asyncMode: true);
      } on ApiException {
        response = await _backendClient.syncPending();
      }
      if (response['queued'] == true) {
        final jobIdsRaw = response['jobIds'];
        final jobIds = jobIdsRaw is List
            ? jobIdsRaw.map((e) => e.toString()).where((e) => e.isNotEmpty).toList()
            : <String>[];
        if (jobIds.isEmpty) {
          return const SyncResult(syncedCount: 0, failedCount: 0);
        }
        return _waitForJobs(jobIds);
      }
      return SyncResult(
        syncedCount: _toInt(response['syncedCount'] ?? response['synced']),
        failedCount: _toInt(response['failedCount'] ?? response['failed']),
        errorMessage: response['errorMessage']?.toString(),
      );
    } on ApiException catch (e) {
      return SyncResult(syncedCount: 0, failedCount: 1, errorMessage: e.message);
    }
  }

  Future<List<CaseRecord>> _getAllCases() async {
    final rows = await _backendClient.getCases();
    return rows.map(_mapCase).toList(growable: false);
  }

  CaseRecord _mapCase(Map<String, dynamic> row) {
    return CaseRecord.fromDbMap(
      row.map((key, value) => MapEntry(key, value as Object?)),
    );
  }

  int _toInt(Object? value) {
    if (value is num) {
      return value.toInt();
    }
    return int.tryParse(value?.toString() ?? '') ?? 0;
  }

  Future<SyncResult> _waitForJobs(List<String> jobIds) async {
    if (jobIds.isEmpty) {
      return const SyncResult(syncedCount: 0, failedCount: 0);
    }

    final pending = Set<String>.from(jobIds);
    final completed = <String>{};
    final failed = <String>{};
    final failedMessages = <String>[];
    final deadline = DateTime.now().add(const Duration(seconds: 45));

    while (pending.isNotEmpty && DateTime.now().isBefore(deadline)) {
      final snapshot = pending.toList(growable: false);
      for (final jobId in snapshot) {
        try {
          final statusPayload = await _backendClient.getJobStatus(jobId);
          final status = statusPayload['status']?.toString().toLowerCase().trim() ?? '';
          if (status == 'completed') {
            pending.remove(jobId);
            completed.add(jobId);
            continue;
          }
          if (status == 'failed') {
            pending.remove(jobId);
            failed.add(jobId);
            final message = statusPayload['errorMessage']?.toString().trim();
            if (message != null && message.isNotEmpty) {
              failedMessages.add(message);
            }
          }
        } on ApiException {
          // Keep polling unless timeout hits.
        }
      }
      if (pending.isNotEmpty) {
        await Future<void>.delayed(const Duration(milliseconds: 900));
      }
    }

    if (pending.isNotEmpty) {
      failed.addAll(pending);
      final timeoutError = 'Some sync jobs timed out before completion.';
      return SyncResult(
        syncedCount: completed.length,
        failedCount: failed.length,
        errorMessage: failedMessages.isNotEmpty ? failedMessages.first : timeoutError,
      );
    }

    return SyncResult(
      syncedCount: completed.length,
      failedCount: failed.length,
      errorMessage: failedMessages.isNotEmpty ? failedMessages.first : null,
    );
  }

  List<DashboardTrendPoint> _buildWeeklyTrend(List<CaseRecord> cases) {
    final now = DateTime.now();
    final result = <DashboardTrendPoint>[];

    for (var i = 5; i >= 0; i--) {
      final weekStart = now.subtract(Duration(days: i * 7));
      final weekEnd = weekStart.add(const Duration(days: 7));
      final count = cases
          .where((item) => item.createdAt.isAfter(weekStart) && item.createdAt.isBefore(weekEnd))
          .length;
      result.add(
        DashboardTrendPoint(label: DateFormat('MMM d').format(weekStart), count: count),
      );
    }

    return result;
  }
}
