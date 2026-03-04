import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';

import '../../../widgets/primary_button.dart';
import '../bloc/case_bloc.dart';
import '../bloc/case_event.dart';
import '../bloc/case_state.dart';
import '../model/animal_profile.dart';

class NewCasePage extends StatefulWidget {
  const NewCasePage({super.key, this.preselectedAnimalId});

  final String? preselectedAnimalId;

  @override
  State<NewCasePage> createState() => _NewCasePageState();
}

class _NewCasePageState extends State<NewCasePage> {
  final _temperatureController = TextEditingController();
  final _notesController = TextEditingController();

  final _symptoms = <String, bool>{
    'fever': false,
    'loss_of_appetite': false,
    'depression': false,
    'painless_lumps': false,
    'skin_nodules': false,
    'enlarged_lymph_nodes': false,
    'mouth_blisters': false,
    'tongue_sores': false,
    'foot_lesions': false,
    'drooling': false,
    'lameness': false,
    'nasal_discharge': false,
    'eye_discharge': false,
    'difficulty_breathing': false,
    'swollen_lymph_nodes': false,
    'coughing': false,
    'rapid_shallow_breathing': false,
    'chest_pain_signs': false,
    'diarrhoea': false,
    'corneal_opacity': false,
  };

  int _currentStep = 0;
  double _severity = 0.5;
  final List<XFile> _selectedImages = [];
  String? _selectedAnimalId;
  bool _quickCase = false;

