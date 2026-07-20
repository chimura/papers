import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:papers/core/database/app_database.dart';
import 'package:papers/core/database/daos/note_dao.dart';
import 'package:papers/core/database/daos/paper_dao.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// The papers table exactly as version 1 shipped it.
const _v1PapersTable = '''
  CREATE TABLE papers (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    title TEXT NOT NULL,
    abstract TEXT,
    doi TEXT UNIQUE,
    year TEXT,
    journal TEXT,
    volume TEXT,
    issue TEXT,
    pages TEXT,
    publisher TEXT,
    url TEXT,
    local_pdf_path TEXT,
    drive_file_id TEXT,
    is_favorite INTEGER NOT NULL DEFAULT 0,
    date_added TEXT NOT NULL,
    date_modified TEXT NOT NULL,
    csl_json TEXT,
    bibtex_key TEXT
  )
''';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  test('a version-1 database upgrades to the current schema', () async {
    final dir = await Directory.systemTemp.createTemp('papers_migration');
    final dbPath = '${dir.path}/v1.db';

    // Build a minimal v1 database with one existing paper.
    final v1 = await databaseFactory.openDatabase(
      dbPath,
      options: OpenDatabaseOptions(
        version: 1,
        onCreate: (db, _) async {
          await db.execute(_v1PapersTable);
          await db.execute('''
            CREATE TABLE authors (
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              given_name TEXT,
              family_name TEXT NOT NULL,
              orcid TEXT
            )
          ''');
          await db.execute('''
            CREATE TABLE paper_authors (
              paper_id INTEGER NOT NULL,
              author_id INTEGER NOT NULL,
              position INTEGER NOT NULL,
              PRIMARY KEY (paper_id, author_id)
            )
          ''');
          await db.execute('''
            CREATE TABLE tags (
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              name TEXT NOT NULL UNIQUE,
              color TEXT
            )
          ''');
          await db.execute('''
            CREATE TABLE paper_tags (
              paper_id INTEGER NOT NULL,
              tag_id INTEGER NOT NULL,
              PRIMARY KEY (paper_id, tag_id)
            )
          ''');
          await db.insert('papers', {
            'title': 'Pre-migration paper',
            'doi': '10.1/legacy',
            'date_added': DateTime.now().toIso8601String(),
            'date_modified': DateTime.now().toIso8601String(),
          });
        },
      ),
    );
    await v1.close();

    // Reopen through AppDatabase — runs the v2 migration.
    final appDatabase = AppDatabase.forPath(dbPath);
    final dao = PaperDao(appDatabase: appDatabase);

    final papers = await dao.getAllPapers();
    expect(papers, hasLength(1));
    expect(papers.first.title, 'Pre-migration paper');
    expect(papers.first.lastReadPage, isNull);
    expect(papers.first.bibtexKeyPinned, isFalse);

    // The new columns are writable.
    await dao.updateReadingPosition(papers.first.id!, page: 7, totalPages: 20);
    await dao.setBibtexKey(papers.first.id!, 'legacy2020', pinned: true);

    final updated = (await dao.getPaperById(papers.first.id!))!;
    expect(updated.lastReadPage, 7);
    expect(updated.totalPages, 20);
    expect(updated.lastReadAt, isNotNull);
    expect(updated.bibtexKey, 'legacy2020');
    expect(updated.bibtexKeyPinned, isTrue);

    // v3 columns exist with sane defaults and the title was backfilled.
    expect(updated.readStatus, ReadStatus.unread);
    expect(updated.needsReview, isFalse);
    expect(updated.arxivId, isNull);
    final rows = await (await appDatabase.database)
        .query('papers', columns: ['title_normalized']);
    expect(rows.first['title_normalized'], 'premigration paper');

    // v3 tables exist and are usable.
    await dao.setReadStatus(updated.id!, ReadStatus.read);
    expect((await dao.getPaperById(updated.id!))!.readStatus, ReadStatus.read);

    final noteDao = NoteDao(appDatabase: appDatabase);
    final noteId = await noteDao.insert(NoteRecord(
      paperId: updated.id,
      title: 'After migration',
      bodyMd: 'still here',
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
    ));
    expect((await noteDao.getById(noteId))?.bodyMd, 'still here');
    expect(await noteDao.search('still'), hasLength(1));

    await appDatabase.close();
    await dir.delete(recursive: true);
  });

  test('a fresh database matches the migrated schema', () async {
    // onCreate must produce exactly what the migrations produce, or new
    // installs and upgraded ones drift apart.
    final appDatabase = AppDatabase.forPath(inMemoryDatabasePath);
    final db = await appDatabase.database;

    final columns = (await db.rawQuery('PRAGMA table_info(papers)'))
        .map((r) => r['name'] as String)
        .toSet();
    for (final expected in [
      'bibtex_key_pinned',
      'last_read_page',
      'total_pages',
      'arxiv_id',
      'pmid',
      'read_status',
      'queue_position',
      'needs_review',
      'title_normalized',
      'update_status',
      'updates_checked_at',
    ]) {
      expect(columns, contains(expected), reason: '$expected missing');
    }

    final tables = (await db.rawQuery(
            "SELECT name FROM sqlite_master WHERE type='table'"))
        .map((r) => r['name'] as String)
        .toSet();
    expect(tables, containsAll(['notes', 'smart_collections', 'auto_exports']));

    await appDatabase.close();
  });
}
