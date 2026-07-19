import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/database/database_provider.dart';
import '../../../core/models/paper_model.dart';

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
    final id = await dao.insertPaper(paper);
    await refresh();
    return id;
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