  @override
  void initState() {
    super.initState();
    _selectedAnimalId = widget.preselectedAnimalId;
    if (_selectedAnimalId != null && _selectedAnimalId!.trim().isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        context.read<CaseBloc>().add(CaseDraftAnimalChanged(_selectedAnimalId));
      });
    }
  }

  @override
  void dispose() {
    _temperatureController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  Future<void> _pickImage(ImageSource source) async {
    final picker = ImagePicker();
    if (source == ImageSource.gallery) {
      final picked = await picker.pickMultiImage(imageQuality: 90);
      if (!mounted || picked.isEmpty) {
        return;
      }
      setState(() {
        for (final file in picked) {
          if (_selectedImages.length >= 3) {
            break;
          }
          _selectedImages.add(file);
        }
      });
      return;
    }
    final file = await picker.pickImage(source: source, imageQuality: 90);
    if (!mounted || file == null) {
      return;
    }
    setState(() {
      if (_selectedImages.length >= 3) {
        _selectedImages.removeAt(0);
      }
      _selectedImages.add(file);
    });
  }

  AnimalProfile? _selectedAnimal(CaseState state) {
    if (_selectedAnimalId == null || _quickCase) {
      return null;
    }

    try {
      return state.animals.firstWhere((item) => item.id == _selectedAnimalId);
    } catch (_) {
      return null;
    }
  }

  bool _validateStep(CaseState state) {
    if (_currentStep == 0 && !_quickCase && _selectedAnimal(state) == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please choose an animal or enable Quick Case.')),
      );
      return false;
    }
    return true;
  }

  void _onContinue(CaseState state) {
    if (!_validateStep(state)) {
      return;
    }

    if (_currentStep < 3) {
      setState(() => _currentStep += 1);
      return;
    }

    _submit(state);
  }

  void _submit(CaseState state) {
    final animal = _selectedAnimal(state);
    final temperature = double.tryParse(_temperatureController.text.trim());

    context.read<CaseBloc>().add(
      CasePredictionSubmitted(
        animalId: _quickCase ? null : animal?.id,
        // Only send symptoms the user explicitly toggled ON.
        // Sending absent (false) symptoms as negative evidence skews the
        // Bayesian classifier toward "Normal" when no symptoms are selected.
        symptoms: Map.fromEntries(_symptoms.entries.where((e) => e.value)),
        temperature: temperature,
        severity: _severity,
        imageFiles: List<XFile>.from(_selectedImages),
        notes: _notesController.text.trim(),
        attachments: _selectedImages.map((e) => e.path).toList(growable: false),
      ),
    );
  }

  String _friendlySubmissionFeedback(String message) {
    final raw = message.trim();
    if (raw.isEmpty) {
      return raw;
    }
    final lower = raw.toLowerCase();
    if (lower.contains('likely not cattle') ||
        (lower.contains('not cattle') && lower.contains('image rejected'))) {
      return 'Image rejected: this does not appear to be a cow/cattle image. '
          'Use a real cow photo (not a drawing/screenshot) and capture the lesion area clearly.';
    }
    if (lower.contains('backend request failed')) {
      return 'Request failed. Check API URL/network and try again.';
    }
    return raw;
  }

  Future<void> _createAnimalQuickly() async {
    final result = await context.push<String>('/app/animal/new?select=1');
    if (!mounted) {
      return;
    }

    context.read<CaseBloc>().add(const CaseDashboardRefreshRequested());
    if (result != null && result.trim().isNotEmpty) {
      setState(() {
        _quickCase = false;
        _selectedAnimalId = result;
      });
      context.read<CaseBloc>().add(CaseDraftAnimalChanged(result));
    }
  }

  @override
  Widget build(BuildContext context) {
    return BlocListener<CaseBloc, CaseState>(
      listenWhen: (previous, current) =>
          previous.pendingNavigationCaseId != current.pendingNavigationCaseId ||
          previous.infoMessage != current.infoMessage ||
          previous.errorMessage != current.errorMessage,
      listener: (context, state) {
        final messenger = ScaffoldMessenger.of(context);
        if (state.errorMessage != null) {
          messenger.showSnackBar(
            SnackBar(content: Text(_friendlySubmissionFeedback(state.errorMessage!))),
          );
          context.read<CaseBloc>().add(const CaseFeedbackCleared());
          return;
        }
        if (state.infoMessage != null) {
          messenger.showSnackBar(SnackBar(content: Text(state.infoMessage!)));
          context.read<CaseBloc>().add(const CaseFeedbackCleared());
        }
        final caseId = state.pendingNavigationCaseId;
        if (caseId == null) {
          return;
        }
        context.read<CaseBloc>().add(const CaseSubmissionHandled());
        context.go('/app/result/$caseId');
      },
      child: Scaffold(
        appBar: AppBar(title: const Text('New Case Wizard')),
        body: BlocBuilder<CaseBloc, CaseState>(
          builder: (context, state) {
            final selectedAnimal = _selectedAnimal(state);

            return ListView(
              padding: const EdgeInsets.all(12),
              children: [
                Stepper(
                  currentStep: _currentStep,
                  onStepContinue: state.isSubmitting ? null : () => _onContinue(state),
                  onStepCancel: _currentStep == 0 ? null : () => setState(() => _currentStep -= 1),
                  controlsBuilder: (context, details) {
                    return Padding(
                      padding: const EdgeInsets.only(top: 12),
                      child: Row(
                        children: [
                          Expanded(
                            child: PrimaryButton(
                              label: _currentStep == 3 ? 'Save & Predict' : 'Continue',
                              icon: _currentStep == 3
                                  ? Icons.analytics_rounded
                                  : Icons.arrow_forward_rounded,
                              isLoading: state.isSubmitting && _currentStep == 3,
                              onPressed: details.onStepContinue,
                            ),
                          ),
                          const SizedBox(width: 10),
                          if (_currentStep > 0)
                            Expanded(
                              child: OutlinedButton(
                                onPressed: details.onStepCancel,
                                child: const Text('Back'),
                              ),
                            ),
                        ],
                      ),
                    );
                  },
                  steps: [
                    Step(
                      title: const Text('Choose Animal'),
                      subtitle: const Text('Select profile or use Quick Case'),
                      isActive: _currentStep >= 0,
                      content: _AnimalSelectorStep(
                        animals: state.animals,
                        selectedAnimalId: _selectedAnimalId,
                        quickCase: _quickCase,
                        onAnimalChanged: (value) {
                          setState(() {
                            _selectedAnimalId = value;
                            _quickCase = false;
                          });
                          context.read<CaseBloc>().add(CaseDraftAnimalChanged(value));
                        },
                        onQuickCaseChanged: (value) {
                          setState(() {
                            _quickCase = value;
                            if (value) {
                              _selectedAnimalId = null;
                            }
                          });
                          context.read<CaseBloc>().add(
                            CaseDraftAnimalChanged(value ? null : _selectedAnimalId),
                          );
                        },
                        onQuickCreate: _createAnimalQuickly,
                      ),
                    ),
                    Step(
                      title: const Text('Add Image'),
                      subtitle: const Text('Camera guidance for better quality'),
                      isActive: _currentStep >= 1,
                      content: _ImageStep(
                        selectedImages: _selectedImages,
                        onPickImage: _pickImage,
                        onRemoveAt: (index) => setState(() => _selectedImages.removeAt(index)),
                      ),
                    ),
                    Step(
                      title: const Text('Symptoms'),
                      subtitle: const Text('Add symptoms and temperature'),
                      isActive: _currentStep >= 2,
                      content: _SymptomsStep(
                        symptoms: _symptoms,
                        severity: _severity,
                        temperatureController: _temperatureController,
                        notesController: _notesController,
                        onSeverityChanged: (value) => setState(() => _severity = value),
                        onSymptomChanged: (key, value) {
                          setState(() {
                            _symptoms[key] = value;
                          });
                        },
                      ),
                    ),
                    Step(
                      title: const Text('Review'),
                      subtitle: const Text('Confirm and run prediction'),
                      isActive: _currentStep >= 3,
                      content: _ReviewStep(
                        animal: selectedAnimal,
                        quickCase: _quickCase,
                        selectedImageCount: _selectedImages.length,
                        symptoms: _symptoms,
                        temperature: _temperatureController.text.trim(),
                        severity: _severity,
                      ),
                    ),
                  ],
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _AnimalSelectorStep extends StatelessWidget {
  const _AnimalSelectorStep({
    required this.animals,
    required this.selectedAnimalId,
    required this.quickCase,
    required this.onAnimalChanged,
    required this.onQuickCaseChanged,
    required this.onQuickCreate,
  });

  final List<AnimalProfile> animals;
  final String? selectedAnimalId;
  final bool quickCase;
  final ValueChanged<String?> onAnimalChanged;
  final ValueChanged<bool> onQuickCaseChanged;
  final VoidCallback onQuickCreate;

  @override
  Widget build(BuildContext context) {
    final normalizedSelection = animals.any((item) => item.id == selectedAnimalId)
        ? selectedAnimalId
        : null;

    if (animals.isEmpty) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SwitchListTile.adaptive(
            contentPadding: EdgeInsets.zero,
            value: quickCase,
            onChanged: onQuickCaseChanged,
            title: const Text('Quick Case (no animal)'),
            subtitle: const Text('Use when no profile is available in the field.'),
          ),
          const SizedBox(height: 10),
          FilledButton.icon(
            onPressed: onQuickCreate,
            icon: const Icon(Icons.add_rounded),
            label: const Text('Create Animal Profile'),
          ),
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SwitchListTile.adaptive(
          contentPadding: EdgeInsets.zero,
          value: quickCase,
          onChanged: onQuickCaseChanged,
          title: const Text('Quick Case (no animal)'),
          subtitle: const Text('Save diagnosis without linking a profile.'),
        ),
        const SizedBox(height: 8),
        DropdownButtonFormField<String>(
          key: ValueKey('animal-${normalizedSelection ?? 'none'}-${animals.length}-$quickCase'),
          initialValue: quickCase ? null : normalizedSelection,
          items: animals
              .map(
                (animal) => DropdownMenuItem<String>(
                  value: animal.id,
                  child: Text(animal.displayName),
                ),
              )
              .toList(growable: false),
          onChanged: quickCase ? null : onAnimalChanged,
          decoration: const InputDecoration(
            labelText: 'Animal',
            prefixIcon: Icon(Icons.pets_rounded),
          ),
        ),
        const SizedBox(height: 12),
        Align(
          alignment: Alignment.centerLeft,
          child: OutlinedButton.icon(
            onPressed: onQuickCreate,
            icon: const Icon(Icons.add_circle_outline_rounded),
            label: const Text('Quick create animal'),
          ),
        ),
      ],
    );
  }
}

class _ImageStep extends StatelessWidget {
  const _ImageStep({
    required this.selectedImages,
    required this.onPickImage,
    required this.onRemoveAt,
  });

  final List<XFile> selectedImages;
  final Future<void> Function(ImageSource source) onPickImage;
  final ValueChanged<int> onRemoveAt;
  static const _warmSurface = Color(0xFFF7F5EF);
  static const _warmBorder = Color(0xFFD8DCCF);
  static const _tipBg = Color(0xFFFBF4E1);
  static const _tipBorder = Color(0xFFE3D1A8);

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: _tipBg,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: _tipBorder),
          ),
          child: const Text(
            'Use up to 3 real cow photos. Close-ups of mouth/nose/skin lesions are accepted, '
            'but drawings, screenshots, and non-cattle images will be rejected.',
            style: TextStyle(fontWeight: FontWeight.w600, color: Color(0xFF5F4A1B)),
          ),
        ),
        const SizedBox(height: 10),
        Stack(
          children: [
            AspectRatio(
              aspectRatio: 1.8,
              child: Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(14),
                  color: _warmSurface,
                  border: Border.all(color: _warmBorder),
                ),
                child: selectedImages.isEmpty
                    ? const Center(child: Text('No image selected'))
                    : Row(
                        children: selectedImages.take(3).toList(growable: false).asMap().entries.map((entry) {
                          final index = entry.key;
                          final image = entry.value;
                          return Expanded(
                            child: Padding(
                              padding: const EdgeInsets.all(4),
                              child: Stack(
                                children: [
                                  Positioned.fill(
                                    child: FutureBuilder<Uint8List>(
                                      future: image.readAsBytes(),
                                      builder: (context, snapshot) {
                                        if (!snapshot.hasData) {
                                          return const Center(child: CircularProgressIndicator());
                                        }
                                        return ClipRRect(
                                          borderRadius: BorderRadius.circular(10),
                                          child: Image.memory(snapshot.data!, fit: BoxFit.cover),
                                        );
                                      },
                                    ),
                                  ),
                                  Positioned(
                                    top: 6,
                                    right: 6,
                                    child: InkWell(
                                      onTap: () => onRemoveAt(index),
                                      child: Container(
                                        decoration: BoxDecoration(
                                          color: Colors.black.withValues(alpha: 0.55),
                                          shape: BoxShape.circle,
                                        ),
                                        child: const Padding(
                                          padding: EdgeInsets.all(4),
                                          child: Icon(Icons.close, size: 14, color: Colors.white),
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          );
                        }).toList(growable: false),
                      ),
              ),
            ),
            Positioned(
              right: 10,
              top: 10,
              child: Container(
                decoration: BoxDecoration(
                  color: const Color(0xFF1F5C3A).withValues(alpha: 0.82),
                  borderRadius: BorderRadius.circular(999),
                ),
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                child: const Text(
                  'Tip: daylight + steady hand',
                  style: TextStyle(color: Colors.white, fontSize: 12),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: () => onPickImage(ImageSource.gallery),
                icon: const Icon(Icons.photo_library_outlined),
                label: const Text('Gallery (up to 3)'),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: OutlinedButton.icon(
                onPressed: () => onPickImage(ImageSource.camera),
                icon: const Icon(Icons.camera_alt_outlined),
                label: const Text('Camera'),
              ),
            ),
          ],
        ),
        if (selectedImages.isNotEmpty)
          Align(
            alignment: Alignment.centerRight,
            child: TextButton.icon(
              onPressed: () {
                for (var i = selectedImages.length - 1; i >= 0; i--) {
                  onRemoveAt(i);
                }
              },
              icon: const Icon(Icons.delete_outline_rounded),
              label: const Text('Clear images'),
            ),
          ),
      ],
    );
  }
}

class _SymptomsStep extends StatelessWidget {
  const _SymptomsStep({
    required this.symptoms,
    required this.severity,
    required this.temperatureController,
    required this.notesController,
    required this.onSeverityChanged,
    required this.onSymptomChanged,
  });

  final Map<String, bool> symptoms;
  final double severity;
  final TextEditingController temperatureController;
  final TextEditingController notesController;
  final ValueChanged<double> onSeverityChanged;
  final void Function(String key, bool value) onSymptomChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ...symptoms.entries.map((entry) {
          return SwitchListTile.adaptive(
            contentPadding: EdgeInsets.zero,
            title: Text(_labelFor(entry.key)),
            value: entry.value,
            onChanged: (value) => onSymptomChanged(entry.key, value),
          );
        }),
        const SizedBox(height: 8),
        TextField(
          controller: temperatureController,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: const InputDecoration(
            labelText: 'Temperature (deg C)',
            prefixIcon: Icon(Icons.thermostat_rounded),
          ),
        ),
        const SizedBox(height: 12),
        Text(
          'Severity (${(severity * 100).round()}%)',
          style: Theme.of(context).textTheme.titleSmall,
        ),
        Slider(
          value: severity,
          onChanged: onSeverityChanged,
          min: 0,
          max: 1,
          divisions: 10,
        ),
        const SizedBox(height: 8),
        TextField(
          controller: notesController,
          minLines: 3,
          maxLines: 4,
          decoration: const InputDecoration(
            labelText: 'Field notes',
            prefixIcon: Icon(Icons.sticky_note_2_outlined),
          ),
        ),
      ],
    );
  }

  String _labelFor(String key) {
    switch (key) {
      case 'skin_nodules':
        return 'Skin nodules';
      case 'painless_lumps':
        return 'Painless lumps';
      case 'enlarged_lymph_nodes':
        return 'Enlarged lymph nodes';
      case 'mouth_blisters':
        return 'Mouth blisters';
      case 'tongue_sores':
        return 'Tongue sores';
      case 'foot_lesions':
        return 'Foot lesions';
      case 'drooling':
        return 'Drooling';
      case 'nasal_discharge':
        return 'Nasal discharge';
      case 'eye_discharge':
        return 'Eye discharge';
      case 'difficulty_breathing':
        return 'Difficulty breathing';
      case 'loss_of_appetite':
        return 'Loss of appetite';
      case 'swollen_lymph_nodes':
        return 'Swollen lymph nodes';
      case 'rapid_shallow_breathing':
        return 'Rapid shallow breathing';
      case 'chest_pain_signs':
        return 'Chest pain signs';
      case 'corneal_opacity':
        return 'Corneal opacity';
      default:
        return key.replaceAll('_', ' ').replaceFirstMapped(
          RegExp(r'^[a-z]'),
          (match) => match.group(0)!.toUpperCase(),
        );
    }
  }
}

class _ReviewStep extends StatelessWidget {
  const _ReviewStep({
    required this.animal,
    required this.quickCase,
    required this.selectedImageCount,
    required this.symptoms,
    required this.temperature,
    required this.severity,
  });

  final AnimalProfile? animal;
  final bool quickCase;
  final int selectedImageCount;
  final Map<String, bool> symptoms;
  final String temperature;
  final double severity;
  static const _okBg = Color(0xFFE4F0E6);
  static const _okBorder = Color(0xFFD0E2D4);
  static const _warnBg = Color(0xFFF7E1DA);
  static const _warnBorder = Color(0xFFE8B8AC);

  @override
  Widget build(BuildContext context) {
    final activeSymptoms = symptoms.entries
        .where((entry) => entry.value)
        .map((entry) => entry.key.replaceAll('_', ' '))
        .toList(growable: false);

    final hasInput = selectedImageCount > 0 || activeSymptoms.isNotEmpty || temperature.isNotEmpty;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _ReviewLine(
          label: 'Animal',
          value: quickCase ? 'Quick Case (no profile)' : (animal?.displayName ?? 'Not selected'),
        ),
        _ReviewLine(label: 'Images', value: selectedImageCount == 0 ? 'None' : '$selectedImageCount attached'),
        _ReviewLine(
          label: 'Symptoms',
          value: activeSymptoms.isEmpty ? 'None selected' : activeSymptoms.join(', '),
        ),
        _ReviewLine(
          label: 'Temperature',
          value: temperature.isEmpty ? 'Not provided' : '$temperature deg C',
        ),
        _ReviewLine(label: 'Severity', value: '${(severity * 100).round()}%'),
        const SizedBox(height: 10),
        Container(
          width: double.infinity,
          decoration: BoxDecoration(
            color: hasInput ? _okBg : _warnBg,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: hasInput ? _okBorder : _warnBorder),
          ),
          padding: const EdgeInsets.all(12),
          child: Text(
            hasInput
                ? 'Ready to submit. Case is always saved locally first, then synced when possible.'
                : 'Add at least an image or symptom data before prediction.',
            style: TextStyle(
              fontWeight: FontWeight.w600,
              color: hasInput ? const Color(0xFF1F5C3A) : const Color(0xFF7B2E24),
            ),
          ),
        ),
      ],
    );
  }
}

class _ReviewLine extends StatelessWidget {
  const _ReviewLine({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 95,
            child: Text(
              '$label:',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          Expanded(child: Text(value)),
        ],
      ),
    );
  }
}
