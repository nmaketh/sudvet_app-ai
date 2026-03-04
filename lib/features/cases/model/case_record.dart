import 'dart:convert';

import 'package:equatable/equatable.dart';

enum CaseStatus { pending, synced, failed }

enum FollowUpStatus { open, inTreatment, recovered }

enum CaseStatusFilter { all, pending, synced, failed }

enum DiseaseFilter { all, normal, lsd, fmd, ecf, cbpp, unknown }

extension CaseStatusX on CaseStatus {
  String get dbValue {
    switch (this) {
      case CaseStatus.pending:
        return 'pending';
      case CaseStatus.synced:
        return 'synced';
      case CaseStatus.failed:
        return 'failed';
    }
  }

  String get label {
    switch (this) {
      case CaseStatus.pending:
        return 'Pending';
      case CaseStatus.synced:
        return 'Synced';
      case CaseStatus.failed:
        return 'Failed';
    }
  }

  static CaseStatus fromDbValue(String? value) {
    switch (value) {
      case 'synced':
        return CaseStatus.synced;
      case 'failed':
        return CaseStatus.failed;
      case 'open':
      case 'in_treatment':
      case 'resolved':
        // Shared ops backend cases are already server-backed. Treat as synced in field-app UI.
        return CaseStatus.synced;
      case 'pending':
      default:
        return CaseStatus.pending;
    }
  }
}

extension FollowUpStatusX on FollowUpStatus {
  String get dbValue {
    switch (this) {
      case FollowUpStatus.open:
        return 'open';
      case FollowUpStatus.inTreatment:
        return 'in_treatment';
      case FollowUpStatus.recovered:
        return 'recovered';
    }
  }

  String get label {
    switch (this) {
      case FollowUpStatus.open:
        return 'Open';
      case FollowUpStatus.inTreatment:
        return 'In treatment';
      case FollowUpStatus.recovered:
        return 'Recovered';
    }
  }

  static FollowUpStatus fromDbValue(String? value) {
    switch (value) {
      case 'in_treatment':
        return FollowUpStatus.inTreatment;
      case 'recovered':
        return FollowUpStatus.recovered;
      case 'open':
      default:
        return FollowUpStatus.open;
    }
  }
}

extension CaseStatusFilterX on CaseStatusFilter {
  String get label {
    switch (this) {
      case CaseStatusFilter.all:
        return 'All';
      case CaseStatusFilter.pending:
        return 'Pending';
      case CaseStatusFilter.synced:
        return 'Synced';
      case CaseStatusFilter.failed:
        return 'Failed';
    }
  }

  CaseStatus? get status {
    switch (this) {
      case CaseStatusFilter.all:
        return null;
      case CaseStatusFilter.pending:
        return CaseStatus.pending;
      case CaseStatusFilter.synced:
        return CaseStatus.synced;
      case CaseStatusFilter.failed:
        return CaseStatus.failed;
    }
  }
}

extension DiseaseFilterX on DiseaseFilter {
  String get label {
    switch (this) {
      case DiseaseFilter.all:
        return 'All';
      case DiseaseFilter.normal:
        return 'Normal';
      case DiseaseFilter.lsd:
        return 'LSD';
      case DiseaseFilter.fmd:
        return 'FMD';
      case DiseaseFilter.ecf:
        return 'ECF';
      case DiseaseFilter.cbpp:
        return 'CBPP';
      case DiseaseFilter.unknown:
        return 'Unknown';
    }
  }

  String? get diseaseKey {
    switch (this) {
      case DiseaseFilter.all:
        return null;
      case DiseaseFilter.normal:
        return 'normal';
      case DiseaseFilter.lsd:
        return 'lsd';
      case DiseaseFilter.fmd:
        return 'fmd';
      case DiseaseFilter.ecf:
        return 'ecf';
      case DiseaseFilter.cbpp:
        return 'cbpp';
      case DiseaseFilter.unknown:
        return 'unknown';
    }
  }
}

