import 'package:uuid/uuid.dart';

class IdGenerator {
  IdGenerator({Uuid? uuid}) : _uuid = uuid ?? const Uuid();

  final Uuid _uuid;

  String newAnimalId() => _uuid.v4();

  String newCaseId() => _uuid.v4();

  String newAnimalTag() {
    final compact = _uuid.v4().replaceAll('-', '').toUpperCase();
    return 'COW-${compact.substring(0, 6)}';
  }
}
