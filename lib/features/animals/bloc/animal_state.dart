import 'package:equatable/equatable.dart';

import '../../cases/model/animal_profile.dart';
import '../../cases/model/case_record.dart';

class AnimalState extends Equatable {
  const AnimalState({
    required this.isLoading,
    required this.isSaving,
    required this.animals,
    required this.animalCases,
    required this.searchQuery,
    this.selectedAnimal,
    this.createdAnimalId,
    this.infoMessage,
    this.errorMessage,
  });

  final bool isLoading;
  final bool isSaving;
  final List<AnimalProfile> animals;
  final List<CaseRecord> animalCases;
  final String searchQuery;
  final AnimalProfile? selectedAnimal;
  final String? createdAnimalId;
  final String? infoMessage;
  final String? errorMessage;

  factory AnimalState.initial() {
    return const AnimalState(
      isLoading: true,
      isSaving: false,
      animals: [],
      animalCases: [],
      searchQuery: '',
    );
  }

  AnimalState copyWith({
    bool? isLoading,
    bool? isSaving,
    List<AnimalProfile>? animals,
    List<CaseRecord>? animalCases,
    String? searchQuery,
    AnimalProfile? selectedAnimal,
    bool clearSelectedAnimal = false,
    String? createdAnimalId,
    bool clearCreatedAnimalId = false,
    String? infoMessage,
    bool clearInfoMessage = false,
    String? errorMessage,
    bool clearErrorMessage = false,
  }) {
    return AnimalState(
      isLoading: isLoading ?? this.isLoading,
      isSaving: isSaving ?? this.isSaving,
      animals: animals ?? this.animals,
      animalCases: animalCases ?? this.animalCases,
      searchQuery: searchQuery ?? this.searchQuery,
      selectedAnimal: clearSelectedAnimal
          ? null
          : (selectedAnimal ?? this.selectedAnimal),
      createdAnimalId: clearCreatedAnimalId
          ? null
          : (createdAnimalId ?? this.createdAnimalId),
      infoMessage: clearInfoMessage ? null : (infoMessage ?? this.infoMessage),
      errorMessage: clearErrorMessage ? null : (errorMessage ?? this.errorMessage),
    );
  }

  @override
  List<Object?> get props => [
    isLoading,
    isSaving,
    animals,
    animalCases,
    searchQuery,
    selectedAnimal,
    createdAnimalId,
    infoMessage,
    errorMessage,
  ];
}
