import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/models/paper_model.dart';
import '../services/bibtex_parser_service.dart';

final bibtexParserProvider = Provider<BibtexParserService>(
  (ref) => BibtexParserService(),
);

class BibtexImportState {
  final List<PaperModel> papers;
  final String? error;

  /// Directory of the opened .bib/.ris file, used to resolve relative PDF
  /// paths (null for pasted text).
  final String? sourceDir;

  const BibtexImportState({
    this.papers = const [],
    this.error,
    this.sourceDir,
  });
}

final bibtexImportProvider =
    NotifierProvider<BibtexImportNotifier, BibtexImportState>(
  BibtexImportNotifier.new,
);

class BibtexImportNotifier extends Notifier<BibtexImportState> {
  @override
  BibtexImportState build() => const BibtexImportState();

  void parseBibtex(String bibtex, {String? sourceDir}) {
    try {
      final parser = ref.read(bibtexParserProvider);
      final papers = parser.parse(bibtex);
      state = BibtexImportState(papers: papers, sourceDir: sourceDir);
    } catch (e) {
      state = BibtexImportState(error: e.toString());
    }
  }

  /// Used by the RIS file path, which parses elsewhere but shares this
  /// preview list.
  void setPapers(List<PaperModel> papers, {String? sourceDir}) {
    state = BibtexImportState(
      papers: papers,
      sourceDir: sourceDir,
      error: papers.isEmpty ? 'No entries found in that file' : null,
    );
  }

  void reset() {
    state = const BibtexImportState();
  }
}
