import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../widgets/app_text_field.dart';
import '../../../widgets/empty_state.dart';
import '../../../widgets/skeleton.dart';
import '../../../widgets/status_chip.dart';
import '../bloc/case_bloc.dart';
import '../bloc/case_event.dart';
import '../bloc/case_state.dart';
import '../model/case_record.dart';

class HistoryPage extends StatefulWidget {
  const HistoryPage({super.key});

  @override
  State<HistoryPage> createState() => _HistoryPageState();
}

class _HistoryPageState extends State<HistoryPage> {
  final _searchController = TextEditingController();

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Case History')),
      body: BlocBuilder<CaseBloc, CaseState>(
        builder: (context, state) {
          return Column(
            children: [
              if (state.isOffline || state.pendingUploads > 0)
                _OfflineInfoBanner(
                  isOffline: state.isOffline,
                  pendingUploads: state.pendingUploads,
                ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
                child: AppTextField(
                  controller: _searchController,
                  label: 'Search case ID, animal, disease',
                  prefixIcon: Icons.search_rounded,
                  onChanged: (value) => context.read<CaseBloc>().add(CaseSearchChanged(value)),
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: DropdownButtonFormField<String>(
                  initialValue: state.historyAnimalId,
                  decoration: const InputDecoration(
                    labelText: 'Filter by animal',
                    prefixIcon: Icon(Icons.pets_rounded),
                  ),
                  items: [
                    const DropdownMenuItem<String>(
                      value: null,
                      child: Text('All animals'),
                    ),
                    ...state.animals.map((animal) {
                      return DropdownMenuItem<String>(
                        value: animal.id,
                        child: Text(animal.displayName),
                      );
                    }),
                  ],
                  onChanged: (value) => context.read<CaseBloc>().add(
                    CaseHistoryAnimalFilterChanged(value),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              SizedBox(
                height: 42,
                child: ListView.separated(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  scrollDirection: Axis.horizontal,
                  itemCount: CaseStatusFilter.values.length,
                  separatorBuilder: (_, index) => const SizedBox(width: 8),
                  itemBuilder: (context, index) {
                    final filter = CaseStatusFilter.values[index];
                    return ChoiceChip(
                      label: Text(filter.label),
                      selected: state.statusFilter == filter,
                      onSelected: (_) => context.read<CaseBloc>().add(
                        CaseStatusFilterChanged(filter),
                      ),
                    );
                  },
                ),
              ),
              const SizedBox(height: 8),
              SizedBox(
                height: 42,
                child: ListView.separated(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  scrollDirection: Axis.horizontal,
                  itemCount: DiseaseFilter.values.length,
                  separatorBuilder: (_, index) => const SizedBox(width: 8),
                  itemBuilder: (context, index) {
                    final filter = DiseaseFilter.values[index];
                    return ChoiceChip(
                      label: Text(filter.label),
                      selected: state.diseaseFilter == filter,
                      onSelected: (_) => context.read<CaseBloc>().add(
                        CaseDiseaseFilterChanged(filter),
                      ),
                    );
                  },
                ),
              ),
              const SizedBox(height: 10),
              Expanded(
                child: state.isLoading
                    ? const _HistorySkeleton()
                    : state.historyCases.isEmpty
                    ? const EmptyState(
                        title: 'No cases found',
                        subtitle: 'Try another filter or create a new case to populate history.',
                      )
                    : RefreshIndicator(
                        onRefresh: () async {
                          context.read<CaseBloc>().add(const CaseDashboardRefreshRequested());
                        },
                        child: ListView.separated(
                          padding: const EdgeInsets.all(16),
                          itemCount: state.historyCases.length,
                          separatorBuilder: (_, index) => const SizedBox(height: 10),
                          itemBuilder: (context, index) {
                            final item = state.historyCases[index];
                            return _HistoryCard(
                              item: item,
                              onTap: () => context.push('/app/case/${item.id}'),
                            );
                          },
                        ),
                      ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _OfflineInfoBanner extends StatelessWidget {
  const _OfflineInfoBanner({
    required this.isOffline,
    required this.pendingUploads,
  });

  final bool isOffline;
  final int pendingUploads;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        color: isOffline ? const Color(0xFFFFF2CC) : const Color(0xFFDFF3E7),
      ),
      child: Row(
        children: [
          Icon(
            isOffline ? Icons.wifi_off_rounded : Icons.cloud_sync_rounded,
            size: 20,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              isOffline
                  ? 'Offline. $pendingUploads case(s) waiting for sync.'
                  : '$pendingUploads case(s) pending sync.',
            ),
          ),
        ],
      ),
    );
  }
}

class _HistoryCard extends StatelessWidget {
  const _HistoryCard({required this.item, required this.onTap});

  final CaseRecord item;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final confidenceLabel = item.confidence == null
        ? 'No confidence'
        : '${(item.confidence! * 100).toStringAsFixed(1)}% confidence';
    final workflow = item.workflowStatus?.trim().isNotEmpty == true
        ? item.workflowStatus!
        : 'unspecified';

    return Card(
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        onTap: onTap,
        leading: Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: const Color(0xFFE7F2EA),
            borderRadius: BorderRadius.circular(12),
          ),
          child: const Icon(Icons.pets_rounded, color: Color(0xFF1E7A3F)),
        ),
        title: Text(
          '${item.animalLabel} - ${item.id.substring(0, 8)}',
          style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
        ),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '${item.prediction ?? 'Pending prediction'} - ${DateFormat('MMM d, h:mm a').format(item.createdAt)}',
              ),
              const SizedBox(height: 2),
              Text(confidenceLabel, style: Theme.of(context).textTheme.bodySmall),
              const SizedBox(height: 2),
              Text('Workflow: $workflow', style: Theme.of(context).textTheme.bodySmall),
            ],
          ),
        ),
        trailing: StatusChip(status: item.status),
      ),
    );
  }
}

class _HistorySkeleton extends StatelessWidget {
  const _HistorySkeleton();

  @override
  Widget build(BuildContext context) {
    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: 5,
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
                      SkeletonBox(height: 14, width: 180, radius: 8),
                      SizedBox(height: 8),
                      SkeletonBox(height: 12, width: 140, radius: 8),
                    ],
                  ),
                ),
                SizedBox(width: 8),
                SkeletonBox(height: 24, width: 64, radius: 12),
              ],
            ),
          ),
        );
      },
    );
  }
}
