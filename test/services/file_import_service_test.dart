import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:papers/features/import/services/file_import_service.dart';
import 'package:path/path.dart' as p;

void main() {
  final service = FileImportService();

  late Directory dir;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('papers_attach');
  });

  tearDown(() async {
    if (dir.existsSync()) await dir.delete(recursive: true);
  });

  test('resolves an absolute path that exists', () async {
    final file = File(p.join(dir.path, 'paper.pdf'));
    await file.writeAsString('%PDF-1.4');

    expect(service.resolveExistingPath(file.path, null), file.path);
  });

  test('resolves a relative path against the base directory', () async {
    final sub = Directory(p.join(dir.path, 'files'))..createSync();
    await File(p.join(sub.path, 'a.pdf')).writeAsString('%PDF-1.4');

    final resolved = service.resolveExistingPath('files/a.pdf', dir.path);
    expect(resolved, isNotNull);
    expect(File(resolved!).existsSync(), isTrue);
  });

  test('an absolute path wins even when a base dir is given', () async {
    final file = File(p.join(dir.path, 'abs.pdf'));
    await file.writeAsString('%PDF-1.4');

    expect(service.resolveExistingPath(file.path, r'C:\somewhere\else'),
        file.path);
  });

  test('returns null when the file is missing', () {
    expect(
      service.resolveExistingPath(p.join(dir.path, 'nope.pdf'), dir.path),
      isNull,
    );
    expect(service.resolveExistingPath('relative/nope.pdf', dir.path), isNull);
  });
}
