import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../../widgets/app_text_field.dart';
import '../../../widgets/empty_state.dart';
import '../../../widgets/skeleton.dart';
import '../bloc/animal_bloc.dart';
import '../bloc/animal_event.dart';
import '../bloc/animal_state.dart';

class AnimalsListPage extends StatefulWidget {
  const AnimalsListPage({super.key});

  @override
  State<AnimalsListPage> createState() => _AnimalsListPageState();
}

class _AnimalsListPageState extends State<AnimalsListPage> {
  final _searchController = TextEditingController();

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return BlocListener<AnimalBloc, AnimalState>(
      listenWhen: (previous, current) =>
          previous.infoMessage != current.infoMessage ||
          previous.errorMessage != current.errorMessage,
      listener: (context, state) {
        final messenger = ScaffoldMessenger.of(context);
        if (state.infoMessage != null) {
          messenger.showSnackBar(SnackBar(content: Text(state.infoMessage!)));
          context.read<AnimalBloc>().add(const AnimalFeedbackCleared());
        } else if (state.errorMessage != null) {
          messenger.showSnackBar(SnackBar(content: Text(state.errorMessage!)));
          context.read<AnimalBloc>().add(const AnimalFeedbackCleared());
        }
      },
      child: Scaffold(
        appBar: AppBar(title: const Text('Animals')),
        body: BlocBuilder<AnimalBloc, AnimalState>(
          builder: (context, state) {
            return Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
                  child: AppTextField(
                    controller: _searchController,
                    label: 'Search by name, tag, location',
                    prefixIcon: Icons.search_rounded,
                    onChanged: (value) => context.read<AnimalBloc>().add(
                      AnimalSearchChanged(value),
                    ),
                  ),
                ),
                Expanded(
                  child: state.isLoading
                      ? const _AnimalListSkeleton()
                      : state.animals.isEmpty
                      ? const EmptyState(
                          title: 'No animals yet',
                          subtitle: 'Add your first animal profile to start tracking health.',
                          icon: Icons.pets_outlined,
                        )
                      : ListView.separated(
                          padding: const EdgeInsets.all(16),
                          itemCount: state.animals.length,
                          separatorBuilder: (_, index) => const SizedBox(height: 10),
                          itemBuilder: (context, index) {
                            final animal = state.animals[index];
                            return Card(
                              child: ListTile(
                                contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 14,
                                  vertical: 10,
                                ),
                                onTap: () => context.push('/app/animal/${animal.id}'),
                                leading: Container(
                                  width: 44,
                                  height: 44,
                                  decoration: BoxDecoration(
                                    color: const Color(0xFFE7F2EA),
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: const Icon(Icons.pets_rounded),
                                ),
                                title: Text(
                                  animal.title,
                                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                subtitle: Text(animal.subtitle),
                                trailing: const Icon(Icons.chevron_right_rounded),
                              ),
                            );
                          },
                        ),
                ),
              ],
            );
          },
        ),
        floatingActionButton: FloatingActionButton.extended(
          onPressed: () => context.push('/app/animal/new'),
          icon: const Icon(Icons.add_rounded),
          label: const Text('Add Animal'),
        ),
      ),
    );
  }
}

class _AnimalListSkeleton extends StatelessWidget {
  const _AnimalListSkeleton();

  @override
  Widget build(BuildContext context) {
    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: 4,
      separatorBuilder: (_, index) => const SizedBox(height: 10),
      itemBuilder: (context, index) {
        return Card(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            child: Row(
              children: const [
                SkeletonCircle(size: 44),
                SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SkeletonBox(height: 14, width: 150, radius: 8),
                      SizedBox(height: 8),
                      SkeletonBox(height: 12, width: 180, radius: 8),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
