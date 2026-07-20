import 'package:flutter_test/flutter_test.dart';
import 'package:papers/core/models/author_model.dart';
import 'package:papers/core/models/paper_model.dart';
import 'package:papers/features/citations/services/citekey_service.dart';

PaperModel buildPaper({
  String title = '',
  String? year,
  List<AuthorModel> authors = const [],
}) {
  final now = DateTime(2026, 1, 1);
  return PaperModel(
    title: title,
    year: year,
    authors: authors,
    dateAdded: now,
    dateModified: now,
  );
}

void main() {
  final service = CitekeyService();

  final vaswani = buildPaper(
    title: 'Attention Is All You Need',
    year: '2017',
    authors: const [
      AuthorModel(givenName: 'Ashish', familyName: 'Vaswani'),
      AuthorModel(givenName: 'Noam', familyName: 'Shazeer'),
    ],
  );

  group('generateKey', () {
    test('default pattern with a normal paper', () {
      // Title words: attention, is (stopword), all, you, need.
      // First 3 non-stopwords: attention, all, you.
      expect(service.generateKey(vaswani), 'vaswani2017attentionallyou');
    });

    test('folds diacritics in the author family name', () {
      final paper = buildPaper(
        authors: const [
          AuthorModel(givenName: 'Marie', familyName: 'Skłodowska-Curie'),
        ],
      );
      expect(
        service.generateKey(paper, pattern: '[auth]'),
        'sklodowskacurie',
      );
    });

    test('folds diacritics in title words', () {
      final paper = buildPaper(title: 'Über Naïve Façades');
      expect(
        service.generateKey(paper, pattern: '[shorttitle]'),
        'ubernaivefacades',
      );
    });

    test('uses unknown when there are no authors', () {
      final paper = buildPaper(title: 'Some Title', year: '2020');
      expect(service.generateKey(paper, pattern: '[auth]'), 'unknown');
    });

    test('uses nd when year is null', () {
      final paper = buildPaper(
        title: 'Some Title',
        authors: const [AuthorModel(familyName: 'Doe')],
      );
      expect(service.generateKey(paper, pattern: '[auth][year]'), 'doend');
    });

    test('[Auth] capitalizes the first letter', () {
      expect(
        service.generateKey(vaswani, pattern: '[Auth][year]'),
        'Vaswani2017',
      );
    });

    test('[veryshorttitle] takes only the first non-stopword word', () {
      expect(
        service.generateKey(vaswani, pattern: '[auth][veryshorttitle]'),
        'vaswaniattention',
      );
    });

    test('drops unknown bracketed tokens', () {
      expect(
        service.generateKey(vaswani, pattern: '[auth][journal][year]'),
        'vaswani2017',
      );
    });

    test('falls back to paper when the result is empty', () {
      final empty = buildPaper(title: 'The Of And');
      expect(service.generateKey(empty, pattern: '[bogus]'), 'paper');
      expect(service.generateKey(empty, pattern: '[shorttitle]'), 'paper');
    });
  });

  group('ensureUnique', () {
    test('returns the base when it is free', () {
      expect(service.ensureUnique('doe2020', {'smith2019'}), 'doe2020');
    });

    test('appends a on the first collision', () {
      expect(service.ensureUnique('doe2020', {'doe2020'}), 'doe2020a');
    });

    test('skips taken letter suffixes', () {
      expect(
        service.ensureUnique('doe2020', {'doe2020', 'doe2020a', 'doe2020b'}),
        'doe2020c',
      );
    });

    test('falls back to numeric suffixes after z', () {
      final existing = <String>{'doe2020'};
      for (var code = 'a'.codeUnitAt(0); code <= 'z'.codeUnitAt(0); code++) {
        existing.add('doe2020${String.fromCharCode(code)}');
      }
      expect(service.ensureUnique('doe2020', existing), 'doe20201');

      existing.add('doe20201');
      expect(service.ensureUnique('doe2020', existing), 'doe20202');
    });
  });
}
