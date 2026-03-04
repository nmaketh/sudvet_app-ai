import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../widgets/app_text_field.dart';
import '../../../widgets/primary_button.dart';
import '../../cases/bloc/case_bloc.dart';
import '../../cases/bloc/case_event.dart';
import '../bloc/animal_bloc.dart';
import '../bloc/animal_event.dart';
import '../bloc/animal_state.dart';

class AnimalNewPage extends StatefulWidget {
  const AnimalNewPage({super.key, this.returnCreatedId = false});

  final bool returnCreatedId;

  @override
  State<AnimalNewPage> createState() => _AnimalNewPageState();
}

class _AnimalNewPageState extends State<AnimalNewPage> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _ageMonthsController = TextEditingController();
  final _locationController = TextEditingController();
  final _notesController = TextEditingController();
  DateTime? _selectedDob;

  @override
  void dispose() {
    _nameController.dispose();
    _ageMonthsController.dispose();
    _locationController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  Future<void> _selectDob() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDob ?? now.subtract(const Duration(days: 365 * 2)),
      firstDate: DateTime(2000),
      lastDate: now,
    );
    if (!mounted || picked == null) {
      return;
    }
    setState(() => _selectedDob = picked);
  }

  void _save() {
    FocusScope.of(context).unfocus();
    if (!_formKey.currentState!.validate()) {
      return;
    }

    final ageMonths = int.tryParse(_ageMonthsController.text.trim());
    final dob = _selectedDob ??
        (ageMonths == null ? null : DateTime.now().subtract(Duration(days: ageMonths * 30)));

    context.read<AnimalBloc>().add(
      AnimalAddRequested(
        name: _nameController.text.trim(),
        dob: dob,
        location: _locationController.text.trim(),
        notes: _notesController.text.trim(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return BlocListener<AnimalBloc, AnimalState>(
      listenWhen: (previous, current) =>
          previous.createdAnimalId != current.createdAnimalId ||
          previous.infoMessage != current.infoMessage ||
          previous.errorMessage != current.errorMessage,
      listener: (context, state) {
        final messenger = ScaffoldMessenger.of(context);

        if (state.errorMessage != null) {
          messenger.showSnackBar(SnackBar(content: Text(state.errorMessage!)));
          context.read<AnimalBloc>().add(const AnimalFeedbackCleared());
        }

        final newId = state.createdAnimalId;
        if (newId == null || newId.isEmpty) {
          return;
        }

        context.read<AnimalBloc>().add(const AnimalCreationHandled());
        context.read<CaseBloc>().add(const CaseDashboardRefreshRequested());

        if (widget.returnCreatedId) {
          context.pop(newId);
          return;
        }

        context.go('/app/animal/$newId');
      },
      child: Scaffold(
        appBar: AppBar(title: const Text('Add Animal')),
        body: BlocBuilder<AnimalBloc, AnimalState>(
          builder: (context, state) {
            return ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Text(
                  'Tag is auto-generated (example: COW-8F3K2A).',
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
                const SizedBox(height: 12),
                Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      AppTextField(
                        controller: _nameController,
                        label: 'Nickname / Name (optional)',
                        hint: 'Amina',
                        prefixIcon: Icons.pets_rounded,
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: AppTextField(
                              controller: _ageMonthsController,
                              label: 'Age (months)',
                              prefixIcon: Icons.calendar_month_outlined,
                              keyboardType: TextInputType.number,
                              validator: (value) {
                                if (value.trim().isEmpty) {
                                  return null;
                                }
                                if (int.tryParse(value.trim()) == null) {
                                  return 'Enter a valid number';
                                }
                                return null;
                              },
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed: _selectDob,
                              icon: const Icon(Icons.event_outlined),
                              label: Text(
                                _selectedDob == null
                                    ? 'Pick DOB'
                                    : DateFormat('MMM d, y').format(_selectedDob!),
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      AppTextField(
                        controller: _locationController,
                        label: 'Location (optional)',
                        hint: 'North Barn',
                        prefixIcon: Icons.place_outlined,
                      ),
                      const SizedBox(height: 12),
                      AppTextField(
                        controller: _notesController,
                        label: 'Notes (optional)',
                        prefixIcon: Icons.sticky_note_2_outlined,
                        minLines: 3,
                        maxLines: 4,
                      ),
                      const SizedBox(height: 16),
                      PrimaryButton(
                        label: 'Save Animal',
                        icon: Icons.check_circle_outline_rounded,
                        isLoading: state.isSaving,
                        onPressed: _save,
                      ),
                    ],
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}
