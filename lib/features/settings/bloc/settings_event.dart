import 'package:equatable/equatable.dart';

abstract class SettingsEvent extends Equatable {
  const SettingsEvent();

  @override
  List<Object?> get props => [];
}

class SettingsLoadedRequested extends SettingsEvent {
  const SettingsLoadedRequested();
}

class SettingsApiBaseChanged extends SettingsEvent {
  const SettingsApiBaseChanged(this.value);

  final String value;

  @override
  List<Object?> get props => [value];
}

class SettingsVetEmailChanged extends SettingsEvent {
  const SettingsVetEmailChanged(this.value);

  final String value;

  @override
  List<Object?> get props => [value];
}

class SettingsUserRoleChanged extends SettingsEvent {
  const SettingsUserRoleChanged(this.value);

  final String value;

  @override
  List<Object?> get props => [value];
}

class SettingsThemeModeChanged extends SettingsEvent {
  const SettingsThemeModeChanged(this.value);

  final String value;

  @override
  List<Object?> get props => [value];
}

class SettingsSavedRequested extends SettingsEvent {
  const SettingsSavedRequested();
}

class SettingsOfflineToggled extends SettingsEvent {
  const SettingsOfflineToggled(this.value);

  final bool value;

  @override
  List<Object?> get props => [value];
}

class SettingsConnectionTestRequested extends SettingsEvent {
  const SettingsConnectionTestRequested();
}

class SettingsFeedbackCleared extends SettingsEvent {
  const SettingsFeedbackCleared();
}
