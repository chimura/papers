import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:papers/features/import/services/bibtex_parser_service.dart';
import 'package:papers/features/import/services/file_import_service.dart';
import 'package:path/path.dart' as p;

/// The whole Mendeley/Zotero migration path in one test: parse a real .bib
/// with a `file` field, then attach the PDF it points at.
void main() {
  test('a .bib entry with a file field brings its PDF across', () async {
    final export = await Directory.systemTemp.createTemp('papers_export');
    final library = await Directory.systemTemp.createTemp('papers_lib');
    addTearDown(() async {
      for (final d in [export, library]) {
        if (d.existsSync()) await d.delete(recursive: true);
      }
    });

    // A real PDF sitting next to the .bib, referenced by a relative path.
    final pdfDir = Directory(p.join(export.path, 'files'))..createSync();
    final pdf = File(p.join(pdfDir.path, 'vaswani2017.pdf'));
    await pdf.writeAsString('%PDF-1.7 attention is all you need');

    final bib = '''
@article{vaswani2017,
  title = {Attention Is All You Need},
  author = {Vaswani, Ashish and Shazeer, Noam},
  year = {2017},
  file = {Full Text PDF:files/vaswani2017.pdf:application/pdf}
}
''';

    final parsed = BibtexParserService().parse(bib).single;
    expect(parsed.title, 'Attention Is All You Need');
    expect(parsed.importedFilePath, 'files/vaswani2017.pdf');

    final service = FileImportService(pdfsDirectory: () async => library);
    final withPdf =
        await service.attachImportedPdf(parsed, baseDir: export.path);

    expect(withPdf.localPdfPath, isNotNull,
        reason: 'the linked PDF should have been attached');
    final copied = File(withPdf.localPdfPath!);
    expect(copied.existsSync(), isTrue);
    expect(await copied.readAsString(), '%PDF-1.7 attention is all you need');
  });
}
