import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../widgets/empty_state.dart';
import '../../../widgets/skeleton.dart';
import '../../../widgets/status_chip.dart';
import '../../auth/bloc/auth_bloc.dart';
import '../../auth/bloc/auth_state.dart';
import '../../cases/bloc/case_bloc.dart';
import '../../cases/bloc/case_event.dart';
import '../../cases/bloc/case_state.dart';
import '../../cases/model/case_record.dart';
import '../../cases/model/dashboard_stats.dart';
import '../../settings/bloc/settings_bloc.dart';

const _homePrimary = Color(0xFF2E7D4F);
const _homeDeep = Color(0xFF1F5C3A);
const _homeWarm = Color(0xFFF7F5EF);
const _homePanel = Color(0xFFFFFEFB);
const _homeBorder = Color(0xFFD8DCCF);
const _homeMuted = Color(0xFF5E675F);
const _homeOchre = Color(0xFFC79A3B);

class HomePage extends StatelessWidget {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocListener<CaseBloc, CaseState>(
      listenWhen: (previous, current) =>
          previous.infoMessage != current.infoMessage ||
          previous.errorMessage != current.errorMessage,
      listener: (context, state) {
        final messenger = ScaffoldMessenger.of(context);

        if (state.infoMessage != null) {
          messenger.showSnackBar(SnackBar(content: Text(state.infoMessage!)));
          context.read<CaseBloc>().add(const CaseFeedbackCleared());
          return;
        }

        if (state.errorMessage != null) {
          messenger.showSnackBar(SnackBar(content: Text(state.errorMessage!)));
          context.read<CaseBloc>().add(const CaseFeedbackCleared());
        }
      },
      child: BlocBuilder<AuthBloc, AuthState>(
        builder: (context, authState) {
          final firstName = authState is AuthAuthenticated
              ? authState.user.name.split(' ').first
              : 'Farmer';

          return Scaffold(
            appBar: AppBar(
              title: const Text('SudVet Field'),
              actions: [
                IconButton(
                  onPressed: () => context.go('/app/learn'),
                  icon: const Icon(Icons.menu_book_rounded),
                  tooltip: 'Learn',
                ),
              ],
            ),
            body: BlocBuilder<CaseBloc, CaseState>(
              builder: (context, caseState) {
                final settingsState = context.watch<SettingsBloc>().state;
                final isVetRole = settingsState.userRole == 'vet';
                final stats = caseState.stats;
                final lastSyncLabel = stats.lastSyncAt == null
                    ? 'Never'
                    : DateFormat('MMM d, h:mm a').format(stats.lastSyncAt!);

                return RefreshIndicator(
                  onRefresh: () async {
                    context.read<CaseBloc>().add(
                      const CaseDashboardRefreshRequested(),
                    );
                  },
                  child: ListView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.all(16),
                    children: [
                      _AnimatedGreetingHeader(
                        firstName: firstName,
                        isVetRole: isVetRole,
                      ),
                      if (caseState.isOffline ||
                          caseState.pendingUploads > 0) ...[
                        const SizedBox(height: 12),
                        _OfflineBanner(
                          isOffline: caseState.isOffline,
                          pendingUploads: caseState.pendingUploads,
                          onSyncTap: caseState.isOffline
                              ? null
                              : () => context.read<CaseBloc>().add(
                                  const CasePendingSyncRequested(),
                                ),
                        ),
                      ],
                      const SizedBox(height: 16),
                      AnimatedSwitcher(
                        duration: const Duration(milliseconds: 280),
                        child: caseState.isLoading
                            ? const _HeroStatsSkeleton(
                                key: ValueKey('hero-loading'),
                              )
                            : _HeroStatsCard(
                                key: const ValueKey('hero-ready'),
                                totalCases: stats.totalCases,
                                pendingCases: stats.pendingCases,
                                syncedCases: stats.syncedCases,
                                failedCases: stats.failedCases,
                                lastSyncLabel: lastSyncLabel,
                                isVetRole: isVetRole,
                                onPrimaryAction: () => isVetRole
                                    ? context.push('/app/vet-inbox')
                                    : context.go('/app/new-case'),
                              ),
                      ),
                      const SizedBox(height: 14),
                      _PriorityTasksCard(
                        isVetRole: isVetRole,
                        pendingUploads: caseState.pendingUploads,
                        isOffline: caseState.isOffline,
                        pendingCases: stats.pendingCases,
                        failedCases: stats.failedCases,
                        hasRecentCases: caseState.recentCases.isNotEmpty,
                        onPrimary: () {
                          if (isVetRole) {
                            context.push('/app/vet-inbox');
                            return;
                          }
                          if (!caseState.isOffline &&
                              caseState.pendingUploads > 0) {
                            context.read<CaseBloc>().add(
                              const CasePendingSyncRequested(),
                            );
                            return;
                          }
                          context.go('/app/new-case');
                        },
                        onSecondary: () => context.go('/app/history'),
                      ),
                      const SizedBox(height: 16),
                      Text(
                        'Field Tools',
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                      const SizedBox(height: 10),
                      Wrap(
                        spacing: 10,
                        runSpacing: 10,
                        children: [
                          if (isVetRole)
                            _QuickActionCard(
                              label: 'Vet Inbox',
                              icon: Icons.medical_services_rounded,
                              onTap: () => context.push('/app/vet-inbox'),
                            ),
                          _QuickActionCard(
                            label: 'New Case',
                            icon: Icons.add_a_photo_rounded,
                            onTap: () => context.go('/app/new-case'),
                          ),
                          _QuickActionCard(
                            label: 'History',
                            icon: Icons.history_rounded,
                            onTap: () => context.go('/app/history'),
                          ),
                          _QuickActionCard(
                            label: 'Animals',
                            icon: Icons.pets_rounded,
                            onTap: () => context.push('/app/animals'),
                          ),
                          _QuickActionCard(
                            label: caseState.isSyncing
                                ? 'Syncing...'
                                : 'Sync Pending',
                            icon: Icons.sync_rounded,
                            onTap: caseState.isSyncing
                                ? null
                                : () => context.read<CaseBloc>().add(
                                    const CasePendingSyncRequested(),
                                  ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 18),
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              'Recent Cases',
                              style: Theme.of(context).textTheme.titleLarge,
                            ),
                          ),
                          TextButton(
                            onPressed: () => context.go('/app/history'),
                            child: const Text('View all'),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      SizedBox(
                        height: 216,
                        child: AnimatedSwitcher(
                          duration: const Duration(milliseconds: 280),
                          child: caseState.isLoading
                              ? const _RecentCasesSkeleton(
                                  key: ValueKey('recent-loading'),
                                )
                              : caseState.recentCases.isEmpty
                              ? const EmptyState(
                                  key: ValueKey('recent-empty'),
                                  title: 'No recent cases yet',
                                  subtitle:
                                      'Start a new case to see prediction results here.',
                                  icon: Icons.pets_outlined,
                                )
                              : ListView.separated(
                                  key: const ValueKey('recent-list'),
                                  scrollDirection: Axis.horizontal,
                                  itemCount: caseState.recentCases.length,
                                  separatorBuilder: (_, index) =>
                                      const SizedBox(width: 12),
                                  itemBuilder: (context, index) {
                                    final item = caseState.recentCases[index];
                                    return _RecentCaseCard(
                                      item: item,
                                      onTap: () => context.push(
                                        '/app/result/${item.id}',
                                      ),
                                    );
                                  },
                                ),
                        ),
                      ),
                      const SizedBox(height: 18),
                      _AnalyticsPanel(
                        isVetRole: isVetRole,
                        isLoading: caseState.isLoading,
                        stats: stats,
                      ),
                    ],
                  ),
                );
              },
            ),
          );
        },
      ),
    );
  }
}

class _PriorityTasksCard extends StatelessWidget {
  const _PriorityTasksCard({
    required this.isVetRole,
    required this.pendingUploads,
    required this.isOffline,
    required this.pendingCases,
    required this.failedCases,
    required this.hasRecentCases,
    required this.onPrimary,
    required this.onSecondary,
  });

