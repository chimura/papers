import 'package:flutter_test/flutter_test.dart';
import 'package:papers/core/database/app_database.dart';
import 'package:papers/core/database/daos/note_dao.dart';
import 'package:papers/core/database/daos/paper_dao.dart';
import 'package:papers/core/models/paper_model.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

PaperModel _paper({String title = 'A Paper'}) {
  final now = DateTime.now();
  return PaperModel(title: title, dateAdded: now, dateModified: now);
}

NoteRecord _note({
  int? paperId,
  String? title,
  String bodyMd = '',
  DateTime? at,
}) {
  final now = at ?? DateTime.now();
  return NoteRecord(
    paperId: paperId,
    title: title,
    bodyMd: bodyMd,
    createdAt: now,
    updatedAt: now,
  );
}

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  late AppDatabase appDatabase;
  late NoteDao dao;
  late PaperDao paperDao;

  setUp(() {
    appDatabase = AppDatabase.forPath(inMemoryDatabasePath);
    dao = NoteDao(appDatabase: appDatabase);
    paperDao = PaperDao(appDatabase: appDatabase);
  });

  tearDown(() async {
    await appDatabase.close();
  });

  test('insert and read back a note', () async {
    final paperId = await paperDao.insertPaper(_paper());
    final id = await dao.insert(_note(
      paperId: paperId,
      title: 'Reading notes',
      bodyMd: 'The method section is weak.',
    ));

    final note = await dao.getById(id);
    expect(note, isNotNull);
    expect(note!.paperId, paperId);
    expect(note.title, 'Reading notes');
    expect(note.bodyMd, 'The method section is weak.');
  });

  test('update rewrites the body and bumps updated_at', () async {
    final paperId = await paperDao.insertPaper(_paper());
    final id = await dao.insert(_note(
      paperId: paperId,
      bodyMd: 'First draft',
      at: DateTime.now().subtract(const Duration(days: 1)),
    ));
    final before = (await dao.getById(id))!;

    await dao.update(before.copyWith(bodyMd: 'Second draft'));

    final after = (await dao.getById(id))!;
    expect(after.bodyMd, 'Second draft');
    expect(after.updatedAt.isAfter(before.updatedAt), isTrue);
    expect(after.createdAt, before.createdAt);
  });

  test('delete removes the note', () async {
    final id = await dao.insert(_note(bodyMd: 'Disposable'));
    await dao.delete(id);
    expect(await dao.getById(id), isNull);
  });

  test('paper notes and topic pages are kept apart', () async {
    final paperId = await paperDao.insertPaper(_paper(title: 'Host'));
    final otherId = await paperDao.insertPaper(_paper(title: 'Other'));

    await dao.insert(_note(paperId: paperId, bodyMd: 'On the host paper'));
    await dao.insert(_note(paperId: otherId, bodyMd: 'On the other paper'));
    await dao.insert(_note(title: 'Attention mechanisms', bodyMd: 'Cross-paper'));

    final forPaper = await dao.getForPaper(paperId);
    expect(forPaper, hasLength(1));
    expect(forPaper.single.bodyMd, 'On the host paper');

    final topics = await dao.getTopicPages();
    expect(topics, hasLength(1));
    expect(topics.single.title, 'Attention mechanisms');
    expect(topics.single.paperId, isNull);
  });

  test('getForPaper and getTopicPages order by most recently updated',
      () async {
    final paperId = await paperDao.insertPaper(_paper());
    final base = DateTime.now().subtract(const Duration(days: 3));

    await dao.insert(_note(paperId: paperId, bodyMd: 'oldest', at: base));
    await dao.insert(_note(
      paperId: paperId,
      bodyMd: 'newest',
      at: base.add(const Duration(days: 2)),
    ));
    await dao.insert(_note(
      paperId: paperId,
      bodyMd: 'middle',
      at: base.add(const Duration(days: 1)),
    ));

    expect(
      (await dao.getForPaper(paperId)).map((n) => n.bodyMd),
      ['newest', 'middle', 'oldest'],
    );

    await dao.insert(_note(title: 'A', bodyMd: 'topic old', at: base));
    await dao.insert(_note(
      title: 'B',
      bodyMd: 'topic new',
      at: base.add(const Duration(days: 5)),
    ));
    expect(
      (await dao.getTopicPages()).map((n) => n.title),
      ['B', 'A'],
    );
  });

  test('deleting a paper cascades to its notes but spares topic pages',
      () async {
    final paperId = await paperDao.insertPaper(_paper());
    final noteId =
        await dao.insert(_note(paperId: paperId, bodyMd: 'Attached'));
    final topicId = await dao.insert(_note(bodyMd: 'Standalone'));

    await paperDao.deletePaper(paperId);

    expect(await dao.getById(noteId), isNull);
    expect(await dao.getById(topicId), isNotNull);
  });

  group('full-text search', () {
    test('finds a note by a word in its body and in its title', () async {
      await dao.insert(_note(
        title: 'Transformers',
        bodyMd: 'Self-attention replaces recurrence entirely.',
      ));
      await dao.insert(_note(title: 'Diffusion', bodyMd: 'Denoising steps.'));

      expect((await dao.search('recurrence')).length, 1);
      expect((await dao.search('transformers')).length, 1);
      expect((await dao.search('denois')).length, 1); // last-term prefix
      expect(await dao.search('nonexistent'), isEmpty);
    });

    test('search index follows updates and deletes', () async {
      final id = await dao.insert(_note(bodyMd: 'Original wording'));
      final note = (await dao.getById(id))!;
      await dao.update(note.copyWith(bodyMd: 'Revised wording'));

      expect(await dao.search('original'), isEmpty);
      expect((await dao.search('revised')).length, 1);

      await dao.delete(id);
      expect(await dao.search('revised'), isEmpty);
    });

    test('special characters do not break the query', () async {
      await dao.insert(_note(bodyMd: "Annual Review: don't panic"));

      for (final query in [
        'foo"bar',
        '-x',
        'review:',
        'AND OR NOT',
        '(parens)',
        '"unbalanced',
      ]) {
        await expectLater(dao.search(query), completes);
      }

      expect(await dao.search('   '), isEmpty);
      expect((await dao.search('annual review')).length, 1);
    });
  });

  group('appendQuote', () {
    test('creates the note on first capture, then appends to the same one',
        () async {
      final paperId = await paperDao.insertPaper(_paper());

      final first = await dao.appendQuote(
        paperId: paperId,
        quote: 'Attention is all you need.',
        page: 3,
      );
      final second = await dao.appendQuote(
        paperId: paperId,
        quote: 'Recurrence is unnecessary.',
        page: 7,
      );

      expect(second, first, reason: 'both quotes land on the primary note');
      expect(await dao.getForPaper(paperId), hasLength(1));

      final body = (await dao.getById(first))!.bodyMd;
      expect(
        body,
        '> Attention is all you need.\n'
        '> — [p. 3](papers://open/$paperId?page=3)\n'
        '\n'
        '> Recurrence is unnecessary.\n'
        '> — [p. 7](papers://open/$paperId?page=7)',
      );
      expect('\n$body'.split('\n> ').length - 1, 4); // two 2-line blocks
    });

    test('appends to an existing hand-written note', () async {
      final paperId = await paperDao.insertPaper(_paper());
      final noteId = await dao.insert(_note(
        paperId: paperId,
        bodyMd: 'My own thoughts.',
      ));

      final target = await dao.appendQuote(
        paperId: paperId,
        quote: 'A claim worth keeping.',
        page: 12,
      );

      expect(target, noteId);
      final body = (await dao.getById(noteId))!.bodyMd;
      expect(body, startsWith('My own thoughts.\n\n> A claim worth keeping.'));
      expect(body, contains('papers://open/$paperId?page=12'));
    });

    test('appended quotes are searchable', () async {
      final paperId = await paperDao.insertPaper(_paper());
      await dao.appendQuote(
        paperId: paperId,
        quote: 'Photosynthesis in low light',
        page: 2,
      );
      expect((await dao.search('photosynthesis')).length, 1);
    });
  });
}
