import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/database/database_provider.dart';
import '../../../core/models/paper_model.dart';
import '../../citations/services/auto_bib_export.dart';
import '../../citations/services/citekey_service.dart';
import '../../settings/models/app_settings.dart';
import '../../settings/providers/settings_provider.dart';

final libraryProvider =
    AsyncNotifierProvider<LibraryNotifier, List<PaperModel>>(
  LibraryNotifier.new,
);

/// Tracks the selected paper for the master-detail layout on wide screens.
final selectedPaperProvider =
    NotifierProvider<SelectedPaperNotifier, PaperModel?>(
  SelectedPaperNotifier.new,
);

class SelectedPaperNotifier extends Notifier<PaperModel?> {
  @override
  PaperModel? build() => null;

  void select(PaperModel? paper) => state = paper;
}

class LibraryNotifier extends AsyncNotifier<List<PaperModel>> {
  @override
  Future<List<PaperModel>> build() async {
    return ref.read(paperDaoProvider).getAllPapers();
  }

  Future<void> refresh() async {
    state = const AsyncValue.loading();
    state = await AsyncValue.guard(
      () => ref.read(paperDaoProvider).getAllPapers(),
    );
    markLibraryChanged(ref);
  }

  Future<void> setReadStatus(int id, ReadStatus status) async {
    await ref.read(paperDaoProvider).setReadStatus(id, status);
    await refresh();
  }

  /// Cycles unread → reading → read → unread from a single tap.
  Future<void> cycleReadStatus(PaperModel paper) async {
    if (paper.id == null) return;
    final next = switch (paper.readStatus) {
      ReadStatus.unread => ReadStatus.reading,
      ReadStatus.reading => ReadStatus.read,
      ReadStatus.read => ReadStatus.unread,
    };
    await setReadStatus(paper.id!, next);
  }

  Future<void> setQueued(int id, bool queued) async {
    final dao = ref.read(paperDaoProvider);
    if (queued) {
      final papers = state.value ?? await dao.getAllPapers();
      final maxPosition = papers
          .map((p) => p.queuePosition ?? -1)
          .fold<int>(-1, (a, b) => a > b ? a : b);
      await dao.setQueuePosition(id, maxPosition + 1);
    } else {
      await dao.setQueuePosition(id, null);
    }
    await refresh();
  }

  Future<void> saveQueueOrder(List<int> orderedIds) async {
    await ref.read(paperDaoProvider).saveQueueOrder(orderedIds);
    await refresh();
  }

  // ── Bulk actions ──

  Future<void> bulkSetFavorite(List<int> ids, bool isFavorite) async {
    await ref.read(paperDaoProvider).bulkSetFavorite(ids, isFavorite);
    await refresh();
  }

  Future<void> bulkSetReadStatus(List<int> ids, ReadStatus status) async {
    await ref.read(paperDaoProvider).bulkSetReadStatus(ids, status);
    await refresh();
  }

  Future<void> bulkAddTag(List<int> ids, String tag) async {
    await ref.read(paperDaoProvider).bulkAddTag(ids, tag);
    await refresh();
  }

  Future<void> bulkDelete(List<int> ids) async {
    await ref.read(paperDaoProvider).bulkDelete(ids);
    await refresh();
  }

  Future<int> addPaper(PaperModel paper) async {
    final dao = ref.read(paperDaoProvider);
    final id = await dao.insertPaper(await _withCitationKey(paper));
    await refresh();
    return id;
  }

  /// Every paper gets a unique citation key at insert time. Keys arriving
  /// from BibTeX/RIS imports are kept (uniquified if colliding) and pinned.
  Future<PaperModel> _withCitationKey(PaperModel paper) async {
    final existing = await ref.read(paperDaoProvider).getAllBibtexKeys();
    final service = CitekeyService();

    final imported = paper.bibtexKey;
    if (imported != null && imported.isNotEmpty) {
      return paper.copyWith(
        bibtexKey: service.ensureUnique(imported, existing),
        bibtexKeyPinned: true,
      );
    }

    final pattern = ref.read(settingsProvider).value?.citationKeyPattern ??
        AppSettings.defaultCitationKeyPattern;
    return paper.copyWith(
      bibtexKey: service.ensureUnique(
        service.generateKey(paper, pattern: pattern),
        existing,
      ),
    );
  }

  Future<void> updatePaperDetails(PaperModel paper) async {
    final dao = ref.read(paperDaoProvider);
    await dao.updatePaperWithRelations(paper);
    await refresh();
  }

  Future<void> deletePaper(int id) async {
    final dao = ref.read(paperDaoProvider);
    await dao.deletePaper(id);
    await refresh();
  }

  Future<void> toggleFavorite(int id, bool isFavorite) async {
    final dao = ref.read(paperDaoProvider);
    await dao.toggleFavorite(id, isFavorite);
    await refresh();
  }
}
