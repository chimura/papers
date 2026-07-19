import 'package:flutter/foundation.dart';
import 'package:path/path.dart';
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';

class AppDatabase {
  static const _databaseName = 'sci.db';
  static const _databaseVersion = 1;

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
    final path = _overridePath ??
        join((await getApplicationDocumentsDirectory()).path, _databaseName);
    return openDatabase(
      path,
      version: _databaseVersion,
      onCreate: _onCreate,
      onConfigure: (db) async {
        await db.execute('PRAGMA foreign_keys = ON');
      },
    );
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
        bibtex_key TEXT
      )
    ''');

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
  }
}
