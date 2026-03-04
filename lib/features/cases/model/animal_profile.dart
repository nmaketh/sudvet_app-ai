import 'package:equatable/equatable.dart';
import 'package:intl/intl.dart';

class AnimalProfile extends Equatable {
  const AnimalProfile({
    required this.id,
    required this.tag,
    required this.createdAt,
    this.name,
    this.dob,
    this.location,
    this.notes,
  });

  final String id;
  final String tag;
  final String? name;
  final DateTime? dob;
  final String? location;
  final String? notes;
  final DateTime createdAt;

  bool get _hasUnknownTag {
    final normalized = tag.trim().toUpperCase();
    return normalized.isEmpty || normalized == 'UNKNOWN' || normalized == 'COW-UNKNOWN';
  }

  String get displayTag {
    if (!_hasUnknownTag) {
      return tag.trim();
    }
    final compact = id.replaceAll(RegExp(r'[^A-Za-z0-9]'), '').toUpperCase();
    final suffix = compact.isEmpty
        ? 'TMP001'
        : (compact.length >= 6 ? compact.substring(0, 6) : compact.padRight(6, 'X'));
    return 'COW-TMP-$suffix';
  }

  String get tagStatusLabel => _hasUnknownTag ? 'No physical tag recorded' : displayTag;

  String get title {
    final normalized = name?.trim() ?? '';
    if (normalized.isEmpty) {
      return displayTag;
    }
    return normalized;
  }

  String get displayName {
    final normalized = name?.trim() ?? '';
    if (normalized.isEmpty) {
      return displayTag;
    }
    return '$normalized (${_hasUnknownTag ? 'No tag' : displayTag})';
  }

  String get subtitle {
    final normalized = location?.trim() ?? '';
    if (normalized.isEmpty) {
      return tagStatusLabel;
    }
    return '${_hasUnknownTag ? 'No tag recorded' : displayTag} - $normalized';
  }

  String get dobLabel {
    if (dob == null) {
      return 'Not recorded';
    }
    return DateFormat('MMM d, y').format(dob!);
  }

  String get ageLabel {
    if (dob == null) {
      return 'Not recorded';
    }

    final now = DateTime.now();
    var months = (now.year - dob!.year) * 12 + (now.month - dob!.month);
    if (now.day < dob!.day) {
      months -= 1;
    }

    if (months < 1) {
      return '<1 month';
    }

    final years = months ~/ 12;
    final remainingMonths = months % 12;
    if (years <= 0) {
      return '$months month${months == 1 ? '' : 's'}';
    }
    if (remainingMonths == 0) {
      return '$years year${years == 1 ? '' : 's'}';
    }
    return '$years year${years == 1 ? '' : 's'} $remainingMonths month${remainingMonths == 1 ? '' : 's'}';
  }

  Map<String, Object?> toDbMap() {
    return {
      'id': id,
      'tag': tag,
      'name': _normalize(name),
      'dob': dob?.toIso8601String(),
      'location': _normalize(location),
      'notes': _normalize(notes),
      'createdAt': createdAt.toIso8601String(),
    };
  }

  factory AnimalProfile.fromDbMap(Map<String, Object?> map) {
    final createdRaw =
        map['createdAt'] ?? map['created_at'] ?? DateTime.now().toIso8601String();
    final dobRaw = map['dob'];
    final legacyAgeMonths = map['age_months'] as int?;

    DateTime? parsedDob;
    if (dobRaw is String && dobRaw.trim().isNotEmpty) {
      parsedDob = DateTime.tryParse(dobRaw);
    } else if (legacyAgeMonths != null) {
      parsedDob = DateTime.now().subtract(Duration(days: legacyAgeMonths * 30));
    }

    return AnimalProfile(
      id: map['id'] as String,
      tag: (map['tag'] as String?) ?? (map['tag_id'] as String?) ?? 'COW-UNKNOWN',
      name: _normalize(map['name'] as String?),
      dob: parsedDob,
      location: _normalize(map['location'] as String?),
      notes: _normalize(map['notes'] as String?),
      createdAt: DateTime.parse(createdRaw as String),
    );
  }

  factory AnimalProfile.fromApiMap(Map<String, dynamic> map) {
    return AnimalProfile(
      id: map['id'].toString(),
      tag: (map['tag'] ?? 'COW-UNKNOWN').toString(),
      name: _normalize(map['name']?.toString()),
      dob: map['dob'] == null ? null : DateTime.tryParse(map['dob'].toString()),
      location: _normalize(map['location']?.toString()),
      notes: _normalize(map['notes']?.toString()),
      createdAt: DateTime.tryParse((map['createdAt'] ?? map['created_at'])?.toString() ?? '') ?? DateTime.now(),
    );
  }

  @override
  List<Object?> get props => [id, tag, name, dob, location, notes, createdAt];

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
}