class CaseRecord extends Equatable {
  const CaseRecord({
    required this.id,
    required this.createdAt,
    required this.status,
    required this.followUpStatus,
    required this.symptoms,
    this.animalId,
    this.animalName,
    this.animalTag,
    this.followUpDate,
    this.temperature,
    this.severity,
    this.imagePath,
    this.attachments = const [],
    this.predictionJson,
    this.notes,
    this.syncedAt,
    this.chwOwnerName,
    this.chwOwnerEmail,
    this.assignedVetName,
    this.assignedVetEmail,
    // Workflow lifecycle fields (populated from ops backend)
    this.urgent = false,
    this.triagedAt,
    this.acceptedAt,
    this.resolvedAt,
    this.vetReviewJson,
    this.rejectionReason,
  });

  final String id;
  final String? animalId;
  final String? animalName;
  final String? animalTag;
  final DateTime createdAt;
  final CaseStatus status;
  final FollowUpStatus followUpStatus;
  final DateTime? followUpDate;
  final Map<String, bool> symptoms;
  final double? temperature;
  final double? severity;
  final String? imagePath;
  final List<String> attachments;
  final Map<String, dynamic>? predictionJson;
  final String? notes;
  final DateTime? syncedAt;
  final String? chwOwnerName;
  final String? chwOwnerEmail;
  final String? assignedVetName;
  final String? assignedVetEmail;
  // Workflow lifecycle fields (populated from ops backend)
  final bool urgent;
  final DateTime? triagedAt;
  final DateTime? acceptedAt;
  final DateTime? resolvedAt;
  final Map<String, dynamic>? vetReviewJson;
  final String? rejectionReason;

  String get animalLabel {
    final normalizedName = animalName?.trim() ?? '';
    final normalizedTag = animalTag?.trim() ?? '';
    if (normalizedName.isNotEmpty && normalizedTag.isNotEmpty) {
      return '$normalizedName ($normalizedTag)';
    }
    if (normalizedName.isNotEmpty) {
      return normalizedName;
    }
    if (normalizedTag.isNotEmpty) {
      return normalizedTag;
    }
    return 'Quick Case';
  }

  String? get prediction => _readPredictionString('prediction');
  double? get confidence => _readPredictionDouble('confidence');
  String? get method => _readPredictionString('method');
  String? get gradcamPath {
    final direct = _readPredictionString('gradcamPath') ?? _readPredictionString('gradcam_path');
    if (direct != null && direct.isNotEmpty) {
      return direct;
    }
    final explain = predictionJson?['explain'];
    if (explain is Map) {
      final nested = (explain['gradcamPath'] ?? explain['gradcam_path'])?.toString().trim();
      if (nested != null && nested.isNotEmpty) {
        return nested;
      }
    }
    return null;
  }
  String? get workflowStatus {
    final raw = _readPredictionStringFromMap('workflowStatus', source: predictionJson);
    if (raw != null) {
      return raw;
    }
    return null;
  }

  List<String> get recommendations {
    final raw = predictionJson?['recommendations'];
    if (raw is! List) {
      return const [];
    }
    return raw.map((item) => item.toString()).toList(growable: false);
  }

  // ── Explainability fields (from richer prediction_json) ─────────────────  /// Probability distribution across all diseases (disease key to 0..1 score).
  Map<String, double> get allProbabilities {
    final raw = _explainField('probabilities') ?? predictionJson?['probabilities'];
    if (raw is! Map) return {};
    return raw.map((k, v) => MapEntry(
      k.toString(),
      v is num ? v.toDouble() : double.tryParse(v.toString()) ?? 0.0,
    ));
  }  /// Ranked symptom contributions (symptom key to 0..1 score, sorted desc).
  Map<String, double> get featureImportance {
    final raw = _explainField('feature_importance') ?? predictionJson?['feature_importance'];
    if (raw is! Map) return {};
    return raw.map((k, v) => MapEntry(
      k.toString(),
      v is num ? v.toDouble() : double.tryParse(v.toString()) ?? 0.0,
    ));
  }

