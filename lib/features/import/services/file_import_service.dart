import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../../core/models/paper_model.dart';
import 'metadata_extractor.dart';

/// Imports a PDF from an arbitrary path (file picker, drag-and-drop, watched
/// folder): copies it into the app's PDF directory and builds a PaperModel
/// with whatever metadata can be extracted. Does not insert into the library.
class FileImportService {
  final MetadataExtractor _extractor;

  FileImportService({MetadataExtractor? extractor})
      : _extractor = extractor ?? MetadataExtractor();

  Future<Directory> pdfsDirectory() async {
    final docsDir = await getApplicationDocumentsDirectory();
    final pdfsDir = Directory(p.join(docsDir.path, 'papers_pdfs'));
    if (!pdfsDir.existsSync()) {
      pdfsDir.createSync(recursive: true);
    }
    return pdfsDir;
  }

  /// [needsReview] marks unattended imports (watched folder) so the user can
  /// find and verify them later.
  Future<PaperModel> importPdf(String sourcePath,
      {bool needsReview = false}) async {
    final pdfsDir = await pdfsDirectory();
    final destPath = _uniqueDestination(pdfsDir, p.basename(sourcePath));
    await File(sourcePath).copy(destPath);

    final filename = p.basename(sourcePath);
    // Read the PDF itself (embedded DOI/arXiv id, XMP, title lookup) and
    // only fall back to guessing from the filename.
    final metadataPaper = await _extractor.fromPdf(destPath) ??
        await _extractor.fromFilename(filename);

    final now = DateTime.now();
    return metadataPaper?.copyWith(
          localPdfPath: destPath,
          needsReview: needsReview,
        ) ??
        PaperModel(
          title: p.basenameWithoutExtension(filename),
          localPdfPath: destPath,
          needsReview: needsReview,
          dateAdded: now,
          dateModified: now,
        );
  }

  /// Avoids silently overwriting a different file with the same name.
  String _uniqueDestination(Directory dir, String filename) {
    var candidate = p.join(dir.path, filename);
    if (!File(candidate).existsSync()) return candidate;

    final base = p.basenameWithoutExtension(filename);
    final ext = p.extension(filename);
    for (var i = 1;; i++) {
      candidate = p.join(dir.path, '$base ($i)$ext');
      if (!File(candidate).existsSync()) return candidate;
    }
  }
}
