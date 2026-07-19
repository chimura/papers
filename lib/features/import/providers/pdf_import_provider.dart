import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../../core/models/paper_model.dart';
import '../services/metadata_extractor.dart';

final metadataExtractorProvider = Provider<MetadataExtractor>(
  (ref) => MetadataExtractor(),
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

      // Copy PDF to app documents directory
      final docsDir = await getApplicationDocumentsDirectory();
      final pdfsDir = Directory(p.join(docsDir.path, 'papers_pdfs'));
      if (!pdfsDir.existsSync()) {
        pdfsDir.createSync(recursive: true);
      }

      final filename = p.basename(sourcePath);
      final destPath = p.join(pdfsDir.path, filename);
      await File(sourcePath).copy(destPath);

      // Try to extract metadata from filename
      final extractor = ref.read(metadataExtractorProvider);
      final metadataPaper = await extractor.fromFilename(filename);

      final now = DateTime.now();
      final paper = metadataPaper?.copyWith(localPdfPath: destPath) ??
          PaperModel(
            title: p.basenameWithoutExtension(filename),
            localPdfPath: destPath,
            dateAdded: now,
            dateModified: now,
          );

      state = PdfImportState(paper: paper, localPath: destPath);
    } catch (e) {
      state = PdfImportState(error: e.toString());
    }
  }

  void reset() {
    state = const PdfImportState();
  }
}
