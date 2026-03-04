import 'package:equatable/equatable.dart';
import 'package:image_picker/image_picker.dart';

import '../model/case_record.dart';

abstract class CaseEvent extends Equatable {
  const CaseEvent();

  @override
  List<Object?> get props => [];
}

class CaseBootstrapRequested extends CaseEvent {
  const CaseBootstrapRequested();
}

class CaseDashboardRefreshRequested extends CaseEvent {
  const CaseDashboardRefreshRequested();
}

class CaseHistoryRequested extends CaseEvent {
  const CaseHistoryRequested();
}

class CaseSearchChanged extends CaseEvent {
  const CaseSearchChanged(this.query);

  final String query;

  @override
  List<Object?> get props => [query];
}

class CaseHistoryAnimalFilterChanged extends CaseEvent {
  const CaseHistoryAnimalFilterChanged(this.animalId);

  final String? animalId;

  @override
  List<Object?> get props => [animalId];
}

class CaseStatusFilterChanged extends CaseEvent {
  const CaseStatusFilterChanged(this.filter);

  final CaseStatusFilter filter;

  @override
  List<Object?> get props => [filter];
}

class CaseDiseaseFilterChanged extends CaseEvent {
  const CaseDiseaseFilterChanged(this.filter);

  final DiseaseFilter filter;

  @override
  List<Object?> get props => [filter];
}

class CaseDraftAnimalChanged extends CaseEvent {
  const CaseDraftAnimalChanged(this.animalId);

  final String? animalId;

  @override
  List<Object?> get props => [animalId];
}

class CaseOpenedById extends CaseEvent {
  const CaseOpenedById(this.caseId);

  final String caseId;

  @override
  List<Object?> get props => [caseId];
}

class CasePredictionSubmitted extends CaseEvent {
  const CasePredictionSubmitted({
    required this.animalId,
    required this.symptoms,
    required this.temperature,
    required this.severity,
    required this.imageFiles,
    required this.notes,
    this.attachments = const [],
  });

  final String? animalId;
  final Map<String, bool> symptoms;
  final double? temperature;
  final double? severity;
  final List<XFile> imageFiles;
  final String? notes;
  final List<String> attachments;

  @override
  List<Object?> get props => [
    animalId,
    symptoms,
    temperature,
    severity,
    imageFiles.map((e) => e.path).toList(growable: false),
    notes,
    attachments,
  ];
}

class CasePendingSyncRequested extends CaseEvent {
  const CasePendingSyncRequested({this.automatic = false});

  final bool automatic;

  @override
  List<Object?> get props => [automatic];
}

class CaseSyncByIdRequested extends CaseEvent {
  const CaseSyncByIdRequested(this.caseId);

  final String caseId;

  @override
  List<Object?> get props => [caseId];
}

class CaseFollowUpStatusChanged extends CaseEvent {
  const CaseFollowUpStatusChanged({
    required this.caseId,
    required this.followUpStatus,
  });

  final String caseId;
  final FollowUpStatus followUpStatus;

  @override
  List<Object?> get props => [caseId, followUpStatus];
}

class CaseNotesSaved extends CaseEvent {
  const CaseNotesSaved({required this.caseId, required this.notes});

  final String caseId;
  final String notes;

  @override
  List<Object?> get props => [caseId, notes];
}

class CaseDeleted extends CaseEvent {
  const CaseDeleted(this.caseId);

  final String caseId;

  @override
  List<Object?> get props => [caseId];
}

class CaseConnectivityChanged extends CaseEvent {
  const CaseConnectivityChanged(this.isOffline);

  final bool isOffline;

  @override
  List<Object?> get props => [isOffline];
}

class CaseSubmissionHandled extends CaseEvent {
  const CaseSubmissionHandled();
}

class CaseFeedbackCleared extends CaseEvent {
  const CaseFeedbackCleared();
}
