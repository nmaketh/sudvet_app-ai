import 'dart:async';
import 'dart:typed_data';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../core/api/api_client.dart';
import '../../animals/data/animal_repository.dart';
import '../../settings/data/settings_repository.dart';
import '../data/case_repository.dart';
import 'case_event.dart';
import 'case_state.dart';

class CaseBloc extends Bloc<CaseEvent, CaseState> {
  CaseBloc({
    required CaseRepository caseRepository,
    required AnimalRepository animalRepository,
    required SettingsRepository settingsRepository,
    Connectivity? connectivity,
  }) : _caseRepository = caseRepository,
       _animalRepository = animalRepository,
       _settingsRepository = settingsRepository,
       _connectivity = connectivity ?? Connectivity(),
       super(CaseState.initial()) {
    on<CaseBootstrapRequested>(_onBootstrapRequested);
    on<CaseDashboardRefreshRequested>(_onDashboardRefreshRequested);
    on<CaseHistoryRequested>(_onHistoryRequested);
    on<CaseSearchChanged>(_onSearchChanged);
    on<CaseHistoryAnimalFilterChanged>(_onHistoryAnimalFilterChanged);
    on<CaseStatusFilterChanged>(_onStatusFilterChanged);
    on<CaseDiseaseFilterChanged>(_onDiseaseFilterChanged);
    on<CaseDraftAnimalChanged>(_onDraftAnimalChanged);
    on<CaseOpenedById>(_onCaseOpenedById);
    on<CasePredictionSubmitted>(_onCasePredictionSubmitted);
    on<CasePendingSyncRequested>(_onPendingSyncRequested);
    on<CaseSyncByIdRequested>(_onSyncByIdRequested);
    on<CaseFollowUpStatusChanged>(_onFollowUpChanged);
    on<CaseNotesSaved>(_onCaseNotesSaved);
    on<CaseDeleted>(_onCaseDeleted);
    on<CaseConnectivityChanged>(_onConnectivityChanged);
    on<CaseSubmissionHandled>(_onSubmissionHandled);
    on<CaseFeedbackCleared>(_onFeedbackCleared);

    _connectivitySubscription = _connectivity.onConnectivityChanged.listen((dynamic results) {
      add(CaseConnectivityChanged(_isOffline(results)));
    });

    add(const CaseBootstrapRequested());
  }

  final CaseRepository _caseRepository;
  final AnimalRepository _animalRepository;
  final SettingsRepository _settingsRepository;
  final Connectivity _connectivity;
  late final StreamSubscription<dynamic> _connectivitySubscription;

  @override
  Future<void> close() async {
    await _connectivitySubscription.cancel();
    return super.close();
  }

  Future<void> _onBootstrapRequested(
    CaseBootstrapRequested event,
    Emitter<CaseState> emit,
  ) async {
    emit(
      state.copyWith(
        isLoading: true,
        clearErrorMessage: true,
        clearInfoMessage: true,
      ),
    );

    try {
      await _caseRepository.initialize();
      await _animalRepository.initialize();
      final currentConnectivity = await _connectivity.checkConnectivity();
      final isOffline = _isOffline(currentConnectivity);

      emit(state.copyWith(isOffline: isOffline));
      await _refreshCollections(emit);

      emit(state.copyWith(isLoading: false));

      final settings = await _settingsRepository.load();
      if (!isOffline && !settings.offlineOnly) {
        add(const CasePendingSyncRequested(automatic: true));
      }
    } catch (_) {
      emit(
        state.copyWith(
          isLoading: false,
          errorMessage: 'Data storage could not be initialized. Restart app and try again.',
        ),
      );
    }
  }

  Future<void> _onDashboardRefreshRequested(
    CaseDashboardRefreshRequested event,
    Emitter<CaseState> emit,
  ) async {
    emit(state.copyWith(isLoading: true, clearErrorMessage: true));
    await _refreshCollections(emit);
    emit(state.copyWith(isLoading: false));
  }

  Future<void> _onHistoryRequested(
    CaseHistoryRequested event,
    Emitter<CaseState> emit,
  ) async {
    final history = await _caseRepository.getHistory(
      query: state.searchQuery,
      animalId: state.historyAnimalId,
      statusFilter: state.statusFilter,
      diseaseFilter: state.diseaseFilter,
    );

    emit(state.copyWith(historyCases: history));
  }

  Future<void> _onSearchChanged(
    CaseSearchChanged event,
    Emitter<CaseState> emit,
  ) async {
    emit(state.copyWith(searchQuery: event.query));
    add(const CaseHistoryRequested());
  }

  Future<void> _onHistoryAnimalFilterChanged(
    CaseHistoryAnimalFilterChanged event,
    Emitter<CaseState> emit,
  ) async {
    emit(
      state.copyWith(
        historyAnimalId: event.animalId,
        clearErrorMessage: true,
      ),
    );
    add(const CaseHistoryRequested());
  }

