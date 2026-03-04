import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../widgets/app_text_field.dart';
import '../../../widgets/primary_button.dart';
import '../../auth/bloc/auth_bloc.dart';
import '../../auth/bloc/auth_event.dart';
import '../../auth/bloc/auth_state.dart';
import '../../cases/bloc/case_bloc.dart';
import '../../cases/bloc/case_event.dart';
import '../../cases/bloc/case_state.dart';
import '../bloc/settings_bloc.dart';
import '../bloc/settings_event.dart';
import '../bloc/settings_state.dart';

const _devServerSettingsEnabled = bool.fromEnvironment(
  'ENABLE_DEV_SERVER_SETTINGS',
  defaultValue: false,
);

class SettingsPage extends StatefulWidget {
  const SettingsPage({
    super.key,
    this.focusConnection = false,
    this.publicMode = false,
  });

  final bool focusConnection;
  final bool publicMode;

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  final _apiController = TextEditingController();
  final _vetEmailController = TextEditingController();
  late bool _connectionExpanded;

  @override
  void initState() {
    super.initState();
    _connectionExpanded = widget.focusConnection || widget.publicMode;
  }

  @override
  void dispose() {
    _apiController.dispose();
    _vetEmailController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return BlocListener<SettingsBloc, SettingsState>(
      listenWhen: (previous, current) =>
          previous.apiBaseUrl != current.apiBaseUrl ||
          previous.vetEmail != current.vetEmail ||
          previous.userRole != current.userRole ||
          previous.infoMessage != current.infoMessage ||
          previous.errorMessage != current.errorMessage,
      listener: (context, state) {
        if (_apiController.text != state.apiBaseUrl) {
          _apiController.text = state.apiBaseUrl;
        }
        if (_vetEmailController.text != state.vetEmail) {
          _vetEmailController.text = state.vetEmail;
        }

        final messenger = ScaffoldMessenger.of(context);
        if (state.infoMessage != null) {
          messenger.showSnackBar(SnackBar(content: Text(state.infoMessage!)));
          context.read<SettingsBloc>().add(const SettingsFeedbackCleared());
        } else if (state.errorMessage != null) {
          messenger.showSnackBar(SnackBar(content: Text(state.errorMessage!)));
          context.read<SettingsBloc>().add(const SettingsFeedbackCleared());
        }
      },
      child: Scaffold(
        appBar: AppBar(title: Text(widget.publicMode ? 'Connection Setup' : 'Settings')),
        body: BlocBuilder<SettingsBloc, SettingsState>(
          builder: (context, settingsState) {
            if (settingsState.isLoading) {
              return const Center(child: CircularProgressIndicator());
            }

            return BlocBuilder<AuthBloc, AuthState>(
              builder: (context, authState) {
                final user = authState is AuthAuthenticated ? authState.user : null;

                return BlocBuilder<CaseBloc, CaseState>(
                  builder: (context, caseState) {
                    return ListView(
                      padding: EdgeInsets.fromLTRB(16, widget.publicMode ? 12 : 16, 16, 16),
                      children: [
                        if (!widget.publicMode) ...[
                          Card(
                            child: ListTile(
                              leading: CircleAvatar(
                                backgroundColor:
                                    Theme.of(context).colorScheme.primaryContainer,
                                child: Icon(
                                  Icons.person_rounded,
                                  color: Theme.of(context).colorScheme.primary,
                                ),
                              ),
                              title: Text(user?.name ?? 'Field User'),
                              subtitle: Text(user?.email ?? 'Not signed in'),
                            ),
                          ),
                          const SizedBox(height: 12),
                          _ProfileAndRoleCard(
                            settingsState: settingsState,
                            vetEmailController: _vetEmailController,
                          ),
                          const SizedBox(height: 12),
                        ],
                        if (widget.publicMode && !_devServerSettingsEnabled)
                          Card(
                            child: ListTile(
                              leading: const Icon(Icons.lock_outline_rounded),
                              title: const Text('Connection settings unavailable'),
                              subtitle: const Text(
                                'Server configuration is restricted to developer/admin builds.',
                              ),
                            ),
                          ),
                        if (widget.publicMode || _devServerSettingsEnabled)
                          _ConnectionCard(
                            publicMode: widget.publicMode,
                            expanded: _connectionExpanded,
                            onExpandedChanged: (value) =>
                                setState(() => _connectionExpanded = value),
                            settingsState: settingsState,
                            apiController: _apiController,
                          ),
                        if (!widget.publicMode) ...[
                          const SizedBox(height: 12),
                          _OfflineAndSyncCard(caseState: caseState),
                          const SizedBox(height: 16),
                          FilledButton.tonalIcon(
                            onPressed: () {
                              context.read<AuthBloc>().add(const AuthLogoutRequested());
                            },
                            icon: const Icon(Icons.logout_rounded),
                            label: const Text('Logout'),
                          ),
                        ],
                      ],
                    );
                  },
                );
              },
            );
          },
        ),
      ),
    );
  }
}

class _ProfileAndRoleCard extends StatelessWidget {
  const _ProfileAndRoleCard({
    required this.settingsState,
    required this.vetEmailController,
  });

  final SettingsState settingsState;
  final TextEditingController vetEmailController;

