import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../database/daos/paper_dao.dart';
import '../models/author_model.dart';
import '../models/paper_model.dart';
import 'drive_service.dart';

enum SyncStatus { idle, syncing, success, error }

class SyncState {
  final SyncStatus status;
  final String? message;
  final int uploadedCount;
  final int downloadedCount;
  final DateTime? lastSyncTime;

  const SyncState({
    this.status = SyncStatus.idle,
    this.message,
    this.uploadedCount = 0,
    this.downloadedCount = 0,
    this.lastSyncTime,
  });

  SyncState copyWith({
    SyncStatus? status,
    String? message,
    int? uploadedCount,
    int? downloadedCount,
    DateTime? lastSyncTime,
  }) {
    return SyncState(
      status: status ?? this.status,
      message: message ?? this.message,
      uploadedCount: uploadedCount ?? this.uploadedCount,
      downloadedCount: downloadedCount ?? this.downloadedCount,
      lastSyncTime: lastSyncTime ?? this.lastSyncTime,
    );
  }
}

/// Handles syncing papers and PDFs between local DB and Google Drive.
///
/// Strategy (like git push/pull):
/// - Push: Upload local PDFs that don't have a driveFileId yet
/// - Pull: Download Drive files that aren't cached locally
/// - Metadata is exported as a JSON manifest alongside PDFs
class DriveSyncService {
  static const _manifestFileName = 'papers_manifest.json';

  final DriveService _driveService;
  final PaperDao _paperDao;

  DriveSyncService({
    required DriveService driveService,
    required PaperDao paperDao,
  })  : _driveService = driveService,
        _paperDao = paperDao;

  /// Full sync: pull remote changes first, then push local state.
  Future<SyncState> sync() async {
    try {
      // Pull: merge remote manifest first, so papers created on other
      // devices exist locally before we upload our manifest (which
      // replaces the remote one).
      await _pullManifest();

      // Push: upload PDFs that aren't on Drive yet
      final uploaded = await _pushPdfs();

      // Pull: download PDFs from Drive that we don't have locally
      final downloaded = await _pullPdfs();

      // Push: upload the merged metadata manifest
      await _pushManifest();

      return SyncState(
        status: SyncStatus.success,
        message: 'Sync complete',
        uploadedCount: uploaded,
        downloadedCount: downloaded,
        lastSyncTime: DateTime.now(),
      );
    } catch (e) {
      return SyncState(
        status: SyncStatus.error,
        message: e.toString(),
      );
    }
  }

  /// Upload local PDFs that don't have a Drive file ID.
  Future<int> _pushPdfs() async {
    final papers = await _paperDao.getAllPapers();
    var count = 0;

    for (final paper in papers) {
      if (paper.localPdfPath != null &&
          paper.driveFileId == null &&
          File(paper.localPdfPath!).existsSync()) {
        final fileName = p.basename(paper.localPdfPath!);
        final driveId = await _driveService.uploadPdf(
          localPath: paper.localPdfPath!,
          fileName: fileName,
        );

        await _paperDao.updatePaper(
          paper.copyWith(driveFileId: driveId),
        );
        count++;
      }
    }

    return count;
  }

  /// Download Drive PDFs that we don't have locally and link them to their
  /// paper records so they can be opened from the app.
  Future<int> _pullPdfs() async {
    final driveFiles = await _driveService.listFiles();
    final papers = await _paperDao.getAllPapers();
    final papersByDriveId = {
      for (final paper in papers)
        if (paper.driveFileId != null) paper.driveFileId!: paper,
    };

    final docsDir = await getApplicationDocumentsDirectory();
    final pdfsDir = Directory(p.join(docsDir.path, 'papers_pdfs'));
    if (!pdfsDir.existsSync()) {
      pdfsDir.createSync(recursive: true);
    }

    var count = 0;
    for (final driveFile in driveFiles) {
      if (driveFile.name == _manifestFileName) continue;

      final paper = papersByDriveId[driveFile.id];
      if (paper != null &&
          paper.localPdfPath != null &&
          File(paper.localPdfPath!).existsSync()) {
        continue;
      }

      final localPath = p.join(pdfsDir.path, driveFile.name);
      await _driveService.downloadFile(
        driveFileId: driveFile.id,
        localPath: localPath,
      );

      if (paper != null) {
        await _paperDao.updatePaper(paper.copyWith(localPdfPath: localPath));
      } else {
        // A PDF on Drive that no paper references (e.g. uploaded before a
        // manifest existed): add a stub entry so it shows up in the library.
        final now = DateTime.now();
        await _paperDao.insertPaper(PaperModel(
          title: p.basenameWithoutExtension(driveFile.name),
          driveFileId: driveFile.id,
          localPdfPath: localPath,
          dateAdded: now,
          dateModified: now,
        ));
      }
      count++;
    }

    return count;
  }

