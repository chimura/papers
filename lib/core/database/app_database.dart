import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart';
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';

class AppDatabase {
  static const _databaseName = 'papers.db';
  static const _legacyDatabaseName = 'sci.db';
  static const _databaseVersion = 3;

  /// Sequential migrations: entry N upgrades a version N-1 database to N.
  /// [_onCreate] must always produce the latest schema directly, so new
  /// installs never run these.
  static final Map<int, Future<void> Function(Database)> _migrations = {
    2: (db) async {
      await db.execute('ALTER TABLE papers ADD COLUMN last_read_page INTEGER');
      await db.execute('ALTER TABLE papers ADD COLUMN last_read_zoom REAL');
      await db.execute('ALTER TABLE papers ADD COLUMN last_read_at TEXT');
      await db.execute('ALTER TABLE papers ADD COLUMN total_pages INTEGER');
      await db.execute(
          'ALTER TABLE papers ADD COLUMN bibtex_key_pinned INTEGER NOT NULL DEFAULT 0');
    },
    3: (db) async {
      for (final statement in _v3PaperColumns) {
        await db.execute(statement);
      }
      await db.execute(_createNotesTable);
      for (final statement in _createNotesFts) {
        await db.execute(statement);
      }
      await db.execute(_createSmartCollectionsTable);
      await db.execute(_createAutoExportsTable);
      await db.execute(_createTitleNormalizedIndex);
      // Backfill the normalized title used by enrichment/dedupe matching.
      final rows = await db.query('papers', columns: ['id', 'title']);
      for (final row in rows) {
        await db.update(
          'papers',
          {'title_normalized': normalizeTitle(row['title'] as String)},
          where: 'id = ?',
          whereArgs: [row['id']],
        );
      }
    },
  };

  /// Lowercased, punctuation-stripped title used for fuzzy matching.
  static String normalizeTitle(String title) {
    return title
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9\s]'), '')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

  static const _v3PaperColumns = [
    'ALTER TABLE papers ADD COLUMN arxiv_id TEXT',
    'ALTER TABLE papers ADD COLUMN pmid TEXT',
    "ALTER TABLE papers ADD COLUMN read_status TEXT NOT NULL DEFAULT 'unread'",
    'ALTER TABLE papers ADD COLUMN date_read TEXT',
    'ALTER TABLE papers ADD COLUMN queue_position INTEGER',
    'ALTER TABLE papers ADD COLUMN needs_review INTEGER NOT NULL DEFAULT 0',
    'ALTER TABLE papers ADD COLUMN title_normalized TEXT',
    'ALTER TABLE papers ADD COLUMN update_status TEXT',
    'ALTER TABLE papers ADD COLUMN update_notice_doi TEXT',
    'ALTER TABLE papers ADD COLUMN published_version_doi TEXT',
    'ALTER TABLE papers ADD COLUMN updates_checked_at TEXT',
  ];

  static const _createTitleNormalizedIndex =
      'CREATE INDEX IF NOT EXISTS idx_papers_title_norm ON papers(title_normalized)';

  /// paper_id NULL marks a cross-paper topic page.
  static const _createNotesTable = '''
    CREATE TABLE notes (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      paper_id INTEGER,
      title TEXT,
      body_md TEXT NOT NULL DEFAULT '',
      created_at TEXT NOT NULL,
      updated_at TEXT NOT NULL,
      FOREIGN KEY (paper_id) REFERENCES papers(id) ON DELETE CASCADE
    )
  ''';

  static const _createNotesFts = [
    '''
    CREATE VIRTUAL TABLE notes_fts USING fts5(
      title,
      body_md,
      content=notes,
      content_rowid=id
    )
    ''',
    '''
    CREATE TRIGGER notes_ai AFTER INSERT ON notes BEGIN
      INSERT INTO notes_fts(rowid, title, body_md)
      VALUES (new.id, new.title, new.body_md);
    END
    ''',
    '''
    CREATE TRIGGER notes_ad AFTER DELETE ON notes BEGIN
      INSERT INTO notes_fts(notes_fts, rowid, title, body_md)
      VALUES ('delete', old.id, old.title, old.body_md);
    END
    ''',
    '''
    CREATE TRIGGER notes_au AFTER UPDATE ON notes BEGIN
      INSERT INTO notes_fts(notes_fts, rowid, title, body_md)
      VALUES ('delete', old.id, old.title, old.body_md);
      INSERT INTO notes_fts(rowid, title, body_md)
      VALUES (new.id, new.title, new.body_md);
    END
    ''',
  ];

  static const _createSmartCollectionsTable = '''
    CREATE TABLE smart_collections (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      name TEXT NOT NULL,
      filter_json TEXT NOT NULL,
      created_at TEXT NOT NULL
    )
  ''';

  static const _createAutoExportsTable = '''
    CREATE TABLE auto_exports (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      target_path TEXT NOT NULL,
      scope TEXT NOT NULL DEFAULT 'library',
      collection_id INTEGER,
      last_exported TEXT,
      FOREIGN KEY (collection_id) REFERENCES collections(id) ON DELETE CASCADE
    )
  ''';

  AppDatabase._() : _overridePath = null;