  final bool isVetRole;
  final int pendingUploads;
  final bool isOffline;
  final int pendingCases;
  final int failedCases;
  final bool hasRecentCases;
  final VoidCallback onPrimary;
  final VoidCallback onSecondary;

  @override
  Widget build(BuildContext context) {
    final primaryLabel = isVetRole
        ? 'Open Vet Inbox'
        : (!isOffline && pendingUploads > 0
              ? 'Sync Pending Cases'
              : 'Start New Case');

    final primaryIcon = isVetRole
        ? Icons.medical_services_rounded
        : (!isOffline && pendingUploads > 0
              ? Icons.sync_rounded
              : Icons.add_a_photo_rounded);

    final title = isVetRole ? 'Vet Priorities' : 'CHW Priorities';
    final subtitle = isVetRole
        ? 'Focus on assigned cases and reviews first.'
        : 'Focus on new case capture and follow-up first.';

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 34,
                  height: 34,
                  decoration: BoxDecoration(
                    color: const Color(0xFFFBF1DD),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: const Color(0xFFE4D0A5)),
                  ),
                  child: const Icon(
                    Icons.assignment_turned_in_rounded,
                    size: 18,
                    color: _homeOchre,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    title,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              subtitle,
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: _homeMuted),
            ),
            const SizedBox(height: 12),
            if (isVetRole) ...[
              _PriorityLine(
                label: 'Pending cases to review',
                value: '$pendingCases',
                tone: pendingCases > 0
                    ? _PriorityTone.warn
                    : _PriorityTone.neutral,
              ),
              const SizedBox(height: 8),
              _PriorityLine(
                label: 'Cases needing retry/sync follow-up',
                value: '$failedCases',
                tone: failedCases > 0
                    ? _PriorityTone.error
                    : _PriorityTone.neutral,
              ),
              const SizedBox(height: 8),
              _PriorityLine(
                label: 'Update case thread and close reviewed cases',
                value: 'Today',
                tone: _PriorityTone.neutral,
              ),
            ] else ...[
              _PriorityLine(
                label: 'Pending uploads',
                value: '$pendingUploads',
                tone: pendingUploads > 0
                    ? _PriorityTone.warn
                    : _PriorityTone.neutral,
              ),
              const SizedBox(height: 8),
              _PriorityLine(
                label: 'Network status',
                value: isOffline ? 'Offline' : 'Online',
                tone: isOffline ? _PriorityTone.error : _PriorityTone.success,
              ),
              const SizedBox(height: 8),
              _PriorityLine(
                label: 'Recent case follow-up',
                value: hasRecentCases ? 'Available' : 'None yet',
                tone: hasRecentCases
                    ? _PriorityTone.neutral
                    : _PriorityTone.neutral,
              ),
            ],
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: FilledButton.icon(
                    onPressed: onPrimary,
                    icon: Icon(primaryIcon),
                    label: Text(primaryLabel),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            OutlinedButton(
              onPressed: onSecondary,
              child: Text(isVetRole ? 'Open Case History' : 'Open History'),
            ),
          ],
        ),
      ),
    );
  }
}

