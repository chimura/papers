import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../../core/models/paper_model.dart';
import 'metadata_extractor.dart';

/// Imports a PDF from an arbitrary path (file picker, drag-and-drop, watched
/// folder): copies it into the app's PDF directory and builds a PaperModel
/// with whatever metadata can be extracted. Does not insert into the library.
class FileImportService {
  final MetadataExtractor _extractor;
  final Future<Directory> Function()? _pdfsDirOverride;

  FileImportService({
    MetadataExtractor? extractor,
    @visibleForTesting Future<Directory> Function()? pdfsDirectory,
  })  : _extractor = extractor ?? MetadataExtractor(),
        _pdfsDirOverride = pdfsDirectory;

  Future<Directory> pdfsDirectory() async {
    if (_pdfsDirOverride != null) return _pdfsDirOverride();
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

  /// If [paper] carries an [PaperModel.importedFilePath] hint from a BibTeX/RIS
  /// import, resolve it (absolute, or relative to [baseDir]) and copy the PDF
  /// into the library. Returns the paper unchanged when there is no hint, it
  /// already has a PDF, or the file can't be found on disk.
  Future<PaperModel> attachImportedPdf(PaperModel paper,
      {String? baseDir}) async {
    final hint = paper.importedFilePath;
    if (hint == null || paper.localPdfPath != null) return paper;

    final source = resolveExistingPath(hint, baseDir);
    if (source == null) return paper;

    try {
      final dest =
          _uniqueDestination(await pdfsDirectory(), p.basename(source));
      await File(source).copy(dest);
      return paper.copyWith(localPdfPath: dest);
    } catch (_) {
      return paper;
    }
  }

  /// Returns the first existing file for [rawPath]: the path itself (when
  /// absolute) or joined onto [baseDir]. Null when nothing is found.
  String? resolveExistingPath(String rawPath, String? baseDir) {
    final candidates = <String>[
      rawPath,
      if (baseDir != null) p.join(baseDir, rawPath),
    ];
    for (final candidate in candidates) {
      try {
        if (File(candidate).existsSync()) return candidate;
      } catch (_) {
        // Malformed path on this platform — try the next candidate.
      }
    }
    return null;
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
