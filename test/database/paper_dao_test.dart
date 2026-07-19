import 'package:flutter_test/flutter_test.dart';
import 'package:sci/core/database/app_database.dart';
import 'package:sci/core/database/daos/collection_dao.dart';
import 'package:sci/core/database/daos/paper_dao.dart';
import 'package:sci/core/models/author_model.dart';
import 'package:sci/core/models/paper_model.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

PaperModel _paper({
  String title = 'A Paper',
  String? doi,
  List<AuthorModel> authors = const [],
  List<String> tags = const [],
}) {
  final now = DateTime.now();
  return PaperModel(
    title: title,
    doi: doi,
    authors: authors,
    tags: tags,
    dateAdded: now,
    dateModified: now,
  );
}

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  late AppDatabase appDatabase;
  late PaperDao dao;

  setUp(() {
    appDatabase = AppDatabase.forPath(inMemoryDatabasePath);
    dao = PaperDao(appDatabase: appDatabase);
  });

  tearDown(() async {
    await appDatabase.close();
  });

  test('insert and read back a paper with authors and tags', () async {
    final id = await dao.insertPaper(_paper(
      title: 'Attention Is All You Need',
      doi: '10.48550/arXiv.1706.03762',
      authors: const [
        AuthorModel(givenName: 'Ashish', familyName: 'Vaswani'),
        AuthorModel(givenName: 'Noam', familyName: 'Shazeer'),
      ],
      tags: const ['ml', 'transformers'],
    ));

    final paper = await dao.getPaperById(id);
    expect(paper, isNotNull);
    expect(paper!.title, 'Attention Is All You Need');
    expect(paper.authors.map((a) => a.familyName), ['Vaswani', 'Shazeer']);
    expect(paper.tags.toSet(), {'ml', 'transformers'});
  });

  test('getPaperByDoi finds the paper', () async {
    await dao.insertPaper(_paper(title: 'X', doi: '10.1000/xyz'));
    final found = await dao.getPaperByDoi('10.1000/xyz');
    expect(found?.title, 'X');
    expect(await dao.getPaperByDoi('10.1000/other'), isNull);
  });

  test('update and delete', () async {
    final id = await dao.insertPaper(_paper(title: 'Old title'));
    final paper = (await dao.getPaperById(id))!;

    await dao.updatePaper(paper.copyWith(title: 'New title'));
    expect((await dao.getPaperById(id))!.title, 'New title');

    await dao.deletePaper(id);
    expect(await dao.getPaperById(id), isNull);
  });

  test('toggleFavorite persists', () async {
    final id = await dao.insertPaper(_paper());
    await dao.toggleFavorite(id, true);
    expect((await dao.getPaperById(id))!.isFavorite, isTrue);
  });

  test('authors without a given name dedupe instead of duplicating', () async {
    await dao.insertPaper(_paper(
      title: 'One',
      authors: const [AuthorModel(familyName: 'Solo')],
    ));
    await dao.insertPaper(_paper(
      title: 'Two',
      authors: const [AuthorModel(familyName: 'Solo')],
    ));

    final db = await appDatabase.database;
    final rows = await db.query('authors', where: "family_name = 'Solo'");
    expect(rows, hasLength(1));
  });

  test('updatePaperWithRelations rewrites authors and tags', () async {
    final id = await dao.insertPaper(_paper(
      title: 'Original',
      authors: const [AuthorModel(givenName: 'Old', familyName: 'Author')],
      tags: const ['old-tag'],
    ));

    final paper = (await dao.getPaperById(id))!;
    await dao.updatePaperWithRelations(paper.copyWith(
      title: 'Edited',
      authors: const [
        AuthorModel(givenName: 'New', familyName: 'Person'),
        AuthorModel(familyName: 'Second'),
      ],
      tags: const ['fresh', 'better'],
    ));

    final updated = (await dao.getPaperById(id))!;
    expect(updated.title, 'Edited');
    expect(updated.authors.map((a) => a.familyName), ['Person', 'Second']);
    expect(updated.tags.toSet(), {'fresh', 'better'});
  });

  test('collection membership add/remove/query', () async {
    final collectionDao = CollectionDao(appDatabase: appDatabase);
    final paperId = await dao.insertPaper(_paper(title: 'In collection'));
    final otherId = await dao.insertPaper(_paper(title: 'Not in collection'));

    final collectionId = await collectionDao.insert(CollectionRecord(
      name: 'Thesis',
      createdAt: DateTime.now(),
    ));

    await collectionDao.addPaperToCollection(paperId, collectionId);
    expect(
      await collectionDao.getPaperIdsInCollection(collectionId),
      [paperId],
    );
    expect(
      await collectionDao.getCollectionIdsForPaper(paperId),
      {collectionId},
    );
    expect(await collectionDao.getCollectionIdsForPaper(otherId), isEmpty);

    await collectionDao.removePaperFromCollection(paperId, collectionId);
    expect(
      await collectionDao.getPaperIdsInCollection(collectionId),
      isEmpty,
    );

    // Deleting a collection cascades its membership rows.
    await collectionDao.addPaperToCollection(paperId, collectionId);
    await collectionDao.delete(collectionId);
    expect(await collectionDao.getCollectionIdsForPaper(paperId), isEmpty);
  });

  group('full-text search', () {
    test('matches title words and last-term prefix', () async {
      await dao.insertPaper(_paper(title: 'Quantum Error Correction'));
      await dao.insertPaper(_paper(title: 'Deep Learning Basics'));

      expect((await dao.searchPapers('quantum')).length, 1);
      expect((await dao.searchPapers('quantum corr')).length, 1);
      expect((await dao.searchPapers('learning')).length, 1);
      expect((await dao.searchPapers('nonexistent')).length, 0);
    });

    test('search index follows updates', () async {
      final id = await dao.insertPaper(_paper(title: 'Original topic'));
      final paper = (await dao.getPaperById(id))!;
      await dao.updatePaper(paper.copyWith(title: 'Revised subject'));

      expect(await dao.searchPapers('original'), isEmpty);
      expect((await dao.searchPapers('revised')).length, 1);
    });

    test('special characters do not break the query', () async {
      await dao.insertPaper(_paper(title: 'Annual Review: don\'t panic'));

      for (final query in [
        'review:',
        'foo"bar',
        '-negated',
        'AND OR NOT',
        '(parens)',
        '"unbalanced',
      ]) {
        await expectLater(dao.searchPapers(query), completes);
      }

      expect(await dao.searchPapers('   '), isEmpty);
      expect((await dao.searchPapers('annual review')).length, 1);
    });
  });
}
