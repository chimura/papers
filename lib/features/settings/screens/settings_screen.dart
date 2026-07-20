import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

import '../../../core/auth/auth_provider.dart';
import '../../../core/auth/google_auth_service.dart';
import '../../../core/database/database_provider.dart';
import '../../../core/drive/drive_provider.dart';
import '../../../core/drive/drive_sync_service.dart';
import '../../../core/database/daos/auto_export_dao.dart';
import '../../../core/models/paper_model.dart';
import '../../citations/services/auto_bib_export.dart';
import '../../citations/services/citation_clipboard.dart';
import '../../citations/services/export_service.dart';
import '../../enrichment/services/enrichment_service.dart';
import '../../enrichment/services/retraction_service.dart';
import '../../enrichment/services/unpaywall_service.dart';
import '../../import/providers/watched_folder_provider.dart';
import '../../import/services/crossref_service.dart';
import '../../import/services/file_import_service.dart';
import '../../library/providers/library_provider.dart';
import '../../reader/models/annotation_model.dart';
import '../../reader/providers/annotation_provider.dart';
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
          ListTile(
            leading: const Icon(Icons.download_outlined),
            title: const Text('Find open-access PDFs'),
            subtitle: const Text(
                'Look up free PDFs (Unpaywall) for papers without a file'),
            onTap: () => _findOpenAccessPdfs(context, ref),
          ),
          ListTile(
            leading: const Icon(Icons.healing_outlined),
            title: const Text('Complete missing metadata'),
            subtitle: const Text(
                'Fill in abstracts, DOIs and journals from CrossRef'),
            onTap: () => _runMetadataDoctor(context, ref),
          ),
          ListTile(
            leading: const Icon(Icons.report_outlined),
            title: const Text('Check for retractions'),
            subtitle:
                const Text('Flag retracted or corrected papers via Crossref'),
            onTap: () => _checkRetractions(context, ref),
          ),

          const Divider(),

          // ── Automation ──
          _SectionHeader('Automation'),
          _WatchedFolderTile(),
          _AutoBibExportTile(),
          ListTile(
            leading: const Icon(Icons.notes_outlined),
            title: const Text('Export annotation summaries'),
            subtitle: const Text(
                'One Markdown file per annotated paper (Obsidian-ready)'),
            onTap: () => _exportAnnotationSummaries(context, ref),
          ),

          const Divider(),

          // ── About & Actions ──
          _SectionHeader('About'),
          const ListTile(
            leading: Icon(Icons.info_outline),
            title: Text('Papers'),
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

  Future<void> _findOpenAccessPdfs(BuildContext context, WidgetRef ref) async {
    final messenger = ScaffoldMessenger.of(context);
    final dao = ref.read(paperDaoProvider);
    final candidates = await dao.getPapersWithDoiWithoutPdf();

    if (candidates.isEmpty) {
      messenger.showSnackBar(const SnackBar(
          content: Text('All papers with a DOI already have a PDF')));
      return;
    }

    messenger.showSnackBar(SnackBar(
        content:
            Text('Searching open-access PDFs for ${candidates.length} papers...')));

    final service = UnpaywallService();
    final pdfsDir = await FileImportService().pdfsDirectory();
    var found = 0;

    for (final paper in candidates) {
      final safeName = (paper.bibtexKey ?? 'paper_${paper.id}')
          .replaceAll(RegExp(r'[^\w\-]'), '_');
      final savePath = p.join(pdfsDir.path, '$safeName.pdf');
      final ok = await service.fetchOaPdf(doi: paper.doi!, savePath: savePath);
      if (ok) {
        await dao.updatePaper(paper.copyWith(localPdfPath: savePath));
        found++;
      }
    }

    await ref.read(libraryProvider.notifier).refresh();
    messenger.showSnackBar(SnackBar(
        content: Text(
            'Found PDFs for $found of ${candidates.length} papers')));
  }

  /// Fills in blank fields on incomplete papers from CrossRef, never
  /// overwriting anything the user already has.
  Future<void> _runMetadataDoctor(BuildContext context, WidgetRef ref) async {
    final messenger = ScaffoldMessenger.of(context);
    final dao = ref.read(paperDaoProvider);
    final service = EnrichmentService();

    final papers = await dao.getAllPapers();
    final incomplete = papers.where(service.isIncomplete).toList();
    if (incomplete.isEmpty) {
      messenger.showSnackBar(
          const SnackBar(content: Text('Every paper already looks complete')));
      return;
    }

    messenger.showSnackBar(SnackBar(
        content: Text('Enriching ${incomplete.length} papers...')));

    var improved = 0;
    for (final paper in incomplete) {
      PaperModel? found;
      if (paper.doi != null) {
        found = await CrossRefService().fetchByDoi(paper.doi!);
      } else {
        found = await service.findByTitle(
          paper.title,
          firstAuthorFamily:
              paper.authors.isNotEmpty ? paper.authors.first.familyName : null,
        );
      }
      if (found == null) continue;

      final merged = service.mergeEnrichment(paper, crossref: found);
      if (service.diff(paper, merged).isNotEmpty) {
        await dao.updatePaper(merged);
        improved++;
      }
    }

    await ref.read(libraryProvider.notifier).refresh();
    messenger.showSnackBar(
        SnackBar(content: Text('Improved $improved of ${incomplete.length} papers')));
  }

  Future<void> _checkRetractions(BuildContext context, WidgetRef ref) async {
    final messenger = ScaffoldMessenger.of(context);
    final dao = ref.read(paperDaoProvider);
    final papers = await dao.getAllPapers();
    final withDoi = papers.where((p) => p.doi != null).toList();

    if (withDoi.isEmpty) {
      messenger.showSnackBar(const SnackBar(
          content: Text('No papers with a DOI to check')));
      return;
    }

    messenger.showSnackBar(SnackBar(
        content: Text('Checking ${withDoi.length} DOIs with Crossref...')));

    final service = RetractionService();
    final notices =
        await service.checkDois(withDoi.map((p) => p.doi!).toList());

    var flagged = 0;
    for (final paper in withDoi) {
      final notice = notices[paper.doi!.toLowerCase()];
      final published = service.publishedVersionDoiFrom(paper.cslJson);
      if (notice == null && published == null) continue;

      await dao.setUpdateStatus(
        paper.id!,
        status: notice?.type ?? 'preprint_superseded',
        noticeDoi: notice?.noticeDoi,
        publishedVersionDoi: published,
      );
      flagged++;
    }

    await ref.read(libraryProvider.notifier).refresh();
    messenger.showSnackBar(SnackBar(
        content: Text(flagged == 0
            ? 'No retractions or updates found'
            : 'Flagged $flagged papers — see their detail pages')));
  }

  Future<void> _exportAnnotationSummaries(
      BuildContext context, WidgetRef ref) async {
    final messenger = ScaffoldMessenger.of(context);
    final dirPath = await FilePicker.platform.getDirectoryPath(
      dialogTitle: 'Export annotation summaries to...',
    );
    if (dirPath == null) return;

    final papers = ref.read(libraryProvider).value ??
        await ref.read(paperDaoProvider).getAllPapers();
    final annotationDao = ref.read(annotationDaoProvider);
    final exportService = ExportService();
    final style = citationStyleFor(
        ref.read(settingsProvider).value?.defaultCitationStyle ??
            DefaultCitationStyle.apa);

    var exported = 0;
    for (final paper in papers) {
      if (paper.id == null) continue;
      final records = await annotationDao.getForPaper(paper.id!);
      if (records.isEmpty) continue;

      final annotations = records.map(AnnotationModel.fromRecord).toList();
      final markdown = exportService.toMarkdownSummary(
        paper,
        annotations,
        formattedCitation: style.format(paper),
      );
      final safeName = (paper.bibtexKey ?? 'paper_${paper.id}')
          .replaceAll(RegExp(r'[^\w\-]'), '_');
      await File(p.join(dirPath, '$safeName.md')).writeAsString(markdown);
      exported++;
    }

    messenger.showSnackBar(SnackBar(
        content: Text(exported == 0
            ? 'No papers with annotations to export'
            : 'Exported $exported annotation summaries')));
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

/// Picks a folder to monitor; any PDF landing there is imported and flagged
/// for review.
class _WatchedFolderTile extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final path = ref.watch(watchedFolderPathProvider).value;

    return ListTile(
      leading: const Icon(Icons.folder_special_outlined),
      title: const Text('Watched folder'),
      subtitle: Text(path ?? 'Off — pick a folder to auto-import new PDFs'),
      trailing: path == null
          ? null
          : IconButton(
              icon: const Icon(Icons.close),
              tooltip: 'Stop watching',
              onPressed: () =>
                  ref.read(watchedFolderPathProvider.notifier).setPath(null),
            ),
      onTap: () async {
        final chosen = await FilePicker.platform.getDirectoryPath(
          dialogTitle: 'Watch a folder for new PDFs',
        );
        if (chosen != null) {
          await ref.read(watchedFolderPathProvider.notifier).setPath(chosen);
        }
      },
    );
  }
}

