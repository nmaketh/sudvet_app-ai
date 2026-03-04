import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../core/api/api_client.dart';
import '../core/api/backend_http_client.dart';
import '../core/api/session_events.dart' as session;
import '../features/animals/bloc/animal_bloc.dart';
import '../features/animals/data/animal_repository.dart';
import '../features/auth/bloc/auth_bloc.dart';
import '../features/auth/bloc/auth_event.dart';
import '../features/auth/data/auth_repository.dart';
import '../features/cases/bloc/case_bloc.dart';
import '../features/cases/data/case_repository.dart';
import '../features/settings/bloc/settings_bloc.dart';
import '../features/settings/bloc/settings_event.dart';
import '../features/settings/bloc/settings_state.dart';
import '../features/settings/data/settings_repository.dart';
import 'router.dart';
import 'theme.dart';

class AppBootstrap extends StatefulWidget {
  const AppBootstrap({super.key});

  @override
  State<AppBootstrap> createState() => _AppBootstrapState();
}

class _AppBootstrapState extends State<AppBootstrap> {
  late final ApiClient _apiClient;
  late final AuthRepository _authRepository;
  late final SettingsRepository _settingsRepository;
  late final BackendHttpClient _backendHttpClient;
  late final AnimalRepository _animalRepository;
  late final CaseRepository _caseRepository;

  late final AuthBloc _authBloc;
  late final SettingsBloc _settingsBloc;
  late final AnimalBloc _animalBloc;
  late final CaseBloc _caseBloc;

  late final GoRouter _router;
  StreamSubscription<void>? _sessionExpiredSub;

  @override
  void initState() {
    super.initState();

    _apiClient = ApiClient();
    _authRepository = AuthRepository(apiClient: _apiClient);
    _settingsRepository = SettingsRepository(apiClient: _apiClient);
    _backendHttpClient = BackendHttpClient();
    _animalRepository = AnimalRepository(backendClient: _backendHttpClient);
    _caseRepository = CaseRepository(backendClient: _backendHttpClient);

    _authBloc = AuthBloc(authRepository: _authRepository)
      ..add(const AuthSessionCheckRequested());
    _settingsBloc = SettingsBloc(settingsRepository: _settingsRepository)
      ..add(const SettingsLoadedRequested());
    _animalBloc = AnimalBloc(
      animalRepository: _animalRepository,
      caseRepository: _caseRepository,
    );
    _caseBloc = CaseBloc(
      caseRepository: _caseRepository,
      animalRepository: _animalRepository,
      settingsRepository: _settingsRepository,
    );

    _router = buildRouter(authBloc: _authBloc);

    // Auto-logout when the backend returns a persistent 401 (expired/invalid token).
    _sessionExpiredSub = session.onSessionExpired.listen((_) {
      _authBloc.add(const AuthLogoutRequested());
    });
  }

  @override
  void dispose() {
    _sessionExpiredSub?.cancel();
    _router.dispose();
    _authBloc.close();
    _settingsBloc.close();
    _animalBloc.close();
    _caseBloc.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MultiRepositoryProvider(
      providers: [
        RepositoryProvider.value(value: _apiClient),
        RepositoryProvider.value(value: _backendHttpClient),
        RepositoryProvider.value(value: _authRepository),
        RepositoryProvider.value(value: _settingsRepository),
        RepositoryProvider.value(value: _animalRepository),
        RepositoryProvider.value(value: _caseRepository),
      ],
      child: MultiBlocProvider(
        providers: [
          BlocProvider.value(value: _authBloc),
          BlocProvider.value(value: _settingsBloc),
          BlocProvider.value(value: _animalBloc),
          BlocProvider.value(value: _caseBloc),
        ],
        child: BlocBuilder<SettingsBloc, SettingsState>(
          builder: (context, settingsState) {
            return MaterialApp.router(
              debugShowCheckedModeBanner: false,
              title: 'SudVet',
              theme: buildAppTheme(),
              darkTheme: buildAppDarkTheme(),
              themeMode: _themeModeFromString(settingsState.themeMode),
              routerConfig: _router,
            );
          },
        ),
      ),
    );
  }

  ThemeMode _themeModeFromString(String value) {
    return switch (value.trim().toLowerCase()) {
      'dark' => ThemeMode.dark,
      'light' => ThemeMode.light,
      _ => ThemeMode.system,
    };
  }
}
