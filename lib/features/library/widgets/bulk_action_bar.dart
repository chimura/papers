import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/models/paper_model.dart';
import '../../citations/services/bibliography_builder.dart';
import '../../citations/services/citation_clipboard.dart';
import '../../settings/models/app_settings.dart';
import '../../settings/providers/settings_provider.dart';
import '../providers/collection_providers.dart';
import '../providers/library_provider.dart';
import '../providers/selection_provider.dart';

/// Replaces the library app bar while papers are multi-selected.
class BulkActionBar extends ConsumerWidget implements PreferredSizeWidget {
  const BulkActionBar({super.key});

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final selection = ref.watch(selectionProvider);
    final ids = selection.toList();

    return AppBar(
      backgroundColor: theme.colorScheme.secondaryContainer,
      leading: IconButton(
        icon: const Icon(Icons.close),
        tooltip: 'Cancel selection (Esc)',
        onPressed: () => ref.read(selectionProvider.notifier).clear(),
      ),
      title: Text('${ids.length} selected'),
      actions: [
        IconButton(
          icon: const Icon(Icons.star),
          tooltip: 'Add to favorites',
          onPressed: () => _run(
            context,
            ref,
            () => ref.read(libraryProvider.notifier).bulkSetFavorite(ids, true),
            '${ids.length} papers favorited',
          ),
        ),
        PopupMenuButton<ReadStatus>(
          icon: const Icon(Icons.auto_stories),
          tooltip: 'Set read status',
          onSelected: (status) => _run(
            context,
            ref,
            () => ref
                .read(libraryProvider.notifier)
                .bulkSetReadStatus(ids, status),
            'Marked ${ids.length} papers as ${status.label.toLowerCase()}',
          ),
          itemBuilder: (context) => ReadStatus.values
              .map((s) => PopupMenuItem(value: s, child: Text(s.label)))
              .toList(),
        ),
        IconButton(
          icon: const Icon(Icons.label_outline),
          tooltip: 'Add tag',
          onPressed: () => _addTag(context, ref, ids),
        ),
        IconButton(
          icon: const Icon(Icons.folder_outlined),
          tooltip: 'Add to collection',
          onPressed: () => _addToCollection(context, ref, ids),
        ),
        IconButton(
          icon: const Icon(Icons.format_quote),
          tooltip: 'Copy bibliography',
          onPressed: () => _copyBibliography(context, ref, ids),
        ),
        IconButton(
          icon: const Icon(Icons.delete_outline),
          tooltip: 'Delete',
          onPressed: () => _confirmDelete(context, ref, ids),
        ),
      ],
    );
  }

  Future<void> _run(
    BuildContext context,
    WidgetRef ref,
    Future<void> Function() action,
    String message,
  ) async {
    final messenger = ScaffoldMessenger.of(context);
    await action();
    ref.read(selectionProvider.notifier).clear();
    messenger.showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _addTag(
      BuildContext context, WidgetRef ref, List<int> ids) async {
    final controller = TextEditingController();
    final tag = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('Tag ${ids.length} papers'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(labelText: 'Tag name'),
          onSubmitted: (v) => Navigator.pop(dialogContext, v),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, controller.text),
            child: const Text('Add tag'),
          ),
        ],
      ),
    );
    controller.dispose();

    final trimmed = tag?.trim() ?? '';
    if (trimmed.isEmpty || !context.mounted) return;
    await _run(
      context,
      ref,
      () => ref.read(libraryProvider.notifier).bulkAddTag(ids, trimmed),
      'Tagged ${ids.length} papers with "$trimmed"',
    );
    ref.invalidate(allTagsProvider);
  }

  Future<void> _addToCollection(
      BuildContext context, WidgetRef ref, List<int> ids) async {
    final collections = await ref.read(collectionDaoProvider).getAll();
    if (!context.mounted) return;

    if (collections.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Create a collection first (filter drawer → +)')));
      return;
    }

    final chosen = await showDialog<int>(
      context: context,
      builder: (dialogContext) => SimpleDialog(
        title: Text('Add ${ids.length} papers to...'),
        children: collections
            .map((c) => SimpleDialogOption(
                  onPressed: () => Navigator.pop(dialogContext, c.id),
                  child: Text(c.name),
                ))
            .toList(),
      ),
    );
    if (chosen == null || !context.mounted) return;

    await _run(
      context,
      ref,
      () => ref.read(collectionDaoProvider).addPapersToCollection(ids, chosen),
      'Added ${ids.length} papers to the collection',
    );
    ref.invalidate(collectionPaperIdsProvider);
  }

  /// Builds one correctly sorted reference list from the selection.
  Future<void> _copyBibliography(
      BuildContext context, WidgetRef ref, List<int> ids) async {
    final messenger = ScaffoldMessenger.of(context);
    final papers = (ref.read(libraryProvider).value ?? const <PaperModel>[])
        .where((p) => ids.contains(p.id))
        .toList();
    if (papers.isEmpty) return;

    final style = citationStyleFor(
        ref.read(settingsProvider).value?.defaultCitationStyle ??
            DefaultCitationStyle.apa);
    final bibliography = BibliographyBuilder().build(papers, style);

    await Clipboard.setData(ClipboardData(text: bibliography));
    ref.read(selectionProvider.notifier).clear();
    messenger.showSnackBar(SnackBar(
        content: Text(
            '${papers.length}-entry ${style.shortName} bibliography copied')));
  }

  Future<void> _confirmDelete(
      BuildContext context, WidgetRef ref, List<int> ids) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('Delete ${ids.length} papers?'),
        content: const Text('This removes them from your library.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
            ),
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;

    await _run(
      context,
      ref,
      () => ref.read(libraryProvider.notifier).bulkDelete(ids),
      '${ids.length} papers deleted',
    );
  }
}
