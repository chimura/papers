import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/models/author_model.dart';
import '../../../core/models/paper_model.dart';
import '../providers/library_provider.dart';

/// Opens the metadata editor for [paper]. Returns true if changes were saved.
Future<bool?> showEditPaperDialog(BuildContext context, PaperModel paper) {
  return showDialog<bool>(
    context: context,
    builder: (context) => EditPaperDialog(paper: paper),
  );
}

class EditPaperDialog extends ConsumerStatefulWidget {
  final PaperModel paper;

  const EditPaperDialog({super.key, required this.paper});

  @override
  ConsumerState<EditPaperDialog> createState() => _EditPaperDialogState();
}

class _EditPaperDialogState extends ConsumerState<EditPaperDialog> {
  final _formKey = GlobalKey<FormState>();

  late final _title = TextEditingController(text: widget.paper.title);
  late final _authors = TextEditingController(
    text: widget.paper.authors
        .map((a) =>
            a.givenName == null ? a.familyName : '${a.familyName}, ${a.givenName}')
        .join('\n'),
  );
  late final _year = TextEditingController(text: widget.paper.year ?? '');
  late final _journal = TextEditingController(text: widget.paper.journal ?? '');
  late final _volume = TextEditingController(text: widget.paper.volume ?? '');
  late final _issue = TextEditingController(text: widget.paper.issue ?? '');
  late final _pages = TextEditingController(text: widget.paper.pages ?? '');
  late final _doi = TextEditingController(text: widget.paper.doi ?? '');
  late final _url = TextEditingController(text: widget.paper.url ?? '');
  late final _abstract =
      TextEditingController(text: widget.paper.abstract_ ?? '');
  late final _tags = TextEditingController(text: widget.paper.tags.join(', '));

  bool _saving = false;

  @override
  void dispose() {
    for (final c in [
      _title, _authors, _year, _journal, _volume, _issue,
      _pages, _doi, _url, _abstract, _tags,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Edit details'),
      content: SizedBox(
        width: 560,
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextFormField(
                  controller: _title,
                  decoration: const InputDecoration(labelText: 'Title'),
                  maxLines: 2,
                  minLines: 1,
                  validator: (v) =>
                      (v == null || v.trim().isEmpty) ? 'Title is required' : null,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _authors,
                  decoration: const InputDecoration(
                    labelText: 'Authors',
                    helperText: 'One per line, as "Family, Given"',
                  ),
                  maxLines: 4,
                  minLines: 2,
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: TextFormField(
                        controller: _year,
                        decoration: const InputDecoration(labelText: 'Year'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      flex: 3,
                      child: TextFormField(
                        controller: _journal,
                        decoration: const InputDecoration(labelText: 'Journal'),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: TextFormField(
                        controller: _volume,
                        decoration: const InputDecoration(labelText: 'Volume'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextFormField(
                        controller: _issue,
                        decoration: const InputDecoration(labelText: 'Issue'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextFormField(
                        controller: _pages,
                        decoration: const InputDecoration(labelText: 'Pages'),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _doi,
                  decoration: const InputDecoration(labelText: 'DOI'),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _url,
                  decoration: const InputDecoration(labelText: 'URL'),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _tags,
                  decoration: const InputDecoration(
                    labelText: 'Tags',
                    helperText: 'Comma-separated',
                  ),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _abstract,
                  decoration: const InputDecoration(labelText: 'Abstract'),
                  maxLines: 6,
                  minLines: 3,
                ),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.pop(context, false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _saving ? null : _save,
          child: Text(_saving ? 'Saving...' : 'Save'),
        ),
      ],
    );
  }

  Future<void> _save() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    setState(() => _saving = true);

    String? emptyToNull(TextEditingController c) {
      final v = c.text.trim();
      return v.isEmpty ? null : v;
    }

    final original = widget.paper;
    final updated = PaperModel(
      id: original.id,
      title: _title.text.trim(),
      abstract_: emptyToNull(_abstract),
      doi: emptyToNull(_doi),
      year: emptyToNull(_year),
      journal: emptyToNull(_journal),
      volume: emptyToNull(_volume),
      issue: emptyToNull(_issue),
      pages: emptyToNull(_pages),
      publisher: original.publisher,
      url: emptyToNull(_url),
      localPdfPath: original.localPdfPath,
      driveFileId: original.driveFileId,
      isFavorite: original.isFavorite,
      dateAdded: original.dateAdded,
      dateModified: DateTime.now(),
      cslJson: original.cslJson,
      bibtexKey: original.bibtexKey,
      authors: _parseAuthors(_authors.text),
      tags: _tags.text
          .split(',')
          .map((t) => t.trim())
          .where((t) => t.isNotEmpty)
          .toList(),
    );

    try {
      await ref.read(libraryProvider.notifier).updatePaperDetails(updated);
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        setState(() => _saving = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not save: $e')),
        );
      }
    }
  }

  List<AuthorModel> _parseAuthors(String text) {
    return text
        .split('\n')
        .expand((line) => line.split(RegExp(r'\band\b')))
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty)
        .map((name) {
      if (name.contains(',')) {
        final parts = name.split(',').map((s) => s.trim()).toList();
        return AuthorModel(
          familyName: parts[0],
          givenName: parts.length > 1 && parts[1].isNotEmpty ? parts[1] : null,
        );
      }
      final parts = name.split(RegExp(r'\s+'));
      if (parts.length == 1) return AuthorModel(familyName: parts[0]);
      return AuthorModel(
        givenName: parts.sublist(0, parts.length - 1).join(' '),
        familyName: parts.last,
      );
    }).toList();
  }
}
