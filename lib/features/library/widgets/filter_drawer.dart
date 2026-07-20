import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/database/daos/collection_dao.dart';
import '../../../core/database/daos/smart_collection_dao.dart';
import '../../../core/models/paper_model.dart';
import '../models/library_filter.dart';
import '../providers/collection_providers.dart';
import '../providers/library_filter_provider.dart';

class FilterDrawer extends ConsumerWidget {
  const FilterDrawer({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final filter = ref.watch(libraryFilterProvider);
    final collectionsAsync = ref.watch(collectionsProvider);
    final tagsAsync = ref.watch(allTagsProvider);

    return Drawer(
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Text('Filters', style: theme.textTheme.titleLarge),
                  const Spacer(),
                  if (filter.isActive)
                    TextButton(
                      onPressed: () =>
                          ref.read(libraryFilterProvider.notifier).clearAll(),
                      child: const Text('Clear all'),
                    ),
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  // Favorites toggle
                  SwitchListTile(
                    title: const Text('Favorites only'),
                    secondary: const Icon(Icons.star),
                    value: filter.favoritesOnly,
                    onChanged: (_) => ref
                        .read(libraryFilterProvider.notifier)
                        .toggleFavorites(),
                  ),
                  SwitchListTile(
                    title: const Text('Missing PDF'),
                    secondary: const Icon(Icons.picture_as_pdf_outlined),
                    value: filter.missingPdfOnly,
                    onChanged: (_) => ref
                        .read(libraryFilterProvider.notifier)
                        .toggleMissingPdf(),
                  ),
                  SwitchListTile(
                    title: const Text('Needs review'),
                    subtitle: const Text('Auto-imported, unverified metadata'),
                    secondary: const Icon(Icons.fiber_new),
                    value: filter.needsReviewOnly,
                    onChanged: (_) => ref
                        .read(libraryFilterProvider.notifier)
                        .toggleNeedsReview(),
                  ),
                  const SizedBox(height: 16),

                  // Reading status
                  Text('Reading status', style: theme.textTheme.titleSmall),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    children: [
                      ChoiceChip(
                        label: const Text('Any'),
                        selected: filter.readStatus == null,
                        onSelected: (_) => ref
                            .read(libraryFilterProvider.notifier)
                            .setReadStatus(null),
                      ),
                      ...ReadStatus.values.map((status) => ChoiceChip(
                            label: Text(status.label),
                            selected: filter.readStatus == status,
                            onSelected: (_) => ref
                                .read(libraryFilterProvider.notifier)
                                .setReadStatus(status),
                          )),
                    ],
                  ),
                  const SizedBox(height: 16),

                  // Saved searches
                  _SmartCollectionsSection(currentFilter: filter),
                  const SizedBox(height: 16),

                  // Sort
                  Text('Sort by', style: theme.textTheme.titleSmall),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    children: SortOption.values.map((option) {
                      final isSelected = filter.sortBy == option;
                      return ChoiceChip(
                        label: Text(option.label),
                        selected: isSelected,
                        onSelected: (_) => ref
                            .read(libraryFilterProvider.notifier)
                            .setSortBy(option),
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      const Text('Direction:'),
                      const SizedBox(width: 8),
                      IconButton(
                        icon: Icon(filter.sortDescending
                            ? Icons.arrow_downward
                            : Icons.arrow_upward),
                        onPressed: () => ref
                            .read(libraryFilterProvider.notifier)
                            .toggleSortDirection(),
                      ),
                      Text(filter.sortDescending
                          ? 'Newest first'
                          : 'Oldest first'),
                    ],
                  ),
                  const SizedBox(height: 16),

                  // Collections
                  Row(
                    children: [
                      Text('Collections', style: theme.textTheme.titleSmall),
                      const Spacer(),
                      IconButton(
                        icon: const Icon(Icons.add, size: 20),
                        tooltip: 'New collection',
                        visualDensity: VisualDensity.compact,
                        onPressed: () => _createCollection(context, ref),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  collectionsAsync.when(
                    loading: () =>
                        const Center(child: CircularProgressIndicator()),
                    error: (e, _) => Text('Error: $e'),
                    data: (collections) {
                      if (collections.isEmpty) {
                        return Text(
                          'No collections yet — use + to create one, then '
                          'add papers from their detail menu.',
                          style: theme.textTheme.bodySmall,
                        );
                      }
                      return Wrap(
                        spacing: 8,
                        children: [
                          ChoiceChip(
                            label: const Text('All'),
                            selected: filter.collectionId == null,
                            onSelected: (_) => ref
                                .read(libraryFilterProvider.notifier)
                                .setCollection(null),
                          ),
                          ...collections.map((c) => GestureDetector(
                                onLongPress: () =>
                                    _deleteCollection(context, ref, c),
                                child: ChoiceChip(
                                  label: Text(c.name),
                                  selected: filter.collectionId == c.id,
                                  tooltip: 'Long-press to delete',
                                  onSelected: (_) => ref
                                      .read(libraryFilterProvider.notifier)
                                      .setCollection(c.id),
                                ),
                              )),
                        ],
                      );
                    },
                  ),
                  const SizedBox(height: 16),

                  // Tags
                  Text('Tags', style: theme.textTheme.titleSmall),
                  const SizedBox(height: 8),
                  tagsAsync.when(
                    loading: () =>
                        const Center(child: CircularProgressIndicator()),
                    error: (e, _) => Text('Error: $e'),
                    data: (tags) {
                      if (tags.isEmpty) {
                        return Text(
                          'No tags yet',
                          style: theme.textTheme.bodySmall,
                        );
                      }
                      return Wrap(
                        spacing: 8,
                        children: tags
                            .map((tag) => FilterChip(
                                  label: Text(tag),
                                  selected: filter.tags.contains(tag),
                                  onSelected: (_) => ref
                                      .read(libraryFilterProvider.notifier)
                                      .toggleTag(tag),
                                ))
                            .toList(),
                      );
                    },
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<String?> _promptForName(
      BuildContext context, String title, String label) async {
    final controller = TextEditingController();
    final value = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: InputDecoration(labelText: label),
          onSubmitted: (v) => Navigator.pop(dialogContext, v),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, controller.text),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    controller.dispose();
    final trimmed = value?.trim() ?? '';
    return trimmed.isEmpty ? null : trimmed;
  }

  Future<void> _createCollection(BuildContext context, WidgetRef ref) async {
    final controller = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('New collection'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(labelText: 'Name'),
          onSubmitted: (value) => Navigator.pop(dialogContext, value),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, controller.text),
            child: const Text('Create'),
          ),
        ],
      ),
    );
    controller.dispose();

    final trimmed = name?.trim() ?? '';
    if (trimmed.isEmpty) return;
    await ref.read(collectionDaoProvider).insert(CollectionRecord(
          name: trimmed,
          createdAt: DateTime.now(),
        ));
    ref.invalidate(collectionsProvider);
  }

  Future<void> _deleteCollection(
      BuildContext context, WidgetRef ref, CollectionRecord collection) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('Delete "${collection.name}"?'),
        content: const Text('Papers in the collection are not deleted.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    await ref.read(collectionDaoProvider).delete(collection.id!);
    if (ref.read(libraryFilterProvider).collectionId == collection.id) {
      ref.read(libraryFilterProvider.notifier).setCollection(null);
    }
    ref.invalidate(collectionsProvider);
    ref.invalidate(collectionPaperIdsProvider);
  }
}

final smartCollectionDaoProvider =
    Provider<SmartCollectionDao>((ref) => SmartCollectionDao());

final smartCollectionsProvider =
    FutureProvider<List<SmartCollectionRecord>>((ref) async {
  return ref.read(smartCollectionDaoProvider).getAll();
});

/// Saved searches: the current filter state, stored by name and restorable
/// with one tap.
class _SmartCollectionsSection extends ConsumerWidget {
  final LibraryFilter currentFilter;

  const _SmartCollectionsSection({required this.currentFilter});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final saved = ref.watch(smartCollectionsProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text('Saved searches', style: theme.textTheme.titleSmall),
            const Spacer(),
            IconButton(
              icon: const Icon(Icons.bookmark_add_outlined, size: 20),
              tooltip: 'Save current filters',
              visualDensity: VisualDensity.compact,
              onPressed: currentFilter.isActive
                  ? () => _save(context, ref)
                  : null,
            ),
          ],
        ),
        const SizedBox(height: 4),
        saved.when(
          loading: () => const SizedBox.shrink(),
          error: (e, _) => Text('Error: $e', style: theme.textTheme.bodySmall),
          data: (records) {
            if (records.isEmpty) {
              return Text(
                currentFilter.isActive
                    ? 'Tap the bookmark to save these filters.'
                    : 'Set some filters, then save them here.',
                style: theme.textTheme.bodySmall,
              );
            }
            return Wrap(
              spacing: 8,
              children: records
                  .map((record) => GestureDetector(
                        onLongPress: () => _delete(context, ref, record),
                        child: ActionChip(
                          avatar: const Icon(Icons.bolt, size: 16),
                          label: Text(record.name),
                          tooltip: 'Long-press to delete',
                          onPressed: () {
                            ref.read(libraryFilterProvider.notifier).replace(
                                  LibraryFilter.fromJson(
                                      jsonDecode(record.filterJson)
                                          as Map<String, dynamic>),
                                );
                            Navigator.of(context).maybePop();
                          },
                        ),
                      ))
                  .toList(),
            );
          },
        ),
      ],
    );
  }

  Future<void> _save(BuildContext context, WidgetRef ref) async {
    final name = await const FilterDrawer()
        ._promptForName(context, 'Save current filters', 'Name');
    if (name == null) return;

    await ref.read(smartCollectionDaoProvider).insert(SmartCollectionRecord(
          name: name,
          filterJson: jsonEncode(currentFilter.toJson()),
          createdAt: DateTime.now(),
        ));
    ref.invalidate(smartCollectionsProvider);
  }

  Future<void> _delete(
      BuildContext context, WidgetRef ref, SmartCollectionRecord r) async {
    await ref.read(smartCollectionDaoProvider).delete(r.id!);
    ref.invalidate(smartCollectionsProvider);
  }
}
