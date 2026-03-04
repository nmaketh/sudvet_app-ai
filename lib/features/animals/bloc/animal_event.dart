import 'package:equatable/equatable.dart';

abstract class AnimalEvent extends Equatable {
  const AnimalEvent();

  @override
  List<Object?> get props => [];
}

class AnimalLoadRequested extends AnimalEvent {
  const AnimalLoadRequested();
}

class AnimalSearchChanged extends AnimalEvent {
  const AnimalSearchChanged(this.query);

  final String query;

  @override
  List<Object?> get props => [query];
}

class AnimalAddRequested extends AnimalEvent {
  const AnimalAddRequested({
    this.name,
    this.dob,
    this.location,
    this.notes,
  });

  final String? name;
  final DateTime? dob;
  final String? location;
  final String? notes;

  @override
  List<Object?> get props => [name, dob, location, notes];
}

class AnimalDetailRequested extends AnimalEvent {
  const AnimalDetailRequested(this.animalId);

  final String animalId;

  @override
  List<Object?> get props => [animalId];
}

class AnimalCreationHandled extends AnimalEvent {
  const AnimalCreationHandled();
}

class AnimalFeedbackCleared extends AnimalEvent {
  const AnimalFeedbackCleared();
}