  /// Ranked differential diagnosis — list of {disease, display_name, score, percentage, matched_symptoms}
  List<Map<String, dynamic>> get differential {
    final raw = _explainField('differential') ?? predictionJson?['differential'];
    if (raw is! List) return [];
    return raw.whereType<Map>().map((m) {
      return m.map((k, v) => MapEntry(k.toString(), v));
    }).toList();
  }

  /// Clinical rule triggers that fired for this prediction
  List<String> get ruleTriggers {
    final raw = _explainField('rule_triggers') ?? predictionJson?['rule_triggers'];
    if (raw is! List) return [];
    return raw.map((e) => e.toString()).toList();
  }

  /// Natural language reasoning explanation
  String? get reasoningText {
    final v = _explainField('reasoning') ?? predictionJson?['reasoning'];
    final s = v?.toString().trim();
    return (s == null || s.isEmpty) ? null : s;
  }

  /// Temperature contextual note from backend
  String? get temperatureNote {
    final v = _explainField('temperature_note') ?? predictionJson?['temperature_note'];
    final s = v?.toString().trim();
    return (s == null || s.isEmpty) ? null : s;
  }

  /// Severity contextual note from backend
  String? get severityNote {
    final v = _explainField('severity_note') ?? predictionJson?['severity_note'];
    final s = v?.toString().trim();
    return (s == null || s.isEmpty) ? null : s;
  }

  Object? _explainField(String key) {
    // The Flutter api_client.dart stores the full raw response under 'raw',
    // which contains an 'explain' sub-object.
    final raw = predictionJson?['raw'];
    if (raw is Map) {
      final explain = raw['explain'];
      if (explain is Map) {
        return explain[key];
      }
    }
    // Fallback: some routes store explainability at top level of prediction_json
    return predictionJson?[key];
  }

  bool get hasPrediction => prediction != null && prediction!.trim().isNotEmpty;

  String get chwOwnerLabel {
    final name = chwOwnerName?.trim() ?? '';
    final email = chwOwnerEmail?.trim() ?? '';
    if (name.isNotEmpty && email.isNotEmpty) return '$name ($email)';
    if (name.isNotEmpty) return name;
    if (email.isNotEmpty) return email;
    return 'Unknown CHW';
  }

  String get assignedVetLabel {
    final name = assignedVetName?.trim() ?? '';
    final email = assignedVetEmail?.trim() ?? '';
    if (name.isNotEmpty && email.isNotEmpty) return '$name ($email)';
    if (name.isNotEmpty) return name;
    if (email.isNotEmpty) return email;
    return 'Unassigned';
  }

  String get diseaseKey {
    // Try machine-key fields first (new format: "fmd", "lsd", etc.)
    final machineKey = (_readPredictionString('label') ??
            _readPredictionString('final_label') ??
            _readPredictionString('prediction'))
        ?.trim()
        .toLowerCase();

    if (machineKey != null && machineKey.isNotEmpty) {
      // Exact machine key match
      if (machineKey == 'lsd') return 'lsd';
      if (machineKey == 'fmd') return 'fmd';
      if (machineKey == 'ecf') return 'ecf';
      if (machineKey == 'cbpp') return 'cbpp';
      if (machineKey == 'normal') return 'normal';
      // Display-name fallback for records stored before the fix
      if (machineKey.contains('lumpy')) return 'lsd';
      if (machineKey.contains('foot') || machineKey.contains('mouth')) return 'fmd';
      if (machineKey.contains('east coast') || machineKey.contains('theileria')) return 'ecf';
      if (machineKey.contains('pleuropneumonia') || machineKey.contains('contagious bovine')) {
        return 'cbpp';
      }
      if (machineKey.contains('normal') || machineKey.contains('no disease')) return 'normal';
    }
    return 'unknown';
  }

