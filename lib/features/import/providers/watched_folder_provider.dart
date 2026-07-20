import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../library/providers/library_provider.dart';
import '../services/watched_folder_service.dart';
import 'pdf_import_provider.dart';

const _watchedFolderKey = 'watched_folder_path';

/// The folder Papers monitors for new PDFs (null = feature off).
final watchedFolderPathProvider =
    AsyncNotifierProvider<WatchedFolderPathNotifier, String?>(
  WatchedFolderPathNotifier.new,
);

class WatchedFolderPathNotifier extends AsyncNotifier<String?> {
  @override
  Future<String?> build() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_watchedFolderKey);
  }

  Future<void> setPath(String? path) async {
    final prefs = await SharedPreferences.getInstance();
    if (path == null) {
      await prefs.remove(_watchedFolderKey);
    } else {
      await prefs.setString(_watchedFolderKey, path);
    }
    state = AsyncData(path);
  }
}

/// Runs the folder watcher while a path is configured. Watched once from
/// SciApp so it lives as long as the app does.
final watchedFolderControllerProvider = Provider<void>((ref) {
  final path = ref.watch(watchedFolderPathProvider).value;
  if (path == null) return;

  final service = WatchedFolderService();
  service.start(
    path,
    onPdf: (pdfPath) async {
      // Unattended import: flag it so the user can review the metadata.
      final paper = await ref
          .read(fileImportServiceProvider)
          .importPdf(pdfPath, needsReview: true);
      await ref.read(libraryProvider.notifier).addPaper(paper);
    },
  );

  ref.onDispose(service.stop);
});
