import 'package:flutter_test/flutter_test.dart';
import 'package:papers/core/models/author_model.dart';
import 'package:papers/core/models/paper_model.dart';
import 'package:papers/features/citations/services/bibliography_builder.dart';
import 'package:papers/features/citations/styles/apa_style.dart';
import 'package:papers/features/citations/styles/ieee_style.dart';

PaperModel _paper({
  int? id,
  String title = 'A Paper',
  String? doi,
  String? year,
  String? bibtexKey,
  List<AuthorModel> authors = const [],
}) {
  final now = DateTime.now();
  return PaperModel(
    id: id,
    title: title,
    doi: doi,
    year: year,
    bibtexKey: bibtexKey,
    authors: authors,
    dateAdded: now,
    dateModified: now,
  );
}

void main() {
  final builder = BibliographyBuilder();
  final apa = ApaStyle();
  final ieee = IeeeStyle();

  test('empty input produces an empty bibliography', () {
    expect(builder.build([], apa), '');
    expect(builder.build([], ieee), '');
    expect(builder.buildBibtex([]), '');
  });

  test('author-date styles sort alphabetically by first author, then year', () {
    final entries = builder.build([
      _paper(
        id: 1,
        title: 'Zebras',
        year: '2020',
        authors: const [AuthorModel(givenName: 'Nia', familyName: 'Young')],
      ),
      _paper(
        id: 2,
        title: 'Later Adams',
        year: '2021',
        authors: const [AuthorModel(givenName: 'Ann', familyName: 'Adams')],
      ),
      _paper(
        id: 3,
        title: 'Earlier Adams',
        year: '1999',
        authors: const [AuthorModel(givenName: 'Ann', familyName: 'Adams')],
      ),
      _paper(
        id: 4,
        title: 'Middle',
        year: '2005',
        authors: const [AuthorModel(givenName: 'Bo', familyName: 'Mbeki')],
      ),
    ], apa).split('\n\n');

    expect(entries, hasLength(4));
    expect(entries[0], contains('Earlier Adams'));
    expect(entries[1], contains('Later Adams'));
    expect(entries[2], contains('Middle'));
    expect(entries[3], contains('Zebras'));
    expect(entries.first, startsWith('Adams, A. (1999)'));
  });

  test('numeric styles keep input order and number the entries', () {
    final entries = builder.build([
      _paper(
        id: 1,
        title: 'Cited First',
        year: '2020',
        authors: const [AuthorModel(givenName: 'Nia', familyName: 'Young')],
      ),
      _paper(
        id: 2,
        title: 'Cited Second',
        year: '1999',
        authors: const [AuthorModel(givenName: 'Ann', familyName: 'Adams')],
      ),
    ], ieee).split('\n\n');

    expect(entries, hasLength(2));
    expect(entries[0], startsWith('[1] '));
    expect(entries[0], contains('Cited First'));
    expect(entries[1], startsWith('[2] '));
    expect(entries[1], contains('Cited Second'));
  });

  group('dedupe', () {
    test('collapses repeats by id', () {
      final paper = _paper(id: 7, title: 'Only Once', year: '2020');
      final entries = builder.build([paper, paper, paper], apa).split('\n\n');
      expect(entries, hasLength(1));
    });

    test('collapses idless papers sharing a DOI, ignoring case', () {
      final entries = builder.build([
        _paper(title: 'Preprint version', doi: '10.1000/XYZ', year: '2020'),
        _paper(title: 'Published version', doi: '10.1000/xyz', year: '2021'),
      ], apa).split('\n\n');

      expect(entries, hasLength(1));
      expect(entries.single, contains('Preprint version'),
          reason: 'the first occurrence wins');
    });

    test('collapses idless, doiless papers with the same normalized title', () {
      final entries = builder.build([
        _paper(title: 'Deep Learning: A Review', year: '2020'),
        _paper(title: 'deep learning a review', year: '2020'),
        _paper(title: 'Something Else', year: '2020'),
      ], apa).split('\n\n');
      expect(entries, hasLength(2));
    });

    test('distinct papers are all kept', () {
      final entries = builder.build([
        _paper(id: 1, title: 'One', year: '2001'),
        _paper(id: 2, title: 'Two', year: '2002'),
        _paper(id: 3, title: 'Three', year: '2003'),
      ], apa).split('\n\n');
      expect(entries, hasLength(3));
    });
  });

  test('buildBibtex dedupes and emits one entry per paper', () {
    final duplicated = _paper(id: 1, title: 'One', bibtexKey: 'one2020');
    final bibtex = builder.buildBibtex([
      duplicated,
      duplicated,
      _paper(id: 2, title: 'Two', bibtexKey: 'two2021'),
    ]);

    expect('@article{'.allMatches(bibtex).length, 2);
    expect(bibtex, contains('@article{one2020,'));
    expect(bibtex, contains('@article{two2021,'));
  });

  test('authorless entries file under their title', () {
    final entries = builder.build([
      _paper(
        id: 1,
        title: 'Zzz Authored',
        year: '2020',
        authors: const [AuthorModel(familyName: 'Zulu')],
      ),
      _paper(id: 2, title: 'Anonymous Report', year: '2020'),
    ], apa).split('\n\n');

    expect(entries.first, contains('Anonymous Report'));
  });
}
