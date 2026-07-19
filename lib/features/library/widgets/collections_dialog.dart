import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/database/daos/collection_dao.dart';
import '../providers/collection_providers.dart';

/// Lets the user choose which collections [paperId] belongs to,
/// and create new collections inline.
Future<void> showCollectionsDialog(BuildContext context, int paperId) {
  return showDialog(
    context: context,
    builder: (context) => CollectionsDialog(paperId: paperId),
  );
}

class CollectionsDialog extends ConsumerStatefulWidget {
  final int paperId;

  const CollectionsDialog({super.key, required this.paperId});

  @override
  ConsumerState<CollectionsDialog> createState() => _CollectionsDialogState();
}

class _CollectionsDialogState extends ConsumerState<CollectionsDialog> {
  final _newCollectionController = TextEditingController();
  Set<int>? _selected; // null until loaded

  @override
  void dispose() {
    _newCollectionController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final collectionsAsync = ref.watch(collectionsProvider);
    final memberIdsAsync =
        ref.watch(paperCollectionIdsProvider(widget.paperId));

    // Initialize the selection once the current membership loads.
    if (_selected == null && memberIdsAsync.hasValue) {
      _selected = Set.of(memberIdsAsync.value!);
    }

    return AlertDialog(
      title: const Text('Collections'),
      content: SizedBox(
        width: 400,
        child: collectionsAsync.when(
          loading: () => const SizedBox(
            height: 80,
            child: Center(child: CircularProgressIndicator()),
          ),
          error: (e, _) => Text('Could not load collections: $e'),
          data: (collections) => Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (collections.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Text(
                    'No collections yet — create one below.',
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                )
              else
                Flexible(
                  child: ListView(
                    shrinkWrap: true,
                    children: collections
                        .map((c) => CheckboxListTile(
                              title: Text(c.name),
                              value: _selected?.contains(c.id) ?? false,
                              onChanged: _selected == null
                                  ? null
                                  : (checked) => setState(() {
                                        if (checked ?? false) {
                                          _selected!.add(c.id!);
                                        } else {
                                          _selected!.remove(c.id);
                                        }
                                      }),
                            ))
                        .toList(),
                  ),
                ),
              const Divider(),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _newCollectionController,
                      decoration: const InputDecoration(
                        hintText: 'New collection name',
                        isDense: true,
                      ),
                      onSubmitted: (_) => _createCollection(),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.add),
                    tooltip: 'Create collection',
                    onPressed: _createCollection,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _selected == null ? null : _save,
          child: const Text('Save'),
        ),
      ],
    );
  }

  Future<void> _createCollection() async {
    final name = _newCollectionController.text.trim();
    if (name.isEmpty) return;

    final dao = ref.read(collectionDaoProvider);
    final id = await dao.insert(CollectionRecord(
      name: name,
      createdAt: DateTime.now(),
    ));
    _newCollectionController.clear();
    ref.invalidate(collectionsProvider);
    setState(() => (_selected ??= {}).add(id));
  }

  Future<void> _save() async {
    final dao = ref.read(collectionDaoProvider);
    final before = await dao.getCollectionIdsForPaper(widget.paperId);
    final after = _selected!;

    for (final id in after.difference(before)) {
      await dao.addPaperToCollection(widget.paperId, id);
    }
    for (final id in before.difference(after)) {
      await dao.removePaperFromCollection(widget.paperId, id);
    }

    ref.invalidate(collectionPaperIdsProvider);
    ref.invalidate(paperCollectionIdsProvider(widget.paperId));
    if (mounted) Navigator.pop(context);
  }
}
