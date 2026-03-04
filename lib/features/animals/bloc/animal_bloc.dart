import 'package:flutter_bloc/flutter_bloc.dart';

import '../../cases/data/case_repository.dart';
import '../data/animal_repository.dart';
import 'animal_event.dart';
import 'animal_state.dart';

class AnimalBloc extends Bloc<AnimalEvent, AnimalState> {
  AnimalBloc({
    required AnimalRepository animalRepository,
    required CaseRepository caseRepository,
  }) : _animalRepository = animalRepository,
       _caseRepository = caseRepository,
       super(AnimalState.initial()) {
    on<AnimalLoadRequested>(_onLoadRequested);
    on<AnimalSearchChanged>(_onSearchChanged);
    on<AnimalAddRequested>(_onAddRequested);
    on<AnimalDetailRequested>(_onDetailRequested);
    on<AnimalCreationHandled>(_onCreationHandled);
    on<AnimalFeedbackCleared>(_onFeedbackCleared);

    add(const AnimalLoadRequested());
  }

  final AnimalRepository _animalRepository;
  final CaseRepository _caseRepository;

  Future<void> _onLoadRequested(
    AnimalLoadRequested event,
    Emitter<AnimalState> emit,
  ) async {
    emit(
      state.copyWith(
        isLoading: true,
        clearErrorMessage: true,
        clearInfoMessage: true,
      ),
    );

    try {
      await _animalRepository.initialize();
      final animals = await _animalRepository.list(query: state.searchQuery);
      emit(state.copyWith(isLoading: false, animals: animals));
    } catch (_) {
      emit(
        state.copyWith(
          isLoading: false,
          errorMessage: 'Unable to load animals right now.',
        ),
      );
    }
  }

  Future<void> _onSearchChanged(
    AnimalSearchChanged event,
    Emitter<AnimalState> emit,
  ) async {
    emit(state.copyWith(searchQuery: event.query));
    final animals = await _animalRepository.list(query: state.searchQuery);
    emit(state.copyWith(animals: animals));
  }

  Future<void> _onAddRequested(
    AnimalAddRequested event,
    Emitter<AnimalState> emit,
  ) async {
    emit(
      state.copyWith(
        isSaving: true,
        clearErrorMessage: true,
        clearInfoMessage: true,
      ),
    );

    try {
      final created = await _animalRepository.add(
        name: event.name,
        dob: event.dob,
        location: event.location,
        notes: event.notes,
      );
      final animals = await _animalRepository.list(query: state.searchQuery);
      emit(
        state.copyWith(
          isSaving: false,
          animals: animals,
          selectedAnimal: created,
          createdAnimalId: created.id,
          infoMessage: 'Animal profile created: ${created.tag}.',
        ),
      );
    } catch (_) {
      emit(
        state.copyWith(
          isSaving: false,
          errorMessage: 'Could not save animal. Please try again.',
        ),
      );
    }
  }

  Future<void> _onDetailRequested(
    AnimalDetailRequested event,
    Emitter<AnimalState> emit,
  ) async {
    emit(
      state.copyWith(
        isLoading: true,
        clearErrorMessage: true,
        clearInfoMessage: true,
      ),
    );

    try {
      final animal = await _animalRepository.getById(event.animalId);
      if (animal == null) {
        emit(
          state.copyWith(
            isLoading: false,
            clearSelectedAnimal: true,
            animalCases: const [],
            errorMessage: 'Animal not found.',
          ),
        );
        return;
      }
      final cases = await _caseRepository.getCasesForAnimal(event.animalId);
      emit(
        state.copyWith(
          isLoading: false,
          selectedAnimal: animal,
          animalCases: cases,
        ),
      );
    } catch (_) {
      emit(
        state.copyWith(
          isLoading: false,
          errorMessage: 'Unable to load animal details.',
        ),
      );
    }
  }

  Future<void> _onCreationHandled(
    AnimalCreationHandled event,
    Emitter<AnimalState> emit,
  ) async {
    emit(state.copyWith(clearCreatedAnimalId: true));
  }

  Future<void> _onFeedbackCleared(
    AnimalFeedbackCleared event,
    Emitter<AnimalState> emit,
  ) async {
    emit(state.copyWith(clearInfoMessage: true, clearErrorMessage: true));
  }
}
