import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/database/daos/note_dao.dart';
import '../providers/note_provider.dart';

/// Freeform Markdown notes for one paper — the Notebook. Quotes captured
/// from the reader land here as blockquotes with page backlinks.
class NotesPanel extends ConsumerWidget {
  final int paperId;

  const NotesPanel({super.key, required this.paperId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final notesAsync = ref.watch(paperNotesProvider(paperId));

    return notesAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text('Could not load notes: $e')),
      data: (notes) {
        if (notes.isEmpty) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.edit_note,
                    size: 48,
                    color: theme.colorScheme.onSurfaceVariant
                        .withValues(alpha: 0.4)),
                const SizedBox(height: 12),
                Text('No notes yet', style: theme.textTheme.titleSmall),
                const SizedBox(height: 4),
                Text(
                  'Write your own, or send highlights here from the reader.',
                  style: theme.textTheme.bodySmall,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 12),
                FilledButton.tonalIcon(
                  onPressed: () => ref
                      .read(noteActionsProvider)
                      .create(paperId: paperId, title: 'Notes'),
                  icon: const Icon(Icons.add, size: 18),
                  label: const Text('Start a note'),
                ),
              ],
            ),
          );
        }

        return ListView.separated(
          padding: const EdgeInsets.all(12),
          itemCount: notes.length + 1,
          separatorBuilder: (_, _) => const SizedBox(height: 12),
          itemBuilder: (context, index) {
            if (index == notes.length) {
              return Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: () => ref
                      .read(noteActionsProvider)
                      .create(paperId: paperId, title: 'Note'),
                  icon: const Icon(Icons.add, size: 18),
                  label: const Text('Add another note'),
                ),
              );
            }
            return _NoteCard(note: notes[index]);
          },
        );
      },
    );
  }
}

class _NoteCard extends ConsumerStatefulWidget {
  final NoteRecord note;
  const _NoteCard({required this.note});

  @override
  ConsumerState<_NoteCard> createState() => _NoteCardState();
}

class _NoteCardState extends ConsumerState<_NoteCard> {
  late final TextEditingController _body =
      TextEditingController(text: widget.note.bodyMd);
  bool _dirty = false;

  @override
  void didUpdateWidget(_NoteCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Adopt external changes (e.g. a quote appended from the reader) only
    // when the user has no unsaved edits of their own.
    if (!_dirty && widget.note.bodyMd != _body.text) {
      _body.text = widget.note.bodyMd;
    }
  }

  @override
  void dispose() {
    _body.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    await ref.read(noteActionsProvider).save(
          NoteRecord(
            id: widget.note.id,
            paperId: widget.note.paperId,
            title: widget.note.title,
            bodyMd: _body.text,
            createdAt: widget.note.createdAt,
            updatedAt: DateTime.now(),
          ),
        );
    if (mounted) setState(() => _dirty = false);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.notes, size: 16, color: theme.colorScheme.primary),
                const SizedBox(width: 6),
                Text(widget.note.title ?? 'Note',
                    style: theme.textTheme.titleSmall),
                const Spacer(),
                if (_dirty)
                  TextButton(onPressed: _save, child: const Text('Save')),
                IconButton(
                  icon: const Icon(Icons.delete_outline, size: 18),
                  tooltip: 'Delete note',
                  onPressed: () =>
                      ref.read(noteActionsProvider).delete(widget.note),
                ),
              ],
            ),
            TextField(
              controller: _body,
              maxLines: null,
              minLines: 4,
              style: theme.textTheme.bodyMedium,
              decoration: const InputDecoration(
                border: InputBorder.none,
                hintText: 'Markdown supported...',
                isDense: true,
              ),
              onChanged: (_) {
                if (!_dirty) setState(() => _dirty = true);
              },
              onEditingComplete: _save,
            ),
          ],
        ),
      ),
    );
  }
}