  String get urgency {
    if (prediction == null) {
      return 'Needs Sync';
    }

    if (diseaseKey == 'normal' && (confidence ?? 0) >= 0.8) {
      return 'Low';
    }

    if ((confidence ?? 0) < 0.65) {
      return 'Medium';
    }

    if (diseaseKey == 'lsd' || diseaseKey == 'fmd' || diseaseKey == 'cbpp') {
      return 'High';
    }

    return 'Medium';
  }

  CaseRecord copyWith({
    String? id,
    String? animalId,
    bool clearAnimalId = false,
    String? animalName,
    bool clearAnimalName = false,
    String? animalTag,
    bool clearAnimalTag = false,
    DateTime? createdAt,
    CaseStatus? status,
    FollowUpStatus? followUpStatus,
    DateTime? followUpDate,
    bool clearFollowUpDate = false,
    Map<String, bool>? symptoms,
    double? temperature,
    bool clearTemperature = false,
    double? severity,
    bool clearSeverity = false,
    String? imagePath,
    bool clearImagePath = false,
    List<String>? attachments,
    Map<String, dynamic>? predictionJson,
    bool clearPredictionJson = false,
    String? notes,
    bool clearNotes = false,
    DateTime? syncedAt,
    bool clearSyncedAt = false,
    String? chwOwnerName,
    bool clearChwOwnerName = false,
    String? chwOwnerEmail,
    bool clearChwOwnerEmail = false,
    String? assignedVetName,
    bool clearAssignedVetName = false,
    String? assignedVetEmail,
    bool clearAssignedVetEmail = false,
    bool? urgent,
    DateTime? triagedAt,
    bool clearTriagedAt = false,
    DateTime? acceptedAt,
    bool clearAcceptedAt = false,
    DateTime? resolvedAt,
    bool clearResolvedAt = false,
    Map<String, dynamic>? vetReviewJson,
    bool clearVetReviewJson = false,
    String? rejectionReason,
    bool clearRejectionReason = false,
  }) {
    return CaseRecord(
      id: id ?? this.id,
      animalId: clearAnimalId ? null : (animalId ?? this.animalId),
      animalName: clearAnimalName ? null : (animalName ?? this.animalName),
      animalTag: clearAnimalTag ? null : (animalTag ?? this.animalTag),
      createdAt: createdAt ?? this.createdAt,
      status: status ?? this.status,
      followUpStatus: followUpStatus ?? this.followUpStatus,
      followUpDate: clearFollowUpDate ? null : (followUpDate ?? this.followUpDate),
      symptoms: symptoms ?? this.symptoms,
      temperature: clearTemperature ? null : (temperature ?? this.temperature),
      severity: clearSeverity ? null : (severity ?? this.severity),
      imagePath: clearImagePath ? null : (imagePath ?? this.imagePath),
      attachments: attachments ?? this.attachments,
      predictionJson: clearPredictionJson ? null : (predictionJson ?? this.predictionJson),
      notes: clearNotes ? null : (notes ?? this.notes),
      syncedAt: clearSyncedAt ? null : (syncedAt ?? this.syncedAt),
      chwOwnerName: clearChwOwnerName ? null : (chwOwnerName ?? this.chwOwnerName),
      chwOwnerEmail: clearChwOwnerEmail ? null : (chwOwnerEmail ?? this.chwOwnerEmail),
      assignedVetName: clearAssignedVetName ? null : (assignedVetName ?? this.assignedVetName),
      assignedVetEmail: clearAssignedVetEmail ? null : (assignedVetEmail ?? this.assignedVetEmail),
      urgent: urgent ?? this.urgent,
      triagedAt: clearTriagedAt ? null : (triagedAt ?? this.triagedAt),
      acceptedAt: clearAcceptedAt ? null : (acceptedAt ?? this.acceptedAt),
      resolvedAt: clearResolvedAt ? null : (resolvedAt ?? this.resolvedAt),
      vetReviewJson: clearVetReviewJson ? null : (vetReviewJson ?? this.vetReviewJson),
      rejectionReason: clearRejectionReason ? null : (rejectionReason ?? this.rejectionReason),
    );
  }

