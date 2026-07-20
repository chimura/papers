import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:papers/core/database/app_database.dart';
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

    await appDatabase.close();
    await dir.delete(recursive: true);
  });
}