enum _PriorityTone { neutral, success, warn, error }

class _PriorityLine extends StatelessWidget {
  const _PriorityLine({
    required this.label,
    required this.value,
    required this.tone,
  });

  final String label;
  final String value;
  final _PriorityTone tone;

  @override
  Widget build(BuildContext context) {
    Color bg;
    Color fg;
    switch (tone) {
      case _PriorityTone.success:
        bg = const Color(0xFFE4F0E6);
        fg = const Color(0xFF225C3A);
      case _PriorityTone.warn:
        bg = const Color(0xFFFBF1DD);
        fg = const Color(0xFF7A5A12);
      case _PriorityTone.error:
        bg = const Color(0xFFF7E1DA);
        fg = const Color(0xFF8A2D1F);
      case _PriorityTone.neutral:
        bg = const Color(0xFFF3F6EC);
        fg = _homeMuted;
    }

    return Row(
      children: [
        Expanded(
          child: Text(
            label,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: _homeDeep,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        const SizedBox(width: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: fg.withValues(alpha: 0.16)),
          ),
          child: Text(
            value,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: fg,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ],
    );
  }
}

class _AnimatedGreetingHeader extends StatelessWidget {
  const _AnimatedGreetingHeader({
    required this.firstName,
    required this.isVetRole,
  });

  final String firstName;
  final bool isVetRole;

  @override
  Widget build(BuildContext context) {
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 420),
      transitionBuilder: (child, animation) {
        final slide = Tween<Offset>(
          begin: const Offset(0, 0.12),
          end: Offset.zero,
        ).animate(animation);
        return FadeTransition(
          opacity: animation,
          child: SlideTransition(position: slide, child: child),
        );
      },
      child: Column(
        key: ValueKey(firstName),
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: _homePanel,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: _homeBorder),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Welcome, $firstName',
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w800,
                    color: _homeDeep,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  isVetRole
                      ? 'Review assigned cases and close follow-up actions.'
                      : 'Capture cases, sync evidence, and track vet responses.',
                  style: Theme.of(
                    context,
                  ).textTheme.bodyMedium?.copyWith(color: _homeMuted),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _OfflineBanner extends StatelessWidget {
  const _OfflineBanner({
    required this.isOffline,
    required this.pendingUploads,
    required this.onSyncTap,
  });

  final bool isOffline;
  final int pendingUploads;
  final VoidCallback? onSyncTap;

  @override
  Widget build(BuildContext context) {
    final background = isOffline
        ? const Color(0xFFFFF1D6)
        : const Color(0xFFDFF3E7);
    final foreground = isOffline
        ? const Color(0xFF6D4C00)
        : const Color(0xFF1D6A3E);

    return Container(
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(14),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      child: Row(
        children: [
          Icon(
            isOffline ? Icons.wifi_off_rounded : Icons.cloud_done_rounded,
            color: foreground,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              isOffline
                  ? 'Offline mode. $pendingUploads pending upload(s).'
                  : '$pendingUploads pending upload(s) waiting to sync.',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: foreground,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          if (!isOffline && pendingUploads > 0)
            TextButton(onPressed: onSyncTap, child: const Text('Sync')),
        ],
      ),
    );
  }
}

class _HeroStatsCard extends StatelessWidget {
  const _HeroStatsCard({
    super.key,
    required this.isVetRole,
    required this.totalCases,
    required this.pendingCases,
    required this.syncedCases,
    required this.failedCases,
    required this.lastSyncLabel,
    required this.onPrimaryAction,
  });

  final bool isVetRole;
  final int totalCases;
  final int pendingCases;
  final int syncedCases;
  final int failedCases;
  final String lastSyncLabel;
  final VoidCallback onPrimaryAction;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        color: _homePanel,
        border: Border.all(color: _homeBorder),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    color: const Color(0xFFE8F1E9),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: const Color(0xFFD0E2D4)),
                  ),
                  child: const Icon(
                    Icons.assessment_rounded,
                    color: _homePrimary,
                  ),
                ),
                const SizedBox(width: 10),
                const Expanded(
                  child: Text(
                    'Field Dashboard',
                    style: TextStyle(
                      color: _homeDeep,
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              'Last sync: $lastSyncLabel',
              style: const TextStyle(color: _homeMuted),
            ),
            const SizedBox(height: 12),
            LayoutBuilder(
              builder: (context, constraints) {
                final isNarrow = constraints.maxWidth < 420;
                final tileWidth = isNarrow
                    ? (constraints.maxWidth - 8) / 2
                    : (constraints.maxWidth - 24) / 4;
                return Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    SizedBox(
                      width: tileWidth,
                      child: _MetricTile(label: 'Total', value: '$totalCases'),
                    ),
                    SizedBox(
                      width: tileWidth,
                      child: _MetricTile(
                        label: 'Pending',
                        value: '$pendingCases',
                      ),
                    ),
                    SizedBox(
                      width: tileWidth,
                      child: _MetricTile(
                        label: 'Synced',
                        value: '$syncedCases',
                      ),
                    ),
                    SizedBox(
                      width: tileWidth,
                      child: _MetricTile(
                        label: 'Failed',
                        value: '$failedCases',
                      ),
                    ),
                  ],
                );
              },
            ),
            const SizedBox(height: 14),
            FilledButton.icon(
              style: FilledButton.styleFrom(
                backgroundColor: _homePrimary,
                foregroundColor: Colors.white,
              ),
              onPressed: onPrimaryAction,
              icon: Icon(
                isVetRole
                    ? Icons.medical_services_rounded
                    : Icons.add_a_photo_rounded,
              ),
              label: Text(isVetRole ? 'Open Vet Inbox' : 'Start New Case'),
            ),
          ],
        ),
      ),
    );
  }
}

