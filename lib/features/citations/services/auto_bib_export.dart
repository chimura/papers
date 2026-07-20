import 'dart:async';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/database/daos/auto_export_dao.dart';
import '../../../core/database/database_provider.dart';
import '../../library/providers/collection_providers.dart';
import 'export_service.dart';

/// Bumped by every library write so exports know something changed.
final libraryRevisionProvider =
    NotifierProvider<LibraryRevisionNotifier, int>(LibraryRevisionNotifier.new);

class LibraryRevisionNotifier extends Notifier<int> {
  @override
  int build() => 0;

  void bump() => state++;
}

final autoExportDaoProvider =
    Provider<AutoExportDao>((ref) => AutoExportDao());

/// Keeps registered .bib files on disk in sync with the library, so
/// `\cite{key}` in LaTeX/Overleaf always resolves. Watched once from SciApp.
final autoBibExportProvider = Provider<void>((ref) {
  final revision = ref.watch(libraryRevisionProvider);
  if (revision == 0) return; // nothing has changed yet this session

  Timer? debounce;
  debounce = Timer(const Duration(seconds: 3), () async {
    try {
      final targets = await ref.read(autoExportDaoProvider).getAll();
      if (targets.isEmpty) return;

      final papers = await ref.read(paperDaoProvider).getAllPapers();
      final exportService = ExportService();

      for (final target in targets) {
        var scoped = papers;
        if (target.collectionId != null) {
          final memberIds = await ref
              .read(collectionDaoProvider)
              .getPaperIdsInSubtree(target.collectionId!);
          scoped =
              papers.where((p) => memberIds.contains(p.id)).toList();
        }
        await writeBibFile(
            target.targetPath, exportService.toBibtexMultiple(scoped));
        await ref
            .read(autoExportDaoProvider)
            .markExported(target.id!, DateTime.now());
      }
    } catch (_) {
      // An unwritable target must never break the app.
    }
  });

  ref.onDispose(() => debounce?.cancel());
});

/// Writes atomically so a reader (Overleaf sync, latexmk) never sees a
/// half-written file.
Future<void> writeBibFile(String path, String contents) async {
  final tmp = File('$path.tmp');
  await tmp.writeAsString(contents, flush: true);
  await tmp.rename(path);
}

/// Call after any library mutation to schedule the debounced export.
void markLibraryChanged(Ref ref) {
  ref.read(libraryRevisionProvider.notifier).bump();
}
