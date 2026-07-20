import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/database/database_provider.dart';
import '../../../core/models/paper_model.dart';
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