  @override
  Widget build(BuildContext context) {
    final authState = context.watch<AuthBloc>().state;
    final serverRole = authState is AuthAuthenticated ? authState.user.role : '';
    final isCahw = serverRole.isEmpty || serverRole.toUpperCase() == 'CAHW';

    String roleLabel;
    switch (serverRole.toUpperCase()) {
      case 'VET':
        roleLabel = 'Veterinarian';
      case 'ADMIN':
        roleLabel = 'Administrator';
      default:
        roleLabel = 'Community Animal Health Worker (CAHW)';
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Profile & Work',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
            ),
            const SizedBox(height: 6),
            Text(
              'Settings used for case routing and notifications.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 10),
            // Read-only server role display
            InputDecorator(
              decoration: const InputDecoration(
                labelText: 'Your role',
                prefixIcon: Icon(Icons.badge_outlined),
              ),
              child: Text(roleLabel, style: Theme.of(context).textTheme.bodyMedium),
            ),
            // Vet email field is only relevant for CAHW users placing referrals
            if (isCahw) ...[
              const SizedBox(height: 10),
              AppTextField(
                controller: vetEmailController,
                label: 'Vet email (for referrals/receipts)',
                hint: 'vet@clinic.org',
                prefixIcon: Icons.alternate_email_rounded,
                keyboardType: TextInputType.emailAddress,
                onChanged: (value) =>
                    context.read<SettingsBloc>().add(SettingsVetEmailChanged(value)),
              ),
            ],
            const SizedBox(height: 10),
            DropdownButtonFormField<String>(
              initialValue: settingsState.themeMode,
              decoration: const InputDecoration(
                labelText: 'Appearance',
                prefixIcon: Icon(Icons.dark_mode_outlined),
              ),
              items: const [
                DropdownMenuItem(value: 'system', child: Text('Use device setting')),
                DropdownMenuItem(value: 'light', child: Text('Light mode')),
                DropdownMenuItem(value: 'dark', child: Text('Dark mode')),
              ],
              onChanged: (value) {
                if (value == null) {
                  return;
                }
                context.read<SettingsBloc>().add(SettingsThemeModeChanged(value));
              },
            ),
            const SizedBox(height: 12),
            PrimaryButton(
              label: settingsState.isSaving ? 'Saving...' : 'Save changes',
              icon: Icons.save_outlined,
              isLoading: settingsState.isSaving,
              onPressed: () => context.read<SettingsBloc>().add(const SettingsSavedRequested()),
            ),
          ],
        ),
      ),
    );
  }
}

class _ConnectionCard extends StatelessWidget {
  const _ConnectionCard({
    required this.publicMode,
    required this.expanded,
    required this.onExpandedChanged,
    required this.settingsState,
    required this.apiController,
  });

  final bool publicMode;
  final bool expanded;
  final ValueChanged<bool> onExpandedChanged;
  final SettingsState settingsState;
  final TextEditingController apiController;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          initiallyExpanded: expanded,
          onExpansionChanged: onExpandedChanged,
          leading: const Icon(Icons.settings_ethernet_rounded),
          title: Text(publicMode ? 'Backend Connection' : 'Advanced Connection'),
          subtitle: Text(
            publicMode
                ? 'Set the SudVet API URL used for sign-in and case sync.'
                : 'Change API base URL only when switching backend servers.',
          ),
          childrenPadding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
          children: [
            AppTextField(
              controller: apiController,
              label: 'API base URL',
              hint: 'http://10.0.2.2:8000',
              prefixIcon: Icons.link_rounded,
              onChanged: (value) =>
                  context.read<SettingsBloc>().add(SettingsApiBaseChanged(value)),
            ),
            const SizedBox(height: 10),
            Text(
              'Web localhost: http://127.0.0.1:8000 | Android emulator: http://10.0.2.2:8000',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 12),
            if (publicMode)
              PrimaryButton(
                label: settingsState.isSaving ? 'Saving...' : 'Save connection',
                icon: Icons.save_outlined,
                isLoading: settingsState.isSaving,
                onPressed: () =>
                    context.read<SettingsBloc>().add(const SettingsSavedRequested()),
              )
            else
              OutlinedButton.icon(
                onPressed: settingsState.isSaving
                    ? null
                    : () => context.read<SettingsBloc>().add(
                          const SettingsSavedRequested(),
                        ),
                icon: const Icon(Icons.save_outlined),
                label: const Text('Save connection settings'),
              ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: settingsState.isTesting
                  ? null
                  : () => context.read<SettingsBloc>().add(
                        const SettingsConnectionTestRequested(),
                      ),
              icon: settingsState.isTesting
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.network_check_rounded),
              label: const Text('Test API connection'),
            ),
          ],
        ),
      ),
    );
  }
}

class _OfflineAndSyncCard extends StatelessWidget {
  const _OfflineAndSyncCard({required this.caseState});

  final CaseState caseState;

  @override
  Widget build(BuildContext context) {
    final settingsState = context.watch<SettingsBloc>().state;
    return Card(
      child: Column(
        children: [
          SwitchListTile.adaptive(
            title: const Text('Offline-only mode'),
            subtitle: const Text(
              'Use local workflow and keep cases pending for later sync.',
            ),
            value: settingsState.offlineOnly,
            onChanged: (value) =>
                context.read<SettingsBloc>().add(SettingsOfflineToggled(value)),
          ),
          const Divider(height: 1),
          ListTile(
            leading: Icon(
              caseState.isOffline ? Icons.wifi_off_rounded : Icons.wifi_rounded,
            ),
            title: Text(
              caseState.isOffline ? 'Device is offline' : 'Device is online',
            ),
            subtitle: Text('${caseState.pendingUploads} pending upload(s)'),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: SizedBox(
              width: double.infinity,
              child: FilledButton.tonalIcon(
                onPressed: caseState.isOffline
                    ? null
                    : () => context.read<CaseBloc>().add(
                          const CasePendingSyncRequested(),
                        ),
                icon: const Icon(Icons.sync_rounded),
                label: const Text('Sync Pending'),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