  Future<void> _onStatusFilterChanged(
    CaseStatusFilterChanged event,
    Emitter<CaseState> emit,
  ) async {
    emit(state.copyWith(statusFilter: event.filter));
    add(const CaseHistoryRequested());
  }

  Future<void> _onDiseaseFilterChanged(
    CaseDiseaseFilterChanged event,
    Emitter<CaseState> emit,
  ) async {
    emit(state.copyWith(diseaseFilter: event.filter));
    add(const CaseHistoryRequested());
  }

  Future<void> _onDraftAnimalChanged(
    CaseDraftAnimalChanged event,
    Emitter<CaseState> emit,
  ) async {
    emit(
      state.copyWith(
        draftAnimalId: event.animalId,
        clearErrorMessage: true,
      ),
    );
  }

  Future<void> _onCaseOpenedById(
    CaseOpenedById event,
    Emitter<CaseState> emit,
  ) async {
    final selected = await _caseRepository.getCaseById(event.caseId);
    emit(state.copyWith(selectedCase: selected));
  }

  Future<void> _onCasePredictionSubmitted(
    CasePredictionSubmitted event,
    Emitter<CaseState> emit,
  ) async {
    final hasAnySymptom = event.symptoms.values.any((value) => value);
    final hasInput = event.imageFiles.isNotEmpty || hasAnySymptom || event.temperature != null;

    if (!hasInput) {
      emit(
        state.copyWith(
          errorMessage: 'Add an image and/or symptoms before starting prediction.',
          clearInfoMessage: true,
        ),
      );
      return;
    }

    emit(
      state.copyWith(
        isSubmitting: true,
        clearErrorMessage: true,
        clearInfoMessage: true,
      ),
    );

    final settings = await _settingsRepository.load();
    final shouldSync = !settings.offlineOnly && !state.isOffline;
    final imageBytesList = <Uint8List>[];
    final imageFileNames = <String>[];
    final imagePaths = <String>[];
    for (final image in event.imageFiles.take(3)) {
      try {
        final bytes = await image.readAsBytes();
        if (bytes.isNotEmpty) {
          imageBytesList.add(bytes);
          imageFileNames.add(image.name);
          imagePaths.add(image.path);
        }
      } catch (_) {
        // Ignore unreadable image and continue with others.
      }
    }
    try {
      final submitResult = await _caseRepository.submitCase(
        animalId: event.animalId,
        symptoms: event.symptoms,
        temperature: event.temperature,
        severity: event.severity,
        imagePaths: imagePaths,
        imageBytesList: imageBytesList,
        imageFileNames: imageFileNames,
        vetEmail: settings.vetEmail,
        attachments: event.attachments,
        notes: event.notes,
        shouldAttemptSync: shouldSync,
        allowAssignment: false,
        apiBaseUrl: settings.apiBaseUrl,
      );

      await _refreshCollections(emit);

      final infoMessage = submitResult.syncedImmediately
          ? 'Prediction complete.'
          : 'Case saved as pending. Sync when API is reachable.';

      emit(
        state.copyWith(
          isSubmitting: false,
          selectedCase: submitResult.record,
          pendingNavigationCaseId: submitResult.record.id,
          infoMessage: infoMessage,
          errorMessage: submitResult.warningMessage,
        ),
      );
    } on ApiException catch (e) {
      emit(
        state.copyWith(
          isSubmitting: false,
          errorMessage: e.message,
        ),
      );
    } catch (_) {
      emit(
        state.copyWith(
          isSubmitting: false,
          errorMessage: 'Unable to submit case right now.',
        ),
      );
    }
  }

  Future<void> _onPendingSyncRequested(
    CasePendingSyncRequested event,
    Emitter<CaseState> emit,
  ) async {
    final settings = await _settingsRepository.load();
    if (settings.offlineOnly) {
      if (!event.automatic) {
        emit(
          state.copyWith(
            infoMessage: 'Offline-only mode is enabled. Disable it in settings to sync.',
            clearErrorMessage: true,
          ),
        );
      }
      return;
    }

    if (state.isOffline) {
      if (!event.automatic) {
        emit(
          state.copyWith(
            infoMessage: 'No connection. Pending cases will sync once online.',
            clearErrorMessage: true,
          ),
        );
      }
      return;
    }

    emit(
      state.copyWith(
        isSyncing: true,
        clearErrorMessage: true,
        clearInfoMessage: true,
      ),
    );

    final result = await _caseRepository.syncPending(
      offlineOnly: settings.offlineOnly,
      apiBaseUrl: settings.apiBaseUrl,
    );

    await _refreshCollections(emit);

    String? info;
    String? error;

    if (result.syncedCount > 0) {
      info = 'Synced ${result.syncedCount} pending case(s).';
    } else if (!event.automatic) {
      info = 'No pending cases synced.';
    }

    if (result.failedCount > 0 && !event.automatic) {
      error = result.errorMessage ?? '${result.failedCount} case(s) could not sync and remain pending.';
    }

    emit(
      state.copyWith(
        isSyncing: false,
        infoMessage: info,
        errorMessage: error,
      ),
    );
  }