  Map<String, Object?> toDbMap() {
    return {
      'id': id,
      'animalId': animalId,
      'createdAt': createdAt.toIso8601String(),
      'imagePath': imagePath,
      'symptomsJson': jsonEncode(symptoms),
      'status': status.dbValue,
      'predictionJson': predictionJson == null ? null : jsonEncode(predictionJson),
      'followUpStatus': followUpStatus.dbValue,
      'followUpDate': followUpDate?.toIso8601String(),
      'notes': _normalize(notes),
      'syncedAt': syncedAt?.toIso8601String(),
      'temperature': temperature,
      'severity': severity,
      'attachmentsJson': jsonEncode(attachments),
    };
  }

  factory CaseRecord.fromDbMap(Map<String, Object?> map) {
    final createdAtRaw = _pick(
      map,
      preferred: 'createdAt',
      fallback: 'created_at',
    );

    final predictionPayload = _decodePredictionMap(
      _pick(map, preferred: 'predictionJson', fallback: 'prediction_json'),
    );
    _mergeLegacyPredictionColumns(map, predictionPayload);

    final followUpDateRaw = _pick(
      map,
      preferred: 'followUpDate',
      fallback: 'follow_up_date',
    );
    final syncedAtRaw = _pick(map, preferred: 'syncedAt', fallback: 'synced_at');
    final attachmentsRaw = _pick(
      map,
      preferred: 'attachmentsJson',
      fallback: 'attachments_json',
    );

    return CaseRecord(
      id: map['id'] as String,
      animalId: _pickString(map, preferred: 'animalId', fallback: 'animal_id'),
      animalName: _pickString(map, preferred: 'animalName', fallback: 'animal_name'),
      animalTag: _pickString(map, preferred: 'animalTag', fallback: 'animal_tag'),
      createdAt: _parseDateTime(createdAtRaw) ?? DateTime.now(),
      imagePath: _pickString(map, preferred: 'imagePath', fallback: 'image_path') ??
          _pickString(map, preferred: 'image_url', fallback: 'image_url'),
      symptoms: _decodeSymptoms(
        _pick(map, preferred: 'symptomsJson', fallback: 'symptoms_json'),
      ),
      temperature: _pickDouble(map, preferred: 'temperature', fallback: 'temperature'),
      severity: _pickDouble(map, preferred: 'severity', fallback: 'severity'),
      predictionJson: predictionPayload.isEmpty ? null : predictionPayload,
      status: CaseStatusX.fromDbValue(map['status'] as String?),
      followUpStatus: FollowUpStatusX.fromDbValue(
        _pickString(map, preferred: 'followUpStatus', fallback: 'follow_up_status') ??
            _deriveFollowUpStatusFromCaseStatus(map['status']?.toString()),
      ),
      followUpDate: _parseDateTime(followUpDateRaw),
      notes: _normalize(map['notes'] as String?),
      syncedAt: _parseDateTime(syncedAtRaw),
      attachments: _decodeStringList(attachmentsRaw),
      chwOwnerName: _participantField(map, 'chwOwner', 'name') ??
          _pickString(map, preferred: 'submitted_by_name', fallback: 'submitted_by_name'),
      chwOwnerEmail: _participantField(map, 'chwOwner', 'email'),
      assignedVetName: _participantField(map, 'assignedVet', 'name') ??
          _pickString(map, preferred: 'assigned_to_name', fallback: 'assigned_to_name'),
      assignedVetEmail: _participantField(map, 'assignedVet', 'email') ??
          _pickString(map, preferred: 'vetEmail', fallback: 'vet_email'),
      // Workflow lifecycle fields from ops backend
      urgent: map['urgent'] == true || map['urgent'].toString() == 'true',
      triagedAt: _parseDateTime(map['triaged_at']),
      acceptedAt: _parseDateTime(map['accepted_at']),
      resolvedAt: _parseDateTime(map['resolved_at']),
      vetReviewJson: _decodeJsonMap(map['vet_review_json']),
      rejectionReason: _pickString(map, preferred: 'rejection_reason', fallback: 'rejectionReason'),
    );
  }

