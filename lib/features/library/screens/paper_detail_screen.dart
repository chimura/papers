import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:url_launcher/url_launcher.dart';

import '../../../core/database/database_provider.dart';
import '../../../core/models/paper_model.dart';
import '../../citations/screens/citation_screen.dart';
import '../../citations/services/citation_clipboard.dart';
import '../../citations/services/export_service.dart';
import '../../enrichment/services/unpaywall_service.dart';
import '../../import/services/file_import_service.dart';
import '../../notes/widgets/notes_panel.dart';
import '../../reader/models/annotation_model.dart';
import '../../reader/providers/annotation_provider.dart';
import '../../reader/screens/reader_screen.dart';
import '../../settings/models/app_settings.dart';
import '../../settings/providers/settings_provider.dart';
import '../providers/library_provider.dart';
import '../widgets/collections_dialog.dart';
import '../widgets/edit_paper_dialog.dart';

class PaperDetailScreen extends ConsumerStatefulWidget {
  final PaperModel paper;

  const PaperDetailScreen({super.key, required this.paper});

  @override
  ConsumerState<PaperDetailScreen> createState() => _PaperDetailScreenState();
}

class _PaperDetailScreenState extends ConsumerState<PaperDetailScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController =
      TabController(length: 2, vsync: this);

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final paper = widget.paper;

    // Resolve the live version of this paper so favorite toggles and edits
    // are reflected immediately; fall back to the snapshot we were given.
    final live = ref
            .watch(libraryProvider)
            .value
            ?.where((p) => p.id == paper.id)
            .firstOrNull ??
        paper;

    return _build(context, ref, theme, live);
  }

  Widget _build(BuildContext context, WidgetRef ref, ThemeData theme,
      PaperModel paper) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Paper Details'),
        actions: [
          IconButton(
            icon: Icon(
              paper.isFavorite ? Icons.star : Icons.star_border,
              color: paper.isFavorite ? Colors.amber : null,
            ),
            tooltip:
                paper.isFavorite ? 'Remove from favorites' : 'Add to favorites',
            onPressed: () {
              if (paper.id != null) {
                ref
                    .read(libraryProvider.notifier)
                    .toggleFavorite(paper.id!, !paper.isFavorite);
              }
            },
          ),
          IconButton(
            icon: const Icon(Icons.edit_outlined),
            tooltip: 'Edit details',
            onPressed: () => showEditPaperDialog(context, paper),
          ),
          PopupMenuButton<String>(
            onSelected: (action) => _handleAction(context, ref, paper, action),
            itemBuilder: (context) => [
              if (paper.localPdfPath != null)
                const PopupMenuItem(
                  value: 'open_pdf',
                  child: ListTile(
                    leading: Icon(Icons.picture_as_pdf),
                    title: Text('Open PDF'),
                    contentPadding: EdgeInsets.zero,
                  ),
                ),
              if (paper.doi != null && paper.localPdfPath == null)
                const PopupMenuItem(
                  value: 'find_oa_pdf',
                  child: ListTile(
                    leading: Icon(Icons.download_outlined),
                    title: Text('Find open-access PDF'),
                    contentPadding: EdgeInsets.zero,
                  ),
                ),
              const PopupMenuItem(
                value: 'collections',
                child: ListTile(
                  leading: Icon(Icons.folder_outlined),
                  title: Text('Collections...'),
                  contentPadding: EdgeInsets.zero,
                ),
              ),
              const PopupMenuItem(
                value: 'copy_markdown',
                child: ListTile(
                  leading: Icon(Icons.notes_outlined),
                  title: Text('Copy notes as Markdown'),
                  contentPadding: EdgeInsets.zero,
                ),
              ),
              const PopupMenuItem(
                value: 'save_markdown',
                child: ListTile(
                  leading: Icon(Icons.save_alt),
                  title: Text('Save notes (.md)'),
                  contentPadding: EdgeInsets.zero,
                ),
              ),
              if (paper.doi != null)
                const PopupMenuItem(
                  value: 'copy_doi',
                  child: ListTile(
                    leading: Icon(Icons.copy),
                    title: Text('Copy DOI'),
                    contentPadding: EdgeInsets.zero,
                  ),
                ),
              const PopupMenuItem(
                value: 'cite',
                child: ListTile(
                  leading: Icon(Icons.format_quote),
                  title: Text('Cite & Export'),
                  contentPadding: EdgeInsets.zero,
                ),
              ),
              const PopupMenuItem(
                value: 'delete',
                child: ListTile(
                  leading: Icon(Icons.delete_outline, color: Colors.red),
                  title: Text('Delete', style: TextStyle(color: Colors.red)),
                  contentPadding: EdgeInsets.zero,
                ),
              ),
            ],
          ),
        ],
        bottom: paper.id == null
            ? null
            : TabBar(
                controller: _tabController,
                tabs: const [
                  Tab(text: 'Details'),
                  Tab(text: 'Notes'),
                ],
              ),
      ),
      body: paper.id == null
          ? _detailsTab(context, ref, theme, paper)
          : TabBarView(
              controller: _tabController,
              children: [
                _detailsTab(context, ref, theme, paper),
                NotesPanel(paperId: paper.id!),
              ],
            ),
      floatingActionButton: paper.localPdfPath != null
          ? FloatingActionButton.extended(
              onPressed: () => _openReader(context, ref, paper),
              icon: const Icon(Icons.menu_book),
              label: const Text('Read'),
            )
          : null,
    );
  }

  Widget _detailsTab(BuildContext context, WidgetRef ref, ThemeData theme,
      PaperModel paper) {
    return ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (paper.updateStatus != null) _UpdateBanner(paper: paper),
          // Title
          Text(
            paper.title,
            style: theme.textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 12),

          // Authors
          if (paper.authors.isNotEmpty) ...[
            Text(
              paper.authors.map((a) => a.displayName).join(', '),
              style: theme.textTheme.bodyLarge?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 12),
          ],

          // Metadata chips
          Wrap(
            spacing: 8,
            runSpacing: 4,
            children: [
              if (paper.year != null) _chip(theme, Icons.calendar_today, paper.year!),
              if (paper.journal != null) _chip(theme, Icons.book, paper.journal!),
              if (paper.volume != null)
                _chip(theme, Icons.layers, 'Vol. ${paper.volume}'),
              if (paper.issue != null)
                _chip(theme, Icons.tag, 'Issue ${paper.issue}'),
              if (paper.pages != null) _chip(theme, Icons.description, paper.pages!),
              if (paper.localPdfPath != null)
                _chip(theme, Icons.picture_as_pdf, 'PDF available'),
            ],
          ),
          const SizedBox(height: 8),

          // DOI
          if (paper.doi != null) ...[
            InkWell(
              onTap: () => _openDoi(paper.doi!),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Text(
                  'DOI: ${paper.doi}',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.primary,
                    decoration: TextDecoration.underline,
                  ),
                ),
              ),
            ),
          ],

          // Tags
          if (paper.tags.isNotEmpty) ...[
            const SizedBox(height: 8),
            Wrap(
              spacing: 6,
              children: paper.tags
                  .map((tag) => Chip(
                        label: Text(tag),
                        visualDensity: VisualDensity.compact,
                      ))
                  .toList(),
            ),
          ],

          // Abstract
          if (paper.abstract_ != null) ...[
            const SizedBox(height: 16),
            const Divider(),
            const SizedBox(height: 12),
            Text('Abstract', style: theme.textTheme.titleMedium),
            const SizedBox(height: 8),
            SelectableText(
              paper.abstract_!,
              style: theme.textTheme.bodyMedium?.copyWith(height: 1.6),
            ),
          ],

          // Publisher
          if (paper.publisher != null) ...[
            const SizedBox(height: 16),
            const Divider(),
            const SizedBox(height: 8),
            Text(
              'Publisher: ${paper.publisher}',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],

          const SizedBox(height: 32),
        ],
      );
  }

  /// Opens the reader and refreshes the library on return so reading
  /// progress shows up immediately.
  void _openReader(BuildContext context, WidgetRef ref, PaperModel paper) {
    Navigator.of(context)
        .push(MaterialPageRoute(builder: (_) => ReaderScreen(paper: paper)))
        .then((_) => ref.read(libraryProvider.notifier).refresh());
  }

  Widget _chip(ThemeData theme, IconData icon, String label) {
    return Chip(
      avatar: Icon(icon, size: 16),
      label: Text(label),
      visualDensity: VisualDensity.compact,
      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
    );
  }

  void _handleAction(
      BuildContext context, WidgetRef ref, PaperModel paper, String action) {
    switch (action) {
      case 'open_pdf':
        _openReader(context, ref, paper);
      case 'find_oa_pdf':
        _findOaPdf(context, ref, paper);
      case 'copy_markdown':
        _copyMarkdownSummary(context, ref, paper);
      case 'save_markdown':
        _saveMarkdownSummary(context, ref, paper);
      case 'collections':
        if (paper.id != null) {
          showCollectionsDialog(context, paper.id!);
        }
      case 'cite':
        Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => CitationScreen(paper: paper)),
        );
      case 'copy_doi':
        if (paper.doi != null) {
          Clipboard.setData(ClipboardData(text: paper.doi!));
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('DOI copied to clipboard')),
          );
        }
      case 'delete':
        final confirm =
            ref.read(settingsProvider).value?.confirmBeforeDelete ?? true;
        if (confirm) {
          _confirmDelete(context, ref, paper);
        } else {
          _deletePaper(context, ref, paper);
        }
    }
  }

  void _confirmDelete(BuildContext context, WidgetRef ref, PaperModel paper) {
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Delete paper?'),
        content: const Text('This will remove the paper from your library.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              Navigator.pop(dialogContext);
              _deletePaper(context, ref, paper);
            },
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
            ),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }

  /// Deletes the paper and leaves the detail view — by popping when this
  /// screen was pushed as a page, or by clearing the master-detail selection
  /// when it is embedded in the wide layout.
  void _deletePaper(BuildContext context, WidgetRef ref, PaperModel paper) {
    if (paper.id != null) {
      ref.read(libraryProvider.notifier).deletePaper(paper.id!);
    }
    ref.read(selectedPaperProvider.notifier).select(null);
    final navigator = Navigator.of(context);
    if (navigator.canPop()) {
      navigator.pop();
    }
  }

  Future<void> _findOaPdf(
      BuildContext context, WidgetRef ref, PaperModel paper) async {
    final messenger = ScaffoldMessenger.of(context);
    messenger.showSnackBar(
        const SnackBar(content: Text('Searching Unpaywall...')));

    final pdfsDir = await FileImportService().pdfsDirectory();
    final safeName = (paper.bibtexKey ?? 'paper_${paper.id}')
        .replaceAll(RegExp(r'[^\w\-]'), '_');
    final savePath = p.join(pdfsDir.path, '$safeName.pdf');

    final ok =
        await UnpaywallService().fetchOaPdf(doi: paper.doi!, savePath: savePath);
    if (ok) {
      await ref
          .read(paperDaoProvider)
          .updatePaper(paper.copyWith(localPdfPath: savePath));
      await ref.read(libraryProvider.notifier).refresh();
      messenger.showSnackBar(
          const SnackBar(content: Text('Open-access PDF downloaded')));
    } else {
      messenger.showSnackBar(const SnackBar(
          content: Text('No open-access PDF found for this DOI')));
    }
  }

  Future<String?> _buildMarkdownSummary(
      WidgetRef ref, PaperModel paper) async {
    if (paper.id == null) return null;
    final records =
        await ref.read(annotationDaoProvider).getForPaper(paper.id!);
    final annotations = records.map(AnnotationModel.fromRecord).toList();
    final style = citationStyleFor(
        ref.read(settingsProvider).value?.defaultCitationStyle ??
            DefaultCitationStyle.apa);
    final withKey = await ensureCitationKey(ref, paper);
    return ExportService().toMarkdownSummary(
      withKey,
      annotations,
      formattedCitation: style.format(paper),
    );
  }

  Future<void> _copyMarkdownSummary(
      BuildContext context, WidgetRef ref, PaperModel paper) async {
    final messenger = ScaffoldMessenger.of(context);
    final markdown = await _buildMarkdownSummary(ref, paper);
    if (markdown == null) return;
    await Clipboard.setData(ClipboardData(text: markdown));
    messenger.showSnackBar(
        const SnackBar(content: Text('Markdown summary copied')));
  }

  Future<void> _saveMarkdownSummary(
      BuildContext context, WidgetRef ref, PaperModel paper) async {
    final messenger = ScaffoldMessenger.of(context);
    final markdown = await _buildMarkdownSummary(ref, paper);
    if (markdown == null) return;

    final safeName = (paper.bibtexKey ?? 'paper_${paper.id}')
        .replaceAll(RegExp(r'[^\w\-]'), '_');
    final savePath = await FilePicker.platform.saveFile(
      dialogTitle: 'Save annotation summary',
      fileName: '$safeName.md',
      type: FileType.custom,
      allowedExtensions: ['md'],
    );
    if (savePath == null) return;

    await File(savePath).writeAsString(markdown);
    messenger.showSnackBar(SnackBar(
        content: Text('Saved ${p.basename(savePath)}')));
  }

  Future<void> _openDoi(String doi) async {
    final uri = Uri.parse('https://doi.org/$doi');
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }
}