class _AnalyticsPanel extends StatelessWidget {
  const _AnalyticsPanel({
    required this.isVetRole,
    required this.isLoading,
    required this.stats,
  });

  final bool isVetRole;
  final bool isLoading;
  final DashboardStats stats;

  @override
  Widget build(BuildContext context) {
    final content = AnimatedSwitcher(
      duration: const Duration(milliseconds: 280),
      child: isLoading
          ? const _AnalyticsSkeleton(key: ValueKey('analytics-loading'))
          : _AnalyticsSection(
              key: const ValueKey('analytics-ready'),
              stats: stats,
            ),
    );

    if (isVetRole) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Analytics', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 10),
          content,
        ],
      );
    }

    return Card(
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          leading: const Icon(Icons.query_stats_rounded, color: _homeOchre),
          initiallyExpanded: false,
          title: const Text('Analytics'),
          subtitle: const Text('Optional: expand for trends and disease mix.'),
          childrenPadding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
          children: [content],
        ),
      ),
    );
  }
}

class _MetricTile extends StatelessWidget {
  const _MetricTile({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
      decoration: BoxDecoration(
        color: _homeWarm,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _homeBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            value,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
              color: _homeDeep,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(color: _homeMuted),
          ),
        ],
      ),
    );
  }
}

class _HeroStatsSkeleton extends StatelessWidget {
  const _HeroStatsSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    final base = Colors.white.withValues(alpha: 0.26);
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF2C8A4F), Color(0xFF537E98)],
        ),
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SkeletonBox(width: 180, height: 16, color: base, radius: 8),
          const SizedBox(height: 8),
          SkeletonBox(width: 120, height: 12, color: base, radius: 8),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(child: SkeletonBox(height: 50, color: base, radius: 12)),
              const SizedBox(width: 8),
              Expanded(child: SkeletonBox(height: 50, color: base, radius: 12)),
              const SizedBox(width: 8),
              Expanded(child: SkeletonBox(height: 50, color: base, radius: 12)),
              const SizedBox(width: 8),
              Expanded(child: SkeletonBox(height: 50, color: base, radius: 12)),
            ],
          ),
          const SizedBox(height: 12),
          SkeletonBox(width: 170, height: 46, color: base, radius: 12),
        ],
      ),
    );
  }
}

