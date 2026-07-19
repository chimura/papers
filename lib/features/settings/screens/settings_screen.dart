import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/auth/auth_provider.dart';
import '../../../core/auth/google_auth_service.dart';
import '../../../core/drive/drive_provider.dart';
import '../../../core/drive/drive_sync_service.dart';
import '../models/app_settings.dart';
import '../providers/settings_provider.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final user = ref.watch(authStateProvider).value;
    final syncState = ref.watch(syncStateProvider);
    final settingsAsync = ref.watch(settingsProvider);
    final settings = settingsAsync.value ?? const AppSettings();

    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        children: [
          // ── Appearance ──
          _SectionHeader('Appearance'),
          ListTile(
            leading: const Icon(Icons.palette),
            title: const Text('Theme'),
            subtitle: Text(settings.themeMode.label),
            trailing: SegmentedButton<AppThemeMode>(
              segments: AppThemeMode.values
                  .map((m) => ButtonSegment(
                        value: m,
                        label: Text(m.label),
                      ))
                  .toList(),
              selected: {settings.themeMode},
              onSelectionChanged: (selected) {
                ref
                    .read(settingsProvider.notifier)
                    .setThemeMode(selected.first);
              },
            ),
          ),

          const Divider(),

          // ── Account ──
          _SectionHeader('Account'),
          if (user != null && !user.isAnonymous) ...[
            ListTile(
              leading: CircleAvatar(
                backgroundImage:
                    user.photoURL != null ? NetworkImage(user.photoURL!) : null,
                child: user.photoURL == null
                    ? Text(user.displayName?.substring(0, 1).toUpperCase() ?? '?')
                    : null,
              ),
              title: Text(user.displayName ?? 'User'),
              subtitle: Text(user.email ?? ''),
            ),
          ] else ...[
            if (user != null)
              const ListTile(
                leading: Icon(Icons.person_outline),
                title: Text('Local session'),
                subtitle: Text('Your library is stored only on this device'),
              ),
            ListTile(
              leading: const Icon(Icons.login),
              title: const Text('Sign in with Google'),
              subtitle: const Text('Required for Google Drive backup'),
              onTap: () => _signInWithGoogle(context),
            ),
          ],

          const Divider(),

          // ── Sync ──
          _SectionHeader('Google Drive Sync'),
          _SyncTile(
            syncState: syncState,
            ref: ref,
            canSync: user != null && !user.isAnonymous,
          ),
          SwitchListTile(
            secondary: const Icon(Icons.sync),
            title: const Text('Auto-sync'),
            subtitle: Text(settings.autoSyncEnabled
                ? 'Every ${settings.syncIntervalMinutes} minutes'
                : 'Disabled'),
            value: settings.autoSyncEnabled,
            onChanged: (value) =>
                ref.read(settingsProvider.notifier).setAutoSync(value),
          ),
          if (settings.autoSyncEnabled)
            ListTile(
              leading: const SizedBox(width: 24),
              title: const Text('Sync interval'),
              trailing: DropdownButton<int>(
                value: settings.syncIntervalMinutes,
                items: [15, 30, 60, 120]
                    .map((m) => DropdownMenuItem(
                          value: m,
                          child: Text('$m min'),
                        ))
                    .toList(),
                onChanged: (value) {
                  if (value != null) {
                    ref
                        .read(settingsProvider.notifier)
                        .setSyncInterval(value);
                  }
                },
              ),
            ),

          const Divider(),

          // ── Library ──
          _SectionHeader('Library'),
          ListTile(
            leading: const Icon(Icons.format_quote),
            title: const Text('Default citation style'),
            trailing: DropdownButton<DefaultCitationStyle>(
              value: settings.defaultCitationStyle,
              items: DefaultCitationStyle.values
                  .map((s) => DropdownMenuItem(
                        value: s,
                        child: Text(s.name.toUpperCase()),
                      ))
                  .toList(),
              onChanged: (value) {
                if (value != null) {
                  ref
                      .read(settingsProvider.notifier)
                      .setDefaultCitationStyle(value);
                }
              },
            ),
          ),
          SwitchListTile(
            secondary: const Icon(Icons.short_text),
            title: const Text('Show abstract in list'),
            subtitle: const Text('Display abstract preview in paper list'),
            value: settings.showAbstractInList,
            onChanged: (value) =>
                ref.read(settingsProvider.notifier).setShowAbstractInList(value),
          ),
          SwitchListTile(
            secondary: const Icon(Icons.warning_amber),
            title: const Text('Confirm before delete'),
            value: settings.confirmBeforeDelete,
            onChanged: (value) => ref
                .read(settingsProvider.notifier)
                .setConfirmBeforeDelete(value),
          ),

          const Divider(),

          // ── About & Actions ──
          _SectionHeader('About'),
          const ListTile(
            leading: Icon(Icons.info_outline),
            title: Text('Sci'),
            subtitle: Text('Version 1.0.0'),
          ),
          ListTile(
            leading: const Icon(Icons.restore),
            title: const Text('Reset settings to defaults'),
            onTap: () => _confirmReset(context, ref),
          ),
          if (user != null)
            ListTile(
              leading: Icon(Icons.logout, color: theme.colorScheme.error),
              title: Text(
                'Sign out',
                style: TextStyle(color: theme.colorScheme.error),
              ),
              onTap: () => _confirmSignOut(context),
            ),

          const SizedBox(height: 32),
        ],
      ),
    );
  }

  Future<void> _signInWithGoogle(BuildContext context) async {
    try {
      await GoogleAuthService().signInWithGoogle();
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Sign-in failed: $e')),
        );
      }
    }
  }

  void _confirmSignOut(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Sign out?'),
        content: const Text(
            'Your local data will be kept. You can sign back in anytime.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              GoogleAuthService().signOut();
              Navigator.pop(context);
            },
            child: const Text('Sign out'),
          ),
        ],
      ),
    );
  }

  void _confirmReset(BuildContext context, WidgetRef ref) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Reset settings?'),
        content: const Text('All settings will be restored to defaults.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              ref.read(settingsProvider.notifier).resetToDefaults();
              Navigator.pop(context);
            },
            child: const Text('Reset'),
          ),
        ],
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String title;
  const _SectionHeader(this.title);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
      child: Text(
        title,
        style: Theme.of(context).textTheme.titleSmall?.copyWith(
              color: Theme.of(context).colorScheme.primary,
            ),
      ),
    );
  }
}