/// Retraction / correction / preprint-superseded banner.
class _UpdateBanner extends ConsumerWidget {
  final PaperModel paper;

  const _UpdateBanner({required this.paper});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final serious = paper.updateStatus == 'retraction' ||
        paper.updateStatus == 'expression_of_concern';

    final (String title, String body) = switch (paper.updateStatus) {
      'retraction' => (
          'This paper has been retracted',
          'Crossref reports a retraction notice. Do not cite it as valid work.'
        ),
      'expression_of_concern' => (
          'Expression of concern',
          'The publisher has flagged concerns about this paper.'
        ),
      'correction' => (
          'A correction was published',
          'Check the correction notice before citing specifics.'
        ),
      'preprint_superseded' => (
          'Published version available',
          'This preprint has since been published in a journal.'
        ),
      _ => ('Publication update', 'Crossref reports an update for this DOI.'),
    };

    final color =
        serious ? theme.colorScheme.error : theme.colorScheme.tertiary;

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        border: Border.all(color: color),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(serious ? Icons.report : Icons.info_outline, color: color),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: theme.textTheme.titleSmall
                        ?.copyWith(color: color, fontWeight: FontWeight.bold)),
                const SizedBox(height: 2),
                Text(body, style: theme.textTheme.bodySmall),
                if (paper.updateNoticeDoi != null)
                  TextButton(
                    style: TextButton.styleFrom(
                        padding: EdgeInsets.zero,
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap),
                    onPressed: () => launchUrl(
                      Uri.parse('https://doi.org/${paper.updateNoticeDoi}'),
                      mode: LaunchMode.externalApplication,
                    ),
                    child: const Text('Read the notice'),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