  static String? _participantField(
    Map<String, Object?> map,
    String participantKey,
    String fieldKey,
  ) {
    final raw = map[participantKey];
    if (raw is Map) {
      final value = raw[fieldKey];
      final text = value?.toString().trim();
      return (text == null || text.isEmpty) ? null : text;
    }
    return null;
  }

  static String? _deriveFollowUpStatusFromCaseStatus(String? status) {
    switch ((status ?? '').trim().toLowerCase()) {
      case 'in_treatment':
        return 'in_treatment';
      case 'resolved':
        return 'recovered';
      case 'open':
        return 'open';
      default:
        return null;
    }
  }

  static String? _readPredictionStringFromMap(
    String key, {
    Map<String, dynamic>? source,
  }) {
    final value = (source ?? const {})[key];
    if (value == null) {
      return null;
    }
    final normalized = value.toString().trim();
    if (normalized.isEmpty) {
      return null;
    }
    return normalized;
  }

  String? _readPredictionString(String key) {
    return _readPredictionStringFromMap(key, source: predictionJson);
  }

  double? _readPredictionDouble(String key) {
    final value = predictionJson?[key];
    if (value is num) {
      return value.toDouble();
    }
    if (value is String) {
      return double.tryParse(value);
    }
    return null;
  }

  static Map<String, bool> _decodeSymptoms(Object? raw) {
    if (raw == null) {
      return const {};
    }

    if (raw is Map) {
      return raw.map(
        (key, value) => MapEntry(key.toString(), value == true || value.toString() == '1'),
      );
    }

    final decoded = jsonDecode(raw as String);
    if (decoded is! Map<String, dynamic>) {
      return const {};
    }
    return decoded.map((key, value) => MapEntry(key, value == true));
  }

  static List<String> _decodeStringList(Object? raw) {
    if (raw == null) {
      return const [];
    }

    if (raw is List) {
      return raw.map((item) => item.toString()).toList(growable: false);
    }

    final decoded = jsonDecode(raw as String);
    if (decoded is! List) {
      return const [];
    }
    return decoded.map((item) => item.toString()).toList(growable: false);
  }

  static Map<String, dynamic> _decodePredictionMap(Object? raw) {
    if (raw == null) {
      return <String, dynamic>{};
    }
    if (raw is Map<String, dynamic>) {
      return Map<String, dynamic>.from(raw);
    }
    if (raw is Map) {
      return raw.map((key, value) => MapEntry(key.toString(), value));
    }
    final decoded = jsonDecode(raw as String);
    if (decoded is! Map<String, dynamic>) {
      return <String, dynamic>{};
    }
    return Map<String, dynamic>.from(decoded);
  }

