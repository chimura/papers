import 'package:file_picker/file_picker.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/models/paper_model.dart';
import '../services/file_import_service.dart';
import '../services/metadata_extractor.dart';

final metadataExtractorProvider = Provider<MetadataExtractor>(
  (ref) => MetadataExtractor(),
);

final fileImportServiceProvider = Provider<FileImportService>(
  (ref) => FileImportService(extractor: ref.read(metadataExtractorProvider)),
);

class PdfImportState {
  final bool isLoading;
  final PaperModel? paper;
  final String? localPath;
  final String? error;

  const PdfImportState({
    this.isLoading = false,
    this.paper,
    this.localPath,
    this.error,
  });
}

final pdfImportProvider =
    NotifierProvider<PdfImportNotifier, PdfImportState>(
  PdfImportNotifier.new,
);

class PdfImportNotifier extends Notifier<PdfImportState> {
  @override
  PdfImportState build() => const PdfImportState();

  Future<void> pickAndImportPdf() async {
    state = const PdfImportState(isLoading: true);

    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['pdf'],
      );

      if (result == null || result.files.isEmpty) {
        state = const PdfImportState();
        return;
      }

      final file = result.files.first;
      final sourcePath = file.path;
      if (sourcePath == null) {
        state = const PdfImportState(error: 'Could not access file');
        return;
      }

      final paper =
          await ref.read(fileImportServiceProvider).importPdf(sourcePath);
      state = PdfImportState(paper: paper, localPath: paper.localPdfPath);
    } catch (e) {
      state = PdfImportState(error: e.toString());
    }
  }

  void reset() {
    state = const PdfImportState();
  }
}
