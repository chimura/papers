import 'package:flutter_test/flutter_test.dart';
import 'package:papers/core/models/author_model.dart';
import 'package:papers/core/models/paper_model.dart';
import 'package:papers/features/citations/services/document_scan_service.dart';
import 'package:papers/features/citations/styles/apa_style.dart';
import 'package:papers/features/citations/styles/ieee_style.dart';

PaperModel _paper({
  required int id,
  required String bibtexKey,
  String title = 'A Paper',
  String? year,
  List<AuthorModel> authors = const [],
}) {
  final now = DateTime.now();
  return PaperModel(
    id: id,
    title: title,
    year: year,
    bibtexKey: bibtexKey,
    authors: authors,
    dateAdded: now,
    dateModified: now,
  );
}

void main() {
  final service = DocumentScanService();
  final apa = ApaStyle();
  final ieee = IeeeStyle();

  final vaswani = _paper(
    id: 1,
    bibtexKey: 'vaswani2017attention',
    title: 'Attention Is All You Need',
    year: '2017',
    authors: const [
      AuthorModel(givenName: 'Ashish', familyName: 'Vaswani'),
      AuthorModel(givenName: 'Noam', familyName: 'Shazeer'),
      AuthorModel(givenName: 'Niki', familyName: 'Parmar'),
    ],
  );
  final lecun = _paper(
    id: 2,
    bibtexKey: 'lecun2015deep',
    title: 'Deep Learning',
    year: '2015',
    authors: const [AuthorModel(givenName: 'Yann', familyName: 'LeCun')],
  );
  final pair = _paper(
    id: 3,
    bibtexKey: 'pair2019',
    title: 'A Two Author Work',
    year: '2019',
    authors: const [
      AuthorModel(familyName: 'Ito'),
      AuthorModel(familyName: 'Bello'),
    ],
  );
  final library = [vaswani, lecun, pair];

  test('replaces both placeholder syntaxes', () {
    final result = service.scan(
      content: 'Transformers [@vaswani2017attention] and nets {@lecun2015deep}.',
      library: library,
      style: apa,
    );

    expect(result.replacedCount, 2);
    expect(result.unresolved, isEmpty);
    expect(
      result.output.split('\n\nReferences').first,
      'Transformers (Vaswani et al., 2017) and nets (LeCun, 2015).',
    );
  });

  test('key matching is case-insensitive', () {
    final result = service.scan(
      content: 'See [@LeCun2015Deep].',
      library: library,
      style: apa,
    );
    expect(result.replacedCount, 1);
    expect(result.output, startsWith('See (LeCun, 2015).'));
  });

  test('in-text form varies with author count', () {
    final result = service.scan(
      content: '[@lecun2015deep] [@pair2019] [@vaswani2017attention]',
      library: library,
      style: apa,
    );
    final body = result.output.split('\n\nReferences').first;
    expect(body, '(LeCun, 2015) (Ito & Bello, 2019) (Vaswani et al., 2017)');
  });

  test('unknown keys are left intact and reported', () {
    final result = service.scan(
      content: 'Known [@lecun2015deep], unknown [@nosuchkey] and {@alsoMissing}.',
      library: library,
      style: apa,
    );

    expect(result.replacedCount, 1);
    expect(result.unresolved, ['nosuchkey', 'alsoMissing']);
    expect(result.output, contains('[@nosuchkey]'));
    expect(result.output, contains('{@alsoMissing}'));
  });

  test('a repeated unknown key is reported once', () {
    final result = service.scan(
      content: '[@ghost] again [@ghost] and {@GHOST}',
      library: library,
      style: apa,
    );
    expect(result.unresolved, ['ghost']);
    expect(result.replacedCount, 0);
    expect(result.output, isNot(contains('References')));
  });

  test('numeric style numbers by first appearance and reuses the number', () {
    final result = service.scan(
      content: 'First [@lecun2015deep], second [@vaswani2017attention], '
          'again [@lecun2015deep].',
      library: library,
      style: ieee,
    );

    final body = result.output.split('\n\nReferences').first;
    expect(body, 'First [1], second [2], again [1].');
    expect(result.replacedCount, 3);
  });

  test('numeric references are listed in citation order', () {
    final result = service.scan(
      content: '[@vaswani2017attention] then [@lecun2015deep]',
      library: library,
      style: ieee,
    );

    final references = result.output.split('\n\nReferences\n\n').last;
    final entries = references.split('\n\n');
    expect(entries, hasLength(2));
    expect(entries[0], startsWith('[1] '));
    expect(entries[0], contains('Attention Is All You Need'));
    expect(entries[1], startsWith('[2] '));
    expect(entries[1], contains('Deep Learning'));
  });

  test('author-date references are alphabetical regardless of citation order',
      () {
    final result = service.scan(
      content: '[@vaswani2017attention] then [@lecun2015deep]',
      library: library,
      style: apa,
    );

    expect(result.output, contains('\n\nReferences\n\n'));
    final entries = result.output.split('\n\nReferences\n\n').last.split('\n\n');
    expect(entries, hasLength(2));
    expect(entries[0], startsWith('LeCun, Y.'));
    expect(entries[1], startsWith('Vaswani, A.'));
  });

  test('only cited papers reach the references section', () {
    final result = service.scan(
      content: 'Only one citation [@lecun2015deep].',
      library: library,
      style: apa,
    );
    final references = result.output.split('\n\nReferences\n\n').last;
    expect(references, contains('Deep Learning'));
    expect(references, isNot(contains('Attention Is All You Need')));
  });

  test('a document with no placeholders is returned unchanged', () {
    const content = 'Plain prose with an [ordinary](link) and {braces}.';
    final result = service.scan(
      content: content,
      library: library,
      style: apa,
    );
    expect(result.output, content);
    expect(result.replacedCount, 0);
    expect(result.unresolved, isEmpty);
  });

  test('papers with no year cite as n.d.', () {
    final undated = _paper(
      id: 9,
      bibtexKey: 'undated',
      title: 'No Year Here',
      authors: const [AuthorModel(familyName: 'Nemo')],
    );
    final result = service.scan(
      content: '[@undated]',
      library: [undated],
      style: apa,
    );
    expect(result.output, startsWith('(Nemo, n.d.)'));
  });

  test('extensionAwareOutputPath inserts -formatted before the extension', () {
    expect(
      service.extensionAwareOutputPath(r'C:\docs\thesis.md'),
      r'C:\docs\thesis-formatted.md',
    );
    expect(
      service.extensionAwareOutputPath('/home/me/paper.txt'),
      '/home/me/paper-formatted.txt',
    );
    expect(
      service.extensionAwareOutputPath('notes.rtf'),
      'notes-formatted.rtf',
    );
    expect(
      service.extensionAwareOutputPath('chapter.one.md'),
      'chapter.one-formatted.md',
    );
    expect(
      service.extensionAwareOutputPath('README'),
      'README-formatted',
    );
  });
}
