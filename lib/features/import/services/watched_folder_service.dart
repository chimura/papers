import 'dart:async';
import 'dart:io';

import 'package:path/path.dart' as p;

/// Watches a folder for newly arrived PDFs and reports each one once it has
/// finished being written (browsers create the file before filling it).
class WatchedFolderService {
  final Duration settleDelay;
  final Duration settleTimeout;

  StreamSubscription<FileSystemEvent>? _subscription;
  final Set<String> _seen = {};
  final Set<String> _inFlight = {};

  WatchedFolderService({
    this.settleDelay = const Duration(milliseconds: 600),
    this.settleTimeout = const Duration(seconds: 30),
  });

  bool get isWatching => _subscription != null;

  /// Starts watching [folderPath]; [onPdf] fires once per new PDF with its
  /// full path. Existing files are ignored — only new arrivals count.
  Future<void> start(
    String folderPath, {
    required Future<void> Function(String path) onPdf,
    void Function(Object error)? onError,
  }) async {
    await stop();

    final dir = Directory(folderPath);
    if (!dir.existsSync()) return;

    // Pre-seed with what is already there so we don't re-import the folder.
    for (final entity in dir.listSync()) {
      if (entity is File && _isPdf(entity.path)) _seen.add(entity.path);
    }

    _subscription = dir.watch(events: FileSystemEvent.all).listen(
      (event) async {
        final path = event.path;
        if (!_isPdf(path)) return;

        if (event is FileSystemDeleteEvent) {
          _seen.remove(path);
          return;
        }
        if (_seen.contains(path) || _inFlight.contains(path)) return;

        _inFlight.add(path);
        try {
          if (await _waitUntilStable(path)) {
            _seen.add(path);
            await onPdf(path);
          }
        } catch (e) {
          onError?.call(e);
        } finally {
          _inFlight.remove(path);
        }
      },
      onError: (Object e) => onError?.call(e),
      cancelOnError: false,
    );
  }

  Future<void> stop() async {
    await _subscription?.cancel();
    _subscription = null;
    _inFlight.clear();
  }

  bool _isPdf(String path) => p.extension(path).toLowerCase() == '.pdf';

  /// A download is complete when the file size stops changing and the file
  /// can be opened for reading (still-locked downloads throw on Windows).
  Future<bool> _waitUntilStable(String path) async {
    final file = File(path);
    final deadline = DateTime.now().add(settleTimeout);
    int? lastSize;

    while (DateTime.now().isBefore(deadline)) {
      await Future<void>.delayed(settleDelay);
      if (!file.existsSync()) return false;

      int size;
      try {
        size = await file.length();
      } catch (_) {
        continue;
      }

      if (size > 0 && size == lastSize) {
        try {
          final handle = await file.open();
          await handle.close();
          return true;
        } catch (_) {
          // Still locked by the writer; keep waiting.
        }
      }
      lastSize = size;
    }
    return false;
  }
}
