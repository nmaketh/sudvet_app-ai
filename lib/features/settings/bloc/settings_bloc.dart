import 'package:flutter_bloc/flutter_bloc.dart';

import '../data/settings_repository.dart';
import 'settings_event.dart';
import 'settings_state.dart';

class SettingsBloc extends Bloc<SettingsEvent, SettingsState> {
  SettingsBloc({required SettingsRepository settingsRepository})
    : _settingsRepository = settingsRepository,
      super(SettingsState.initial()) {
    on<SettingsLoadedRequested>(_onLoadedRequested);
    on<SettingsApiBaseChanged>(_onApiBaseChanged);
    on<SettingsVetEmailChanged>(_onVetEmailChanged);
    on<SettingsUserRoleChanged>(_onUserRoleChanged);
    on<SettingsThemeModeChanged>(_onThemeModeChanged);
    on<SettingsSavedRequested>(_onSavedRequested);
    on<SettingsOfflineToggled>(_onOfflineToggled);
    on<SettingsConnectionTestRequested>(_onConnectionTestRequested);
    on<SettingsFeedbackCleared>(_onFeedbackCleared);
  }

  final SettingsRepository _settingsRepository;

  Future<void> _onLoadedRequested(
    SettingsLoadedRequested event,
    Emitter<SettingsState> emit,
  ) async {
    final settings = await _settingsRepository.load();
    emit(
      state.copyWith(
        apiBaseUrl: settings.apiBaseUrl,
        offlineOnly: settings.offlineOnly,
        vetEmail: settings.vetEmail,
        userRole: settings.userRole,
        themeMode: settings.themeMode,
        isLoading: false,
      ),
    );
  }

  Future<void> _onApiBaseChanged(
    SettingsApiBaseChanged event,
    Emitter<SettingsState> emit,
  ) async {
    emit(state.copyWith(apiBaseUrl: event.value));
  }

  Future<void> _onSavedRequested(
    SettingsSavedRequested event,
    Emitter<SettingsState> emit,
  ) async {
    emit(
      state.copyWith(
        isSaving: true,
        clearErrorMessage: true,
        clearInfoMessage: true,
      ),
    );

    await _settingsRepository.saveApiBaseUrl(state.apiBaseUrl);
    await _settingsRepository.saveVetEmail(state.vetEmail);
    await _settingsRepository.saveUserRole(state.userRole);
    await _settingsRepository.saveThemeMode(state.themeMode);
    emit(state.copyWith(isSaving: false, infoMessage: 'Settings saved.'));
  }

  Future<void> _onVetEmailChanged(
    SettingsVetEmailChanged event,
    Emitter<SettingsState> emit,
  ) async {
    emit(state.copyWith(vetEmail: event.value));
  }

  Future<void> _onUserRoleChanged(
    SettingsUserRoleChanged event,
    Emitter<SettingsState> emit,
  ) async {
    emit(state.copyWith(userRole: event.value.trim().toLowerCase() == 'vet' ? 'vet' : 'chw'));
  }

  Future<void> _onThemeModeChanged(
    SettingsThemeModeChanged event,
    Emitter<SettingsState> emit,
  ) async {
    final normalized = event.value.trim().toLowerCase();
    emit(
      state.copyWith(
        themeMode: switch (normalized) {
          'dark' => 'dark',
          'light' => 'light',
          _ => 'system',
        },
      ),
    );
  }

  Future<void> _onOfflineToggled(
    SettingsOfflineToggled event,
    Emitter<SettingsState> emit,
  ) async {
    emit(state.copyWith(offlineOnly: event.value));
    await _settingsRepository.saveOfflineOnly(event.value);
  }

  Future<void> _onConnectionTestRequested(
    SettingsConnectionTestRequested event,
    Emitter<SettingsState> emit,
  ) async {
    emit(
      state.copyWith(
        isTesting: true,
        clearErrorMessage: true,
        clearInfoMessage: true,
      ),
    );

    final ok = await _settingsRepository.testConnection(state.apiBaseUrl);

    emit(
      state.copyWith(
        isTesting: false,
        infoMessage: ok ? 'Connection successful.' : null,
        errorMessage: ok ? null : 'Connection failed. Check your API base URL.',
      ),
    );
  }

  Future<void> _onFeedbackCleared(
    SettingsFeedbackCleared event,
    Emitter<SettingsState> emit,
  ) async {
    emit(state.copyWith(clearErrorMessage: true, clearInfoMessage: true));
  }
}