  /// Export library metadata as JSON and upload to Drive.
  Future<void> _pushManifest() async {
    final papers = await _paperDao.getAllPapers();

    final manifest = papers.map((paper) => {
      'title': paper.title,
      'abstract': paper.abstract_,
      'doi': paper.doi,
      'year': paper.year,
      'journal': paper.journal,
      'volume': paper.volume,
      'issue': paper.issue,
      'pages': paper.pages,
      'publisher': paper.publisher,
      'url': paper.url,
      'drive_file_id': paper.driveFileId,
      'is_favorite': paper.isFavorite,
      'bibtex_key': paper.bibtexKey,
      'authors': paper.authors.map((a) => {
        'given_name': a.givenName,
        'family_name': a.familyName,
        'orcid': a.orcid,
      }).toList(),
      'tags': paper.tags,
    }).toList();

    final jsonStr = const JsonEncoder.withIndent('  ').convert(manifest);

    final tempDir = await getApplicationDocumentsDirectory();
    final tempFile = File(p.join(tempDir.path, _manifestFileName));
    await tempFile.writeAsString(jsonStr);

    // Delete old manifest on Drive
    final driveFiles = await _driveService.listFiles();
    for (final f in driveFiles) {
      if (f.name == _manifestFileName) {
        await _driveService.deleteFile(f.id);
      }
    }

    await _driveService.uploadPdf(
      localPath: tempFile.path,
      fileName: _manifestFileName,
    );

    await tempFile.delete();
  }

  /// Download and merge remote manifest — add papers we don't have locally.
  Future<void> _pullManifest() async {
    final driveFiles = await _driveService.listFiles();
    final manifestFile = driveFiles
        .where((f) => f.name == _manifestFileName)
        .firstOrNull;

    if (manifestFile == null) return;

    final tempDir = await getApplicationDocumentsDirectory();
    final tempPath = p.join(tempDir.path, 'papers_manifest_remote.json');
    await _driveService.downloadFile(
      driveFileId: manifestFile.id,
      localPath: tempPath,
    );

    final jsonStr = await File(tempPath).readAsString();
    final manifest = jsonDecode(jsonStr) as List<dynamic>;

    // Existing papers, indexed for duplicate detection. DOI is the primary
    // key; Drive file ID and normalized title cover papers without one.
    final localPapers = await _paperDao.getAllPapers();
    final knownDois = {
      for (final paper in localPapers)
        if (paper.doi != null) paper.doi!,
    };
    final knownDriveIds = {
      for (final paper in localPapers)
        if (paper.driveFileId != null) paper.driveFileId!,
    };
    final knownTitles = {
      for (final paper in localPapers) paper.title.trim().toLowerCase(),
    };

    for (final entry in manifest) {
      final map = entry as Map<String, dynamic>;
      final doi = map['doi'] as String?;
      final driveFileId = map['drive_file_id'] as String?;
      final title = (map['title'] as String?)?.trim().toLowerCase();

      if (doi != null && knownDois.contains(doi)) continue;
      if (driveFileId != null && knownDriveIds.contains(driveFileId)) continue;
      if (doi == null &&
          driveFileId == null &&
          title != null &&
          knownTitles.contains(title)) {
        continue;
      }

      final now = DateTime.now();
      final authors = (map['authors'] as List<dynamic>? ?? []).map((a) {
        final authorMap = a as Map<String, dynamic>;
        return AuthorModel(
          givenName: authorMap['given_name'] as String?,
          familyName: authorMap['family_name'] as String? ?? 'Unknown',
          orcid: authorMap['orcid'] as String?,
        );
      }).toList();

      final paper = PaperModel(
        title: map['title'] as String? ?? 'Untitled',
        abstract_: map['abstract'] as String?,
        doi: doi,
        year: map['year'] as String?,
        journal: map['journal'] as String?,
        volume: map['volume'] as String?,
        issue: map['issue'] as String?,
        pages: map['pages'] as String?,
        publisher: map['publisher'] as String?,
        url: map['url'] as String?,
        driveFileId: map['drive_file_id'] as String?,
        isFavorite: map['is_favorite'] as bool? ?? false,
        bibtexKey: map['bibtex_key'] as String?,
        authors: authors,
        tags: (map['tags'] as List<dynamic>? ?? []).cast<String>(),
        dateAdded: now,
        dateModified: now,
      );

      await _paperDao.insertPaper(paper);
      if (doi != null) knownDois.add(doi);
      if (driveFileId != null) knownDriveIds.add(driveFileId);
      knownTitles.add(paper.title.trim().toLowerCase());
    }

    await File(tempPath).delete();
  }
}
