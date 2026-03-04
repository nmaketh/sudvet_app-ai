import '../../../core/api/backend_http_client.dart';
import '../../cases/model/animal_profile.dart';

class AnimalRepository {
  AnimalRepository({required BackendHttpClient backendClient}) : _backendClient = backendClient;

  final BackendHttpClient _backendClient;
  bool _initialized = false;

  Future<void> initialize() async {
    if (_initialized) {
      return;
    }
    _initialized = true;
  }

  Future<List<AnimalProfile>> list({String query = ''}) async {
    await initialize();
    final rows = await _backendClient.getAnimals(query: query);
    return rows.map(AnimalProfile.fromApiMap).toList(growable: false);
  }

  Future<AnimalProfile?> getById(String id) async {
    await initialize();
    final row = await _backendClient.getAnimalById(id);
    if (row == null) {
      return null;
    }
    return AnimalProfile.fromApiMap(row);
  }

  Future<AnimalProfile> add({
    String? name,
    DateTime? dob,
    String? location,
    String? notes,
  }) async {
    await initialize();
    final row = await _backendClient.createAnimal(
      name: _normalize(name),
      dob: dob,
      location: _normalize(location),
      notes: _normalize(notes),
    );
    return AnimalProfile.fromApiMap(row);
  }

  Future<List<AnimalProfile>> seedDemoAnimalsIfEmpty() async {
    return list();
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