/// Registers .bib files that are rewritten whenever the library changes.
class _AutoBibExportTile extends ConsumerStatefulWidget {
  @override
  ConsumerState<_AutoBibExportTile> createState() => _AutoBibExportTileState();
}

class _AutoBibExportTileState extends ConsumerState<_AutoBibExportTile> {
  List<AutoExportRecord> _targets = const [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final targets = await ref.read(autoExportDaoProvider).getAll();
    if (mounted) setState(() => _targets = targets);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ListTile(
          leading: const Icon(Icons.sync_alt),
          title: const Text('Auto-export BibTeX'),
          subtitle: Text(_targets.isEmpty
              ? 'Keep a .bib file in sync for LaTeX / Overleaf'
              : '${_targets.length} file${_targets.length == 1 ? '' : 's'} kept up to date'),
          trailing: IconButton(
            icon: const Icon(Icons.add),
            tooltip: 'Add a .bib target',
            onPressed: _addTarget,
          ),
          onTap: _addTarget,
        ),
        for (final target in _targets)
          Padding(
            padding: const EdgeInsets.only(left: 56, right: 16, bottom: 4),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    target.targetPath,
                    style: theme.textTheme.bodySmall,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close, size: 18),
                  tooltip: 'Remove',
                  onPressed: () async {
                    await ref.read(autoExportDaoProvider).delete(target.id!);
                    await _load();
                  },
                ),
              ],
            ),
          ),
      ],
    );
  }

  Future<void> _addTarget() async {
    final path = await FilePicker.platform.saveFile(
      dialogTitle: 'Choose where to keep the .bib file',
      fileName: 'library.bib',
      type: FileType.custom,
      allowedExtensions: ['bib'],
    );
    if (path == null) return;

    await ref
        .read(autoExportDaoProvider)
        .insert(AutoExportRecord(targetPath: path));
    // Write it immediately so the file exists right away.
    final papers = await ref.read(paperDaoProvider).getAllPapers();
    await writeBibFile(path, ExportService().toBibtexMultiple(papers));
    await _load();
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
