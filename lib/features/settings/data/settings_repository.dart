import 'package:equatable/equatable.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/api/api_client.dart';
import '../../../core/api/base_url_resolver.dart';

class AppSettings extends Equatable {
  const AppSettings({
    required this.apiBaseUrl,
    required this.offlineOnly,
    required this.vetEmail,
    required this.userRole,
    required this.themeMode,
  });

  final String apiBaseUrl;
  final bool offlineOnly;
  final String vetEmail;
  final String userRole;
  final String themeMode;

  @override
  List<Object?> get props => [apiBaseUrl, offlineOnly, vetEmail, userRole, themeMode];
}

class SettingsRepository {
  SettingsRepository({required ApiClient apiClient}) : _apiClient = apiClient;

  final ApiClient _apiClient;

  static const _apiUrlKey = BaseUrlResolver.settingsApiUrlKey;
  static const _offlineKey = 'settings_offline_only';
  static const _vetEmailKey = 'settings_vet_email';
  static const _userRoleKey = 'settings_user_role';
  static const _themeModeKey = 'settings_theme_mode';

  Future<AppSettings> load() async {
    final prefs = await SharedPreferences.getInstance();
    final savedBaseUrl = prefs.getString(_apiUrlKey)?.trim() ?? '';
    return AppSettings(
      apiBaseUrl: BaseUrlResolver.resolveBaseUrl(savedOverride: savedBaseUrl),
      offlineOnly: prefs.getBool(_offlineKey) ?? false,
      vetEmail: prefs.getString(_vetEmailKey)?.trim() ?? '',
      userRole: prefs.getString(_userRoleKey)?.trim().toLowerCase() == 'vet' ? 'vet' : 'chw',
      themeMode: _normalizeThemeMode(prefs.getString(_themeModeKey)),
    );
  }

  Future<void> saveApiBaseUrl(String value) async {
    final prefs = await SharedPreferences.getInstance();
    final normalized = value.trim();
    await prefs.setString(
      _apiUrlKey,
      normalized.isEmpty
          ? BaseUrlResolver.defaultForCurrentPlatform()
          : BaseUrlResolver.normalize(normalized),
    );
  }

  Future<void> saveOfflineOnly(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_offlineKey, value);
  }

  Future<void> saveVetEmail(String value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_vetEmailKey, value.trim());
  }

  Future<void> saveUserRole(String value) async {
    final prefs = await SharedPreferences.getInstance();
    final normalized = value.trim().toLowerCase();
    await prefs.setString(_userRoleKey, normalized == 'vet' ? 'vet' : 'chw');
  }

  Future<void> saveThemeMode(String value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_themeModeKey, _normalizeThemeMode(value));
  }

  Future<bool> testConnection(String baseUrl) async {
    return _apiClient.testConnection(baseUrl: baseUrl);
  }

  String _normalizeThemeMode(String? value) {
    final normalized = (value ?? '').trim().toLowerCase();
    if (normalized == 'dark') {
      return 'dark';
    }
    if (normalized == 'light') {
      return 'light';
    }
    return 'light';
  }
}