class _QuickActionCard extends StatelessWidget {
  const _QuickActionCard({
    required this.label,
    required this.icon,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final width = (MediaQuery.of(context).size.width - 16 * 2 - 10) / 2;
    return SizedBox(
      width: width,
      child: Card(
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Row(
              children: [
                Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    color: const Color(0xFFEFF3EA),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: _homeBorder),
                  ),
                  child: Icon(icon, color: _homePrimary),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    label,
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _AnalyticsSection extends StatelessWidget {
  const _AnalyticsSection({super.key, required this.stats});

  final DashboardStats stats;

  @override
  Widget build(BuildContext context) {
    final maxDiseaseValue = stats.diseaseCounts.values.isEmpty
        ? 1
        : stats.diseaseCounts.values.reduce(math.max);

    final diseaseEntries = ['normal', 'lsd', 'fmd', 'ecf', 'cbpp', 'unknown']
        .map((key) => MapEntry(key, stats.diseaseCounts[key] ?? 0))
        .toList(growable: false);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Cases by Disease',
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 12),
            ...diseaseEntries.map((entry) {
              return Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  children: [
                    SizedBox(width: 68, child: Text(entry.key.toUpperCase())),
                    Expanded(
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(999),
                        child: LinearProgressIndicator(
                          minHeight: 10,
                          value: entry.value / maxDiseaseValue,
                          color: entry.key == 'unknown' ? _homeOchre : null,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    SizedBox(width: 24, child: Text('${entry.value}')),
                  ],
                ),
              );
            }),
            const Divider(height: 20),
            Text(
              'Trend (Past Weeks)',
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 10),
            SizedBox(
              height: 120,
              child: _TrendChart(points: stats.weeklyTrend),
            ),
          ],
        ),
      ),
    );
  }
}

class _TrendChart extends StatelessWidget {
  const _TrendChart({required this.points});

  final List<DashboardTrendPoint> points;

