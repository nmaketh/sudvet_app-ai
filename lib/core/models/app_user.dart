import 'package:equatable/equatable.dart';

class AppUser extends Equatable {
  const AppUser({
    required this.id,
    required this.name,
    required this.email,
    this.role = '',
  });

  final String id;
  final String name;
  final String email;
  /// Server-verified role: 'CAHW', 'VET', or 'ADMIN'.
  final String role;

  @override
  List<Object?> get props => [id, name, email, role];
}