  /// Opens the database at [path] (e.g. `inMemoryDatabasePath`) instead of
  /// the application documents directory.
  @visibleForTesting
  AppDatabase.forPath(String path) : _overridePath = path;

  static final AppDatabase instance = AppDatabase._();

  final String? _overridePath;
  Database? _database;

  Future<Database> get database async {
    _database ??= await _initDatabase();
    return _database!;
  }

  @visibleForTesting
  Future<void> close() async {
    await _database?.close();
    _database = null;
  }

  Future<Database> _initDatabase() async {
    String? path = _overridePath;
    if (path == null) {
      final documentsPath = (await getApplicationDocumentsDirectory()).path;
      path = join(documentsPath, _databaseName);

      // The app used to be called "sci" — carry over its database.
      final legacy = File(join(documentsPath, _legacyDatabaseName));
      if (!File(path).existsSync() && legacy.existsSync()) {
        legacy.renameSync(path);
      }
    }
    return openDatabase(
      path,
      version: _databaseVersion,
      onCreate: _onCreate,
      onUpgrade: _onUpgrade,
      onConfigure: (db) async {
        await db.execute('PRAGMA foreign_keys = ON');
      },
    );
  }

  Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    for (var v = oldVersion + 1; v <= newVersion; v++) {
      final migration = _migrations[v];
      if (migration != null) await migration(db);
    }
  }

  Future<void> _onCreate(Database db, int version) async {
    await db.execute('''
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
        bibtex_key TEXT,
        bibtex_key_pinned INTEGER NOT NULL DEFAULT 0,
        last_read_page INTEGER,
        last_read_zoom REAL,
        last_read_at TEXT,
        total_pages INTEGER,
        arxiv_id TEXT,
        pmid TEXT,
        read_status TEXT NOT NULL DEFAULT 'unread',
        date_read TEXT,
        queue_position INTEGER,
        needs_review INTEGER NOT NULL DEFAULT 0,
        title_normalized TEXT,
        update_status TEXT,
        update_notice_doi TEXT,
        published_version_doi TEXT,
        updates_checked_at TEXT
      )
    ''');
    await db.execute(_createTitleNormalizedIndex);

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
        PRIMARY KEY (paper_id, author_id),
        FOREIGN KEY (paper_id) REFERENCES papers(id) ON DELETE CASCADE,
        FOREIGN KEY (author_id) REFERENCES authors(id) ON DELETE CASCADE
      )
    ''');

    await db.execute('''
      CREATE TABLE collections (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL,
        color TEXT,
        parent_id INTEGER,
        created_at TEXT NOT NULL,
        FOREIGN KEY (parent_id) REFERENCES collections(id) ON DELETE SET NULL
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
        PRIMARY KEY (paper_id, tag_id),
        FOREIGN KEY (paper_id) REFERENCES papers(id) ON DELETE CASCADE,
        FOREIGN KEY (tag_id) REFERENCES tags(id) ON DELETE CASCADE
      )
    ''');

    await db.execute('''
      CREATE TABLE paper_collections (
        paper_id INTEGER NOT NULL,
        collection_id INTEGER NOT NULL,
        PRIMARY KEY (paper_id, collection_id),
        FOREIGN KEY (paper_id) REFERENCES papers(id) ON DELETE CASCADE,
        FOREIGN KEY (collection_id) REFERENCES collections(id) ON DELETE CASCADE
      )
    ''');

    await db.execute('''
      CREATE TABLE annotations (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        paper_id INTEGER NOT NULL,
        page INTEGER NOT NULL,
        x REAL NOT NULL,
        y REAL NOT NULL,
        width REAL,
        height REAL,
        content TEXT NOT NULL,
        type TEXT NOT NULL,
        color TEXT NOT NULL DEFAULT '#FFFF00',
        selected_text TEXT,
        created_at TEXT NOT NULL,
        FOREIGN KEY (paper_id) REFERENCES papers(id) ON DELETE CASCADE
      )
    ''');

    // Full-text search index
    await db.execute('''
      CREATE VIRTUAL TABLE papers_fts USING fts5(
        title,
        abstract,
        content=papers,
        content_rowid=id
      )
    ''');

    // Triggers to keep FTS in sync
    await db.execute('''
      CREATE TRIGGER papers_ai AFTER INSERT ON papers BEGIN
        INSERT INTO papers_fts(rowid, title, abstract)
        VALUES (new.id, new.title, new.abstract);
      END
    ''');

    await db.execute('''
      CREATE TRIGGER papers_ad AFTER DELETE ON papers BEGIN
        INSERT INTO papers_fts(papers_fts, rowid, title, abstract)
        VALUES ('delete', old.id, old.title, old.abstract);
      END
    ''');

    await db.execute('''
      CREATE TRIGGER papers_au AFTER UPDATE ON papers BEGIN
        INSERT INTO papers_fts(papers_fts, rowid, title, abstract)
        VALUES ('delete', old.id, old.title, old.abstract);
        INSERT INTO papers_fts(rowid, title, abstract)
        VALUES (new.id, new.title, new.abstract);
      END
    ''');

    await db.execute(_createNotesTable);
    for (final statement in _createNotesFts) {
      await db.execute(statement);
    }
    await db.execute(_createSmartCollectionsTable);
    await db.execute(_createAutoExportsTable);
  }
}
