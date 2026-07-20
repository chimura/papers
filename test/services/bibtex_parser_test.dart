import 'package:flutter_test/flutter_test.dart';
import 'package:papers/features/import/services/bibtex_parser_service.dart';

void main() {
  final parser = BibtexParserService();

  test('parses a complete article entry', () {
    const bibtex = '''
@article{vaswani2017attention,
  title = {Attention Is All You Need},
  author = {Vaswani, Ashish and Shazeer, Noam},
  journal = {NeurIPS},
  year = {2017},
  volume = {30},
  pages = {5998--6008},
  doi = {10.48550/arXiv.1706.03762}
}
''';

    final papers = parser.parse(bibtex);
    expect(papers, hasLength(1));

    final paper = papers.first;
    expect(paper.title, 'Attention Is All You Need');
    expect(paper.bibtexKey, 'vaswani2017attention');
    expect(paper.year, '2017');
    expect(paper.journal, 'NeurIPS');
    expect(paper.doi, '10.48550/arXiv.1706.03762');
    expect(paper.authors, hasLength(2));
    expect(paper.authors[0].familyName, 'Vaswani');
    expect(paper.authors[0].givenName, 'Ashish');
    expect(paper.authors[1].familyName, 'Shazeer');
  });

  test('parses multiple entries', () {
    const bibtex = '''
@article{a1, title = {First Paper}, year = {2020}}
@book{b1, title = {Second Book}, year = {2021}}
''';

    final papers = parser.parse(bibtex);
    expect(papers, hasLength(2));
    expect(papers[0].title, 'First Paper');
    expect(papers[1].title, 'Second Book');
  });

  test('handles "First Last" author format and quoted values', () {
    const bibtex = '''
@article{k, title = "Quoted Title", author = {Marie Skłodowska Curie}, year = 1911}
''';

    final papers = parser.parse(bibtex);
    expect(papers, hasLength(1));
    expect(papers.first.title, 'Quoted Title');
    expect(papers.first.year, '1911');
    expect(papers.first.authors.single.familyName, 'Curie');
    expect(papers.first.authors.single.givenName, 'Marie Skłodowska');
  });

  test('handles nested braces in values', () {
    const bibtex = '''
@article{n, title = {The {BERT} Model}, year = {2019}}
''';

    final papers = parser.parse(bibtex);
    expect(papers.single.title, 'The BERT Model');
  });

  test('returns empty list for garbage input', () {
    expect(parser.parse('not bibtex at all'), isEmpty);
  });

  test('captures a linked PDF path from the file field', () {
    const bibtex = '''
@article{k,
  title = {Has a PDF},
  file = {Full Text PDF:/home/me/storage/AB/paper.pdf:application/pdf}
}
''';
    final paper = parser.parse(bibtex).single;
    expect(paper.importedFilePath, '/home/me/storage/AB/paper.pdf');
  });

  test('entry without a file field has no PDF hint', () {
    final paper = parser.parse('@article{k, title = {No PDF}}').single;
    expect(paper.importedFilePath, isNull);
  });
}