  Future<void> _onSyncByIdRequested(
    CaseSyncByIdRequested event,
    Emitter<CaseState> emit,
  ) async {
    emit(
      state.copyWith(
        isSyncing: true,
        clearInfoMessage: true,
        clearErrorMessage: true,
      ),
    );

    final settings = await _settingsRepository.load();
    final result = await _caseRepository.syncCaseById(
      caseId: event.caseId,
      apiBaseUrl: settings.apiBaseUrl,
      offlineOnly: settings.offlineOnly,
    );

    await _refreshCollections(emit);
    final selected = await _caseRepository.getCaseById(event.caseId);

    emit(
      state.copyWith(
        isSyncing: false,
        selectedCase: selected,
        infoMessage: result.syncedCount > 0 ? 'Case synced successfully.' : null,
        errorMessage: result.syncedCount == 0 ? result.errorMessage : null,
      ),
    );
  }

  Future<void> _onFollowUpChanged(
    CaseFollowUpStatusChanged event,
    Emitter<CaseState> emit,
  ) async {
    await _caseRepository.updateFollowUpStatus(
      caseId: event.caseId,
      followUpStatus: event.followUpStatus,
    );
    await _refreshCollections(emit);
    final selected = await _caseRepository.getCaseById(event.caseId);
    emit(state.copyWith(selectedCase: selected, infoMessage: 'Follow-up updated.'));
  }

  Future<void> _onCaseNotesSaved(
    CaseNotesSaved event,
    Emitter<CaseState> emit,
  ) async {
    await _caseRepository.updateCaseNotes(caseId: event.caseId, notes: event.notes);
    final selected = await _caseRepository.getCaseById(event.caseId);
    emit(state.copyWith(selectedCase: selected, infoMessage: 'Notes saved.'));
    await _refreshCollections(emit);
  }

  Future<void> _onCaseDeleted(
    CaseDeleted event,
    Emitter<CaseState> emit,
  ) async {
    await _caseRepository.deleteCase(event.caseId);
    await _refreshCollections(emit);
    emit(
      state.copyWith(
        clearSelectedCase: true,
        infoMessage: 'Case deleted.',
      ),
    );
  }

  Future<void> _onConnectivityChanged(
    CaseConnectivityChanged event,
    Emitter<CaseState> emit,
  ) async {
    if (event.isOffline == state.isOffline) {
      return;
    }

    emit(
      state.copyWith(
        isOffline: event.isOffline,
        infoMessage: event.isOffline ? 'You are offline.' : 'Back online.',
        clearErrorMessage: true,
      ),
    );

    if (!event.isOffline) {
      final settings = await _settingsRepository.load();
      if (!settings.offlineOnly && state.pendingUploads > 0) {
        add(const CasePendingSyncRequested(automatic: true));
      }
    }
  }

  Future<void> _onSubmissionHandled(
    CaseSubmissionHandled event,
    Emitter<CaseState> emit,
  ) async {
    emit(state.copyWith(clearPendingNavigationCaseId: true));
  }

  Future<void> _onFeedbackCleared(
    CaseFeedbackCleared event,
    Emitter<CaseState> emit,
  ) async {
    emit(state.copyWith(clearErrorMessage: true, clearInfoMessage: true));
  }

  Future<void> _refreshCollections(Emitter<CaseState> emit) async {
    try {
      final stats = await _caseRepository.getDashboardStats();
      final recent = await _caseRepository.getRecentCases(limit: 5);
      final history = await _caseRepository.getHistory(
        query: state.searchQuery,
        animalId: state.historyAnimalId,
        statusFilter: state.statusFilter,
        diseaseFilter: state.diseaseFilter,
      );
      final animals = await _animalRepository.list();
      final pending = await _caseRepository.getPendingCount();

      emit(
        state.copyWith(
          stats: stats,
          recentCases: recent,
          historyCases: history,
          animals: animals,
          pendingUploads: pending,
        ),
      );
    } on ApiException catch (e) {
      emit(state.copyWith(errorMessage: e.message));
    } catch (_) {
      emit(state.copyWith(errorMessage: 'Unable to refresh backend data right now.'));
    }
  }

  bool _isOffline(dynamic raw) {
    if (raw is ConnectivityResult) {
      return raw == ConnectivityResult.none;
    }

    if (raw is List<ConnectivityResult>) {
      if (raw.isEmpty) {
        return true;
      }
      return raw.every((item) => item == ConnectivityResult.none);
    }

    return true;
  }
}