class _SyncTile extends StatelessWidget {
  final SyncState syncState;
  final WidgetRef ref;
  final bool canSync;

  const _SyncTile({
    required this.syncState,
    required this.ref,
    required this.canSync,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isSyncing = syncState.status == SyncStatus.syncing;

    return Column(
      children: [
        ListTile(
          leading: isSyncing
              ? const SizedBox(
                  width: 24,
                  height: 24,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.cloud_sync_outlined),
          title: const Text('Google Drive Sync'),
          subtitle: Text(canSync
              ? _syncSubtitle
              : 'Sign in with Google above to enable sync'),
          trailing: FilledButton.tonal(
            onPressed: isSyncing || !canSync
                ? null
                : () => ref.read(syncStateProvider.notifier).sync(),
            child: Text(isSyncing ? 'Syncing...' : 'Sync now'),
          ),
        ),
        if (syncState.status == SyncStatus.success) ...[
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                const SizedBox(width: 40),
                Icon(Icons.check_circle,
                    size: 16, color: theme.colorScheme.primary),
                const SizedBox(width: 8),
                Text(
                  '${syncState.uploadedCount} uploaded, ${syncState.downloadedCount} downloaded',
                  style: theme.textTheme.bodySmall,
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
        ],
        if (syncState.status == SyncStatus.error) ...[
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                const SizedBox(width: 40),
                Icon(Icons.error_outline,
                    size: 16, color: theme.colorScheme.error),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    syncState.message ?? 'Sync failed',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.error,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
        ],
      ],
    );
  }

  String get _syncSubtitle {
    if (syncState.status == SyncStatus.syncing) {
      return syncState.message ?? 'Syncing...';
    }
    if (syncState.lastSyncTime != null) {
      return 'Last synced: ${_formatTime(syncState.lastSyncTime!)}';
    }
    return 'Backup & sync your library to Google Drive';
  }

  String _formatTime(DateTime time) {
    final now = DateTime.now();
    final diff = now.difference(time);
    if (diff.inMinutes < 1) return 'just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    return '${time.day}/${time.month}/${time.year}';
  }
}