  @override
  Widget build(BuildContext context) {
    if (points.isEmpty) {
      return const Center(child: Text('No trend data yet.'));
    }

    return CustomPaint(
      painter: _TrendPainter(
        points: points
            .map((item) => item.count.toDouble())
            .toList(growable: false),
        color: Theme.of(context).colorScheme.primary,
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: points
              .map(
                (item) => Text(
                  item.label,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              )
              .toList(growable: false),
        ),
      ),
    );
  }
}

class _TrendPainter extends CustomPainter {
  _TrendPainter({required this.points, required this.color});

  final List<double> points;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    if (points.length < 2) {
      return;
    }

    final maxValue = points.reduce(math.max);
    final minValue = points.reduce(math.min);
    final range = math.max(1, maxValue - minValue);

    final path = Path();
    final fillPath = Path();
    final stepX = size.width / (points.length - 1);

    for (var i = 0; i < points.length; i++) {
      final x = i * stepX;
      final normalized = (points[i] - minValue) / range;
      final y = size.height * 0.15 + (1 - normalized) * (size.height * 0.6);
      if (i == 0) {
        path.moveTo(x, y);
        fillPath.moveTo(x, y);
      } else {
        path.lineTo(x, y);
        fillPath.lineTo(x, y);
      }
    }

    fillPath.lineTo(size.width, size.height * 0.8);
    fillPath.lineTo(0, size.height * 0.8);
    fillPath.close();

    final fillPaint = Paint()
      ..color = color.withValues(alpha: 0.14)
      ..style = PaintingStyle.fill;
    canvas.drawPath(fillPath, fillPaint);

    final linePaint = Paint()
      ..color = color
      ..strokeWidth = 2.2
      ..style = PaintingStyle.stroke;
    canvas.drawPath(path, linePaint);
  }

  @override
  bool shouldRepaint(covariant _TrendPainter oldDelegate) {
    return oldDelegate.points != points || oldDelegate.color != color;
  }
}

class _AnalyticsSkeleton extends StatelessWidget {
  const _AnalyticsSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: const [
        Card(
          child: Padding(
            padding: EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SkeletonBox(width: 140, height: 16, radius: 8),
                SizedBox(height: 12),
                SkeletonBox(height: 10, radius: 999),
                SizedBox(height: 8),
                SkeletonBox(height: 10, radius: 999),
                SizedBox(height: 8),
                SkeletonBox(height: 10, radius: 999),
              ],
            ),
          ),
        ),
        SizedBox(height: 10),
        Card(
          child: Padding(
            padding: EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SkeletonBox(width: 120, height: 16, radius: 8),
                SizedBox(height: 10),
                SkeletonBox(height: 100, radius: 12),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _RecentCaseCard extends StatelessWidget {
  const _RecentCaseCard({required this.item, required this.onTap});

  final CaseRecord item;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final created = DateFormat('MMM d, h:mm a').format(item.createdAt);

    return SizedBox(
      width: 248,
      child: Card(
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  height: 76,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(12),
                    color: const Color(0xFFF3F6EC),
                    border: Border.all(color: _homeBorder),
                  ),
                  child: const Center(
                    child: Icon(
                      Icons.medical_services_rounded,
                      size: 30,
                      color: _homePrimary,
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  item.animalLabel,
                  style: Theme.of(
                    context,
                  ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 4),
                Text(
                  item.prediction ?? 'No prediction yet',
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
                const SizedBox(height: 6),
                Row(
                  children: [
                    StatusChip(status: item.status),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        created,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _RecentCasesSkeleton extends StatelessWidget {
  const _RecentCasesSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    return ListView.separated(
      scrollDirection: Axis.horizontal,
      itemCount: 3,
      separatorBuilder: (_, index) => const SizedBox(width: 12),
      itemBuilder: (context, index) {
        return SizedBox(
          width: 248,
          child: Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: const [
                  SkeletonBox(height: 76, radius: 12),
                  SizedBox(height: 10),
                  SkeletonBox(height: 14, width: 120, radius: 8),
                  SizedBox(height: 8),
                  SkeletonBox(height: 12, width: 150, radius: 8),
                  SizedBox(height: 8),
                  Row(
                    children: [
                      SkeletonBox(height: 24, width: 70, radius: 12),
                      SizedBox(width: 8),
                      Expanded(child: SkeletonBox(height: 12, radius: 8)),
                    ],
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
