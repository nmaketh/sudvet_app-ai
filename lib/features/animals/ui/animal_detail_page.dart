import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../widgets/empty_state.dart';
import '../../../widgets/skeleton.dart';
import '../../../widgets/status_chip.dart';
import '../bloc/animal_bloc.dart';
import '../bloc/animal_event.dart';
import '../bloc/animal_state.dart';

class AnimalDetailPage extends StatefulWidget {
  const AnimalDetailPage({super.key, required this.animalId});

  final String animalId;

  @override
  State<AnimalDetailPage> createState() => _AnimalDetailPageState();
}

class _AnimalDetailPageState extends State<AnimalDetailPage> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<AnimalBloc>().add(AnimalDetailRequested(widget.animalId));
    });
  }

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<AnimalBloc, AnimalState>(
      builder: (context, state) {
        final animal = state.selectedAnimal;
        final cases = state.animalCases;
        final isThisAnimal = animal?.id == widget.animalId;

        return Scaffold(
          appBar: AppBar(title: const Text('Animal Profile')),
          body: state.isLoading && !isThisAnimal
              ? const _AnimalDetailSkeleton()
              : !isThisAnimal
              ? const EmptyState(
                  title: 'Animal not found',
                  subtitle: 'Return to Animals list and try again.',
                  icon: Icons.search_off_rounded,
                )
              : ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              animal!.title,
                              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              animal.tagStatusLabel,
                              style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                                color: Theme.of(context).colorScheme.primary,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const SizedBox(height: 10),
                            _InfoLine(label: 'Location', value: animal.location ?? 'Not recorded'),
                            _InfoLine(label: 'DOB', value: animal.dobLabel),
                            _InfoLine(label: 'Age', value: animal.ageLabel),
                            if ((animal.notes ?? '').trim().isNotEmpty) ...[
                              const SizedBox(height: 8),
                              Text(
                                'Notes',
                                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(animal.notes!),
                            ],
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    FilledButton.icon(
                      onPressed: () => context.go('/app/new-case?animalId=${animal.id}'),
                      icon: const Icon(Icons.add_a_photo_rounded),
                      label: const Text('New Diagnosis for this Animal'),
                    ),
                    const SizedBox(height: 18),
                    Text(
                      'Health History',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const SizedBox(height: 8),
                    if (cases.isEmpty)
                      const EmptyState(
                        title: 'No cases yet',
                        subtitle: 'Create the first diagnosis to start this timeline.',
                        icon: Icons.monitor_heart_outlined,
                      )
                    else
                      ...cases.map((item) {
                        final confidence = item.confidence == null
                            ? 'No confidence'
                            : '${(item.confidence! * 100).toStringAsFixed(1)}% confidence';
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 10),
                          child: Card(
                            child: ListTile(
                              contentPadding: const EdgeInsets.symmetric(
                                horizontal: 14,
                                vertical: 10,
                              ),
                              onTap: () => context.push('/app/case/${item.id}'),
                              leading: Container(
                                width: 44,
                                height: 44,
                                decoration: BoxDecoration(
                                  color: const Color(0xFFE7F2EA),
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: const Icon(Icons.analytics_outlined),
                              ),
                              title: Text(
                                item.prediction ?? 'Pending prediction',
                                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              subtitle: Padding(
                                padding: const EdgeInsets.only(top: 6),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(DateFormat('MMM d, h:mm a').format(item.createdAt)),
                                    const SizedBox(height: 2),
                                    Text(confidence),
                                  ],
                                ),
                              ),
                              trailing: StatusChip(status: item.status),
                            ),
                          ),
                        );
                      }),
                  ],
                ),
        );
      },
    );
  }
}

class _InfoLine extends StatelessWidget {
  const _InfoLine({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        children: [
          SizedBox(
            width: 78,
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

class _AnimalDetailSkeleton extends StatelessWidget {
  const _AnimalDetailSkeleton();

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: const [
        Card(
          child: Padding(
            padding: EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SkeletonBox(height: 18, width: 180, radius: 8),
                SizedBox(height: 8),
                SkeletonBox(height: 14, width: 120, radius: 8),
                SizedBox(height: 10),
                SkeletonBox(height: 12, width: 220, radius: 8),
                SizedBox(height: 6),
                SkeletonBox(height: 12, width: 180, radius: 8),
              ],
            ),
          ),
        ),
        SizedBox(height: 12),
        SkeletonBox(height: 52, radius: 14),
        SizedBox(height: 18),
        SkeletonBox(height: 16, width: 140, radius: 8),
      ],
    );
  }
}
