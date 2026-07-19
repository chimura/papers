import 'dart:io';

import 'package:googleapis/drive/v3.dart' as drive;
import 'package:http/http.dart' as http;

/// Manages PDF file storage in a visible "Papers" folder in the user's
/// Google Drive.
class DriveService {
  static const _appFolderName = 'Papers';
  static const _legacyFolderName = 'Sci';

  final http.Client _client;
  late final drive.DriveApi _driveApi;
  String? _appFolderId;

  DriveService(this._client) {
    _driveApi = drive.DriveApi(_client);
  }

  /// Ensure the "Papers" folder exists in Drive root, create if needed.
  /// A leftover "Sci" folder from before the app was renamed is adopted
  /// and renamed instead of being abandoned.
  Future<String> _getOrCreateAppFolder() async {
    if (_appFolderId != null) return _appFolderId!;

    final existingId = await _findFolder(_appFolderName);
    if (existingId != null) {
      return _appFolderId = existingId;
    }

    final legacyId = await _findFolder(_legacyFolderName);
    if (legacyId != null) {
      await _driveApi.files.update(drive.File()..name = _appFolderName, legacyId);
      return _appFolderId = legacyId;
    }

    final folder = drive.File()
      ..name = _appFolderName
      ..mimeType = 'application/vnd.google-apps.folder';

    final created = await _driveApi.files.create(folder);
    return _appFolderId = created.id!;
  }

  Future<String?> _findFolder(String name) async {
    final result = await _driveApi.files.list(
      q: "name = '$name' and mimeType = 'application/vnd.google-apps.folder' and trashed = false",
      spaces: 'drive',
      $fields: 'files(id, name)',
    );
    return result.files?.firstOrNull?.id;
  }

  /// Upload a PDF file to the Papers folder. Returns the Drive file ID.
  Future<String> uploadPdf({
    required String localPath,
    required String fileName,
  }) async {
    final folderId = await _getOrCreateAppFolder();
    final file = File(localPath);

    final driveFile = drive.File()
      ..name = fileName
      ..parents = [folderId];

    final media = drive.Media(file.openRead(), await file.length());
    final result = await _driveApi.files.create(
      driveFile,
      uploadMedia: media,
      $fields: 'id, name, modifiedTime',
    );

    return result.id!;
  }

  /// Download a file from Drive to local path.
  Future<void> downloadFile({
    required String driveFileId,
    required String localPath,
  }) async {
    final media = await _driveApi.files.get(
      driveFileId,
      downloadOptions: drive.DownloadOptions.fullMedia,
    ) as drive.Media;

    final file = File(localPath);
    final sink = file.openWrite();
    await media.stream.pipe(sink);
    await sink.close();
  }

  /// Delete a file from Drive.
  Future<void> deleteFile(String driveFileId) async {
    await _driveApi.files.delete(driveFileId);
  }

  /// List all files in the Papers folder.
  Future<List<DriveFileInfo>> listFiles() async {
    final folderId = await _getOrCreateAppFolder();

    final result = await _driveApi.files.list(
      q: "'$folderId' in parents and trashed = false",
      spaces: 'drive',
      $fields: 'files(id, name, modifiedTime, size)',
      orderBy: 'modifiedTime desc',
    );

    return (result.files ?? []).map((f) {
      return DriveFileInfo(
        id: f.id!,
        name: f.name ?? 'unknown',
        modifiedTime: f.modifiedTime,
        size: int.tryParse(f.size ?? '0') ?? 0,
      );
    }).toList();
  }

  /// Check if the Papers folder exists (user has synced before).
  Future<bool> hasAppFolder() async {
    final result = await _driveApi.files.list(
      q: "name = '$_appFolderName' and mimeType = 'application/vnd.google-apps.folder' and trashed = false",
      spaces: 'drive',
      $fields: 'files(id)',
    );
    return result.files != null && result.files!.isNotEmpty;
  }

  void dispose() {
    _client.close();
  }
}

class DriveFileInfo {
  final String id;
  final String name;
  final DateTime? modifiedTime;
  final int size;

  const DriveFileInfo({
    required this.id,
    required this.name,
    this.modifiedTime,
    this.size = 0,
  });
}