  static void _mergeLegacyPredictionColumns(
    Map<String, Object?> map,
    Map<String, dynamic> payload,
  ) {
    final legacyPrediction = map['prediction']?.toString();
    if ((payload['prediction'] == null || payload['prediction'].toString().isEmpty) &&
        legacyPrediction != null &&
        legacyPrediction.trim().isNotEmpty) {
      payload['prediction'] = legacyPrediction.trim();
    }

    if (payload['confidence'] == null && map['confidence'] != null) {
      final confidence = map['confidence'];
      if (confidence is num) {
        payload['confidence'] = confidence.toDouble();
      } else if (confidence is String) {
        payload['confidence'] = double.tryParse(confidence);
      }
    }

    if ((payload['method'] == null || payload['method'].toString().isEmpty) &&
        map['method'] != null) {
      payload['method'] = map['method'].toString();
    }

    if ((payload['gradcamPath'] == null ||
            payload['gradcamPath'].toString().isEmpty) &&
        map['gradcam_path'] != null) {
      payload['gradcamPath'] = map['gradcam_path'].toString();
    }
    if ((payload['gradcamPath'] == null || payload['gradcamPath'].toString().isEmpty) &&
        payload['gradcam_path'] != null) {
      payload['gradcamPath'] = payload['gradcam_path'].toString();
    }
    if (payload['gradcamPath'] == null || payload['gradcamPath'].toString().isEmpty) {
      final explain = payload['explain'];
      if (explain is Map) {
        final nested = (explain['gradcamPath'] ?? explain['gradcam_path'])?.toString().trim();
        if (nested != null && nested.isNotEmpty) {
          payload['gradcamPath'] = nested;
        }
      }
    }

    if (payload['recommendations'] == null && map['recommendations_json'] != null) {
      payload['recommendations'] = _decodeStringList(map['recommendations_json']);
    }

    if ((payload['workflowStatus'] == null || payload['workflowStatus'].toString().isEmpty) &&
        map['workflowStatus'] != null) {
      payload['workflowStatus'] = map['workflowStatus'].toString();
    }
  }

  static Object? _pick(
    Map<String, Object?> map, {
    required String preferred,
    required String fallback,
  }) {
    final preferredValue = map[preferred];
    if (preferredValue != null) {
      if (preferredValue is String) {
        if (preferredValue.trim().isNotEmpty) {
          return preferredValue;
        }
      } else {
        return preferredValue;
      }
    }
    return map[fallback];
  }

  static String? _pickString(
    Map<String, Object?> map, {
    required String preferred,
    required String fallback,
  }) {
    final raw = _pick(map, preferred: preferred, fallback: fallback);
    if (raw == null) {
      return null;
    }
    final normalized = raw.toString().trim();
    if (normalized.isEmpty) {
      return null;
    }
    return normalized;
  }

  static double? _pickDouble(
    Map<String, Object?> map, {
    required String preferred,
    required String fallback,
  }) {
    final raw = _pick(map, preferred: preferred, fallback: fallback);
    if (raw is num) {
      return raw.toDouble();
    }
    if (raw is String) {
      return double.tryParse(raw);
    }
    return null;
  }

  static DateTime? _parseDateTime(Object? raw) {
    if (raw == null) {
      return null;
    }
    if (raw is DateTime) {
      return raw;
    }
    if (raw is String) {
      return DateTime.tryParse(raw);
    }
    return null;
  }

  static Map<String, dynamic>? _decodeJsonMap(Object? raw) {
    if (raw == null) return null;
    if (raw is Map<String, dynamic>) return Map<String, dynamic>.from(raw);
    if (raw is Map) return raw.map((k, v) => MapEntry(k.toString(), v));
    if (raw is String && raw.trim().isNotEmpty) {
      try {
        final decoded = jsonDecode(raw);
        if (decoded is Map<String, dynamic>) return Map<String, dynamic>.from(decoded);
      } catch (_) {}
    }
    return null;
  }

  static String? _normalize(String? value) {
    if (value == null) {
      return null;
    }
    final normalized = value.trim();
    if (normalized.isEmpty) {
      return null;
    }
    return normalized;
  }

  @override
  List<Object?> get props => [
    id,
    animalId,
    animalName,
    animalTag,
    createdAt,
    status,
    followUpStatus,
    followUpDate,
    symptoms,
    temperature,
    severity,
    imagePath,
    attachments,
    predictionJson,
    notes,
    syncedAt,
    chwOwnerName,
    chwOwnerEmail,
    assignedVetName,
    assignedVetEmail,
    urgent,
    triagedAt,
    acceptedAt,
    resolvedAt,
    vetReviewJson,
    rejectionReason,
  ];
}
