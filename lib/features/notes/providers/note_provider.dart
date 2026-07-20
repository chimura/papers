import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/database/daos/note_dao.dart';

final noteDaoProvider = Provider<NoteDao>((ref) => NoteDao());

/// Notes attached to one paper, newest first.
final paperNotesProvider =
    FutureProvider.family<List<NoteRecord>, int>((ref, paperId) async {
  return ref.read(noteDaoProvider).getForPaper(paperId);
});

/// Cross-paper topic pages (paper_id IS NULL).
final topicPagesProvider = FutureProvider<List<NoteRecord>>((ref) async {
  return ref.read(noteDaoProvider).getTopicPages();
});

final noteActionsProvider = Provider<NoteActions>((ref) => NoteActions(ref));

class NoteActions {
  final Ref _ref;
  NoteActions(this._ref);

  Future<int> create({int? paperId, String? title, String body = ''}) async {
    final now = DateTime.now();
    final id = await _ref.read(noteDaoProvider).insert(NoteRecord(
          paperId: paperId,
          title: title,
          bodyMd: body,
          createdAt: now,
          updatedAt: now,
        ));
    _invalidate(paperId);
    return id;
  }

  Future<void> save(NoteRecord note) async {
    await _ref.read(noteDaoProvider).update(note);
    _invalidate(note.paperId);
  }

  Future<void> delete(NoteRecord note) async {
    if (note.id == null) return;
    await _ref.read(noteDaoProvider).delete(note.id!);
    _invalidate(note.paperId);
  }

  /// Appends a highlighted passage as a blockquote with a page backlink.
  Future<void> appendQuote({
    required int paperId,
    required String quote,
    required int page,
  }) async {
    await _ref
        .read(noteDaoProvider)
        .appendQuote(paperId: paperId, quote: quote, page: page);
    _invalidate(paperId);
  }

  void _invalidate(int? paperId) {
    if (paperId != null) {
      _ref.invalidate(paperNotesProvider(paperId));
    } else {
      _ref.invalidate(topicPagesProvider);
    }
  }
}
