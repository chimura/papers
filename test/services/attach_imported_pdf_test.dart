import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:papers/core/models/paper_model.dart';
import 'package:papers/features/import/services/file_import_service.dart';
import 'package:path/path.dart' as p;

PaperModel _paperWithHint(String hint, {String? localPdfPath}) {
  final now = DateTime.now();
  return PaperModel(
    title: 'Imported',
    localPdfPath: localPdfPath,
    importedFilePath: hint,
    dateAdded: now,
    dateModified: now,
  );
}

void main() {
  late Directory library; // stands in for papers_pdfs/
  late Directory source;
  late FileImportService service;

  setUp(() async {
    library = await Directory.systemTemp.createTemp('papers_lib');
    source = await Directory.systemTemp.createTemp('papers_src');
    service = FileImportService(pdfsDirectory: () async => library);
  });

  tearDown(() async {
    for (final d in [library, source]) {
      if (d.existsSync()) await d.delete(recursive: true);
    }
  });

  test('copies an absolute linked PDF into the library', () async {
    final src = File(p.join(source.path, 'paper.pdf'));
    await src.writeAsString('%PDF-1.4 hello');

    final result = await service.attachImportedPdf(_paperWithHint(src.path));

    expect(result.localPdfPath, isNotNull);
    final copied = File(result.localPdfPath!);
    expect(copied.existsSync(), isTrue);
    expect(await copied.readAsString(), '%PDF-1.4 hello');
    expect(p.equals(p.dirname(result.localPdfPath!), library.path), isTrue);
  });

  test('resolves a relative link against the export directory', () async {
    final sub = Directory(p.join(source.path, 'files'))..createSync();
    await File(p.join(sub.path, 'a.pdf')).writeAsString('%PDF-1.4');

    final result = await service.attachImportedPdf(
      _paperWithHint('files/a.pdf'),
      baseDir: source.path,
    );
    expect(result.localPdfPath, isNotNull);
    expect(File(result.localPdfPath!).existsSync(), isTrue);
  });

  test('gives copies distinct names instead of overwriting', () async {
    await File(p.join(source.path, 'paper.pdf')).writeAsString('one');
    final other = Directory(p.join(source.path, 'other'))..createSync();
    await File(p.join(other.path, 'paper.pdf')).writeAsString('two');

    final a =
        await service.attachImportedPdf(_paperWithHint(p.join(source.path, 'paper.pdf')));
    final b =
        await service.attachImportedPdf(_paperWithHint(p.join(other.path, 'paper.pdf')));

    expect(a.localPdfPath, isNot(b.localPdfPath));
    expect(await File(a.localPdfPath!).readAsString(), 'one');
    expect(await File(b.localPdfPath!).readAsString(), 'two');
  });

  test('leaves the paper unchanged when the file is missing', () async {
    final result = await service.attachImportedPdf(
      _paperWithHint(p.join(source.path, 'ghost.pdf')),
    );
    expect(result.localPdfPath, isNull);
  });

  test('never overwrites an existing PDF', () async {
    final src = File(p.join(source.path, 'paper.pdf'));
    await src.writeAsString('%PDF-1.4');

    final result = await service.attachImportedPdf(
      _paperWithHint(src.path, localPdfPath: r'C:\existing.pdf'),
    );
    expect(result.localPdfPath, r'C:\existing.pdf');
  });

  test('no-op when there is no hint', () async {
    final now = DateTime.now();
    final paper = PaperModel(title: 'x', dateAdded: now, dateModified: now);
    final result = await service.attachImportedPdf(paper);
    expect(result.localPdfPath, isNull);
  });
}
