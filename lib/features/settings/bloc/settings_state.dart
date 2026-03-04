import 'package:equatable/equatable.dart';

class SettingsState extends Equatable {
  const SettingsState({
    required this.apiBaseUrl,
    required this.offlineOnly,
    required this.vetEmail,
    required this.userRole,
    required this.themeMode,
    required this.isLoading,
    required this.isSaving,
    required this.isTesting,
    this.errorMessage,
    this.infoMessage,
  });

  final String apiBaseUrl;
  final bool offlineOnly;
  final String vetEmail;
  final String userRole;
  final String themeMode;
  final bool isLoading;
  final bool isSaving;
  final bool isTesting;
  final String? errorMessage;
  final String? infoMessage;

  factory SettingsState.initial() {
    return const SettingsState(
      apiBaseUrl: '',
      offlineOnly: false,
      vetEmail: '',
      userRole: 'chw',
      themeMode: 'light',
      isLoading: true,
      isSaving: false,
      isTesting: false,
    );
  }

  SettingsState copyWith({
    String? apiBaseUrl,
    bool? offlineOnly,
    String? vetEmail,
    String? userRole,
    String? themeMode,
    bool? isLoading,
    bool? isSaving,
    bool? isTesting,
    String? errorMessage,
    bool clearErrorMessage = false,
    String? infoMessage,
    bool clearInfoMessage = false,
  }) {
    return SettingsState(
      apiBaseUrl: apiBaseUrl ?? this.apiBaseUrl,
      offlineOnly: offlineOnly ?? this.offlineOnly,
      vetEmail: vetEmail ?? this.vetEmail,
      userRole: userRole ?? this.userRole,
      themeMode: themeMode ?? this.themeMode,
      isLoading: isLoading ?? this.isLoading,
      isSaving: isSaving ?? this.isSaving,
      isTesting: isTesting ?? this.isTesting,
      errorMessage: clearErrorMessage
          ? null
          : (errorMessage ?? this.errorMessage),
      infoMessage: clearInfoMessage ? null : (infoMessage ?? this.infoMessage),
    );
  }

  @override
  List<Object?> get props => [
    apiBaseUrl,
    offlineOnly,
    vetEmail,
    userRole,
    themeMode,
    isLoading,
    isSaving,
    isTesting,
    errorMessage,
    infoMessage,
  ];
}
