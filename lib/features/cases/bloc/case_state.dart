import 'package:equatable/equatable.dart';

import '../model/animal_profile.dart';
import '../model/case_record.dart';
import '../model/dashboard_stats.dart';

class CaseState extends Equatable {
  const CaseState({
    required this.isLoading,
    required this.isSubmitting,
    required this.isSyncing,
    required this.isOffline,
    required this.pendingUploads,
    required this.stats,
    required this.recentCases,
    required this.historyCases,
    required this.animals,
    required this.searchQuery,
    required this.statusFilter,
    required this.diseaseFilter,
    this.historyAnimalId,
    this.draftAnimalId,
    this.selectedCase,
    this.pendingNavigationCaseId,
    this.errorMessage,
    this.infoMessage,
  });

  final bool isLoading;
  final bool isSubmitting;
  final bool isSyncing;
  final bool isOffline;
  final int pendingUploads;
  final DashboardStats stats;
  final List<CaseRecord> recentCases;
  final List<CaseRecord> historyCases;
  final List<AnimalProfile> animals;
  final String searchQuery;
  final String? historyAnimalId;
  final CaseStatusFilter statusFilter;
  final DiseaseFilter diseaseFilter;
  final String? draftAnimalId;
  final CaseRecord? selectedCase;
  final String? pendingNavigationCaseId;
  final String? errorMessage;
  final String? infoMessage;

  factory CaseState.initial() {
    return CaseState(
      isLoading: true,
      isSubmitting: false,
      isSyncing: false,
      isOffline: false,
      pendingUploads: 0,
      stats: DashboardStats.empty(),
      recentCases: const [],
      historyCases: const [],
      animals: const [],
      searchQuery: '',
      statusFilter: CaseStatusFilter.all,
      diseaseFilter: DiseaseFilter.all,
    );
  }

  CaseState copyWith({
    bool? isLoading,
    bool? isSubmitting,
    bool? isSyncing,
    bool? isOffline,
    int? pendingUploads,
    DashboardStats? stats,
    List<CaseRecord>? recentCases,
    List<CaseRecord>? historyCases,
    List<AnimalProfile>? animals,
    String? searchQuery,
    String? historyAnimalId,
    bool clearHistoryAnimalId = false,
    CaseStatusFilter? statusFilter,
    DiseaseFilter? diseaseFilter,
    String? draftAnimalId,
    bool clearDraftAnimalId = false,
    CaseRecord? selectedCase,
    bool clearSelectedCase = false,
    String? pendingNavigationCaseId,
    bool clearPendingNavigationCaseId = false,
    String? errorMessage,
    bool clearErrorMessage = false,
    String? infoMessage,
    bool clearInfoMessage = false,
  }) {
    return CaseState(
      isLoading: isLoading ?? this.isLoading,
      isSubmitting: isSubmitting ?? this.isSubmitting,
      isSyncing: isSyncing ?? this.isSyncing,
      isOffline: isOffline ?? this.isOffline,
      pendingUploads: pendingUploads ?? this.pendingUploads,
      stats: stats ?? this.stats,
      recentCases: recentCases ?? this.recentCases,
      historyCases: historyCases ?? this.historyCases,
      animals: animals ?? this.animals,
      searchQuery: searchQuery ?? this.searchQuery,
      historyAnimalId: clearHistoryAnimalId
          ? null
          : (historyAnimalId ?? this.historyAnimalId),
      statusFilter: statusFilter ?? this.statusFilter,
      diseaseFilter: diseaseFilter ?? this.diseaseFilter,
      draftAnimalId: clearDraftAnimalId
          ? null
          : (draftAnimalId ?? this.draftAnimalId),
      selectedCase: clearSelectedCase
          ? null
          : (selectedCase ?? this.selectedCase),
      pendingNavigationCaseId: clearPendingNavigationCaseId
          ? null
          : (pendingNavigationCaseId ?? this.pendingNavigationCaseId),
      errorMessage: clearErrorMessage
          ? null
          : (errorMessage ?? this.errorMessage),
      infoMessage: clearInfoMessage ? null : (infoMessage ?? this.infoMessage),
    );
  }

  @override
  List<Object?> get props => [
    isLoading,
    isSubmitting,
    isSyncing,
    isOffline,
    pendingUploads,
    stats,
    recentCases,
    historyCases,
    animals,
    searchQuery,
    historyAnimalId,
    statusFilter,
    diseaseFilter,
    draftAnimalId,
    selectedCase,
    pendingNavigationCaseId,
    errorMessage,
    infoMessage,
  ];
}
