import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

class BaseUrlResolver {
  BaseUrlResolver._();

  static const settingsApiUrlKey = 'settings_api_base_url';
  static const _buildDefaultApiUrl = String.fromEnvironment(
    'SUDVET_API_BASE_URL',
    defaultValue: '',
  );
  static const devServerSettingsEnabled = bool.fromEnvironment(
    'ENABLE_DEV_SERVER_SETTINGS',
    defaultValue: false,
  );

  static Future<String> resolve() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = (prefs.getString(settingsApiUrlKey) ?? '').trim();
    return resolveBaseUrl(
      savedOverride: saved,
      buildTimeDefault: _buildDefaultApiUrl,
    );
  }

  static String resolveBaseUrl({
    required String savedOverride,
    String? buildTimeDefault,
    bool? isWeb,
    TargetPlatform? platform,
  }) {
    final configured = normalize(buildTimeDefault ?? _buildDefaultApiUrl);
    // Explicit build-time override should win so developers can recover from stale saved URLs
    // (common on Flutter web when a previous backend port is cached in shared_preferences).
    if (configured.isNotEmpty) {
      return configured;
    }

    final saved = normalize(savedOverride);
    if (saved.isNotEmpty) {
      return saved;
    }

    return _platformFallback(
      isWeb: isWeb ?? kIsWeb,
      platform: platform ?? defaultTargetPlatform,
    );
  }

  static String defaultForCurrentPlatform() {
    return resolveBaseUrl(savedOverride: '');
  }

  static String normalize(String value) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) {
      return '';
    }
    return trimmed.endsWith('/') ? trimmed.substring(0, trimmed.length - 1) : trimmed;
  }

  static String _platformFallback({
    required bool isWeb,
    required TargetPlatform platform,
  }) {
    if (isWeb) {
      return 'http://127.0.0.1:8002';
    }
    switch (platform) {
      case TargetPlatform.android:
        return 'http://10.0.2.2:8002';
      case TargetPlatform.iOS:
      case TargetPlatform.macOS:
      case TargetPlatform.windows:
      case TargetPlatform.linux:
      case TargetPlatform.fuchsia:
        return 'http://127.0.0.1:8002';
    }
  }

  static String developerHintSuffix() {
    if (!devServerSettingsEnabled) {
      return '';
    }
    return ' Use Server Settings (advanced) if needed.';
  }
}
