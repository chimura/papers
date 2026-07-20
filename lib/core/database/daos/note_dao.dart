import 'package:sqflite/sqflite.dart';

import '../app_database.dart';

/// A notebook page. [paperId] null marks a cross-paper topic page.
class NoteRecord {
  final int? id;
  final int? paperId;
  final String? title;
  final String bodyMd;
  final DateTime createdAt;
  final DateTime updatedAt;

  const NoteRecord({
    this.id,
    this.paperId,
    this.title,
    this.bodyMd = '',
    required this.createdAt,
    required this.updatedAt,
  });

  NoteRecord copyWith({
    int? id,
    int? paperId,
    String? title,
    String? bodyMd,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return NoteRecord(
      id: id ?? this.id,
      paperId: paperId ?? this.paperId,
      title: title ?? this.title,
      bodyMd: bodyMd ?? this.bodyMd,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  Map<String, dynamic> toMap() => {
        if (id != null) 'id': id,
        'paper_id': paperId,
        'title': title,
        'body_md': bodyMd,
        'created_at': createdAt.toIso8601String(),
        'updated_at': updatedAt.toIso8601String(),
      };

  static NoteRecord fromMap(Map<String, dynamic> map) => NoteRecord(
        id: map['id'] as int?,
        paperId: map['paper_id'] as int?,
        title: map['title'] as String?,
        bodyMd: map['body_md'] as String? ?? '',
        createdAt: DateTime.parse(map['created_at'] as String),
        updatedAt: DateTime.parse(map['updated_at'] as String),
      );
}

class NoteDao {
  final AppDatabase _appDatabase;

  NoteDao({AppDatabase? appDatabase})
      : _appDatabase = appDatabase ?? AppDatabase.instance;

  Future<Database> get _db => _appDatabase.database;

  Future<int> insert(NoteRecord note) async {
    final db = await _db;
    return db.insert('notes', note.toMap());
  }

  /// Writes [note] back, always stamping a fresh `updated_at` — callers hold
  /// editor state, not clocks.
  Future<int> update(NoteRecord note) async {
    final db = await _db;
    final map = note.toMap()
      ..['updated_at'] = DateTime.now().toIso8601String();
    return db.update('notes', map, where: 'id = ?', whereArgs: [note.id]);
  }

  Future<int> delete(int id) async {
    final db = await _db;
    return db.delete('notes', where: 'id = ?', whereArgs: [id]);
  }

  Future<NoteRecord?> getById(int id) async {
    final db = await _db;
    final rows = await db.query('notes', where: 'id = ?', whereArgs: [id]);
    if (rows.isEmpty) return null;
    return NoteRecord.fromMap(rows.first);
  }

  Future<List<NoteRecord>> getForPaper(int paperId) async {
    final db = await _db;
    final rows = await db.query(
      'notes',
      where: 'paper_id = ?',
      whereArgs: [paperId],
      orderBy: 'updated_at DESC',
    );
    return rows.map(NoteRecord.fromMap).toList();
  }

  /// Notes not attached to any paper — the cross-paper topic pages.
  Future<List<NoteRecord>> getTopicPages() async {
    final db = await _db;
    final rows = await db.query(
      'notes',
      where: 'paper_id IS NULL',
      orderBy: 'updated_at DESC',
    );
    return rows.map(NoteRecord.fromMap).toList();
  }

  Future<List<NoteRecord>> search(String query) async {
    final ftsQuery = _toFtsQuery(query);
    if (ftsQuery.isEmpty) return [];

    final db = await _db;
    final rows = await db.rawQuery('''
      SELECT n.* FROM notes n
      INNER JOIN notes_fts fts ON n.id = fts.rowid
      WHERE notes_fts MATCH ?
      ORDER BY rank
    ''', [ftsQuery]);
    return rows.map(NoteRecord.fromMap).toList();
  }

  /// Converts free-form user input into a safe FTS5 MATCH expression:
  /// each term is quoted (so `:`, `-`, `"` etc. can't break the query
  /// syntax) and the last term matches as a prefix for search-as-you-type.
  String _toFtsQuery(String query) {
    final terms = query
        .split(RegExp(r'\s+'))
        .where((t) => t.isNotEmpty)
        .map((t) => '"${t.replaceAll('"', '""')}"')
        .toList();
    if (terms.isEmpty) return '';
    terms[terms.length - 1] = '${terms.last}*';
    return terms.join(' ');
  }

  /// Appends a quoted passage, with a `papers://` backlink to the source page,
  /// to the paper's primary note — the oldest note for that paper, so repeated
  /// captures always land on the same page. Creates the note when there is
  /// none. Returns the note id.
  Future<int> appendQuote({
    required int paperId,
    required String quote,
    required int page,
  }) async {
    final db = await _db;
    final block = quoteBlock(paperId: paperId, quote: quote, page: page);

    final existing = await db.query(
      'notes',
      where: 'paper_id = ?',
      whereArgs: [paperId],
      orderBy: 'id ASC',
      limit: 1,
    );

    final now = DateTime.now().toIso8601String();
    if (existing.isEmpty) {
      return db.insert('notes', {
        'paper_id': paperId,
        'title': null,
        'body_md': block,
        'created_at': now,
        'updated_at': now,
      });
    }

    final note = NoteRecord.fromMap(existing.first);
    final body = note.bodyMd.trimRight();
    final merged = body.isEmpty ? block : '$body\n\n$block';
    await db.update(
      'notes',
      {'body_md': merged, 'updated_at': now},
      where: 'id = ?',
      whereArgs: [note.id],
    );
    return note.id!;
  }

  /// The markdown a captured quote renders to: a blockquote plus an
  /// attribution line linking back to the exact page in the reader.
  static String quoteBlock({
    required int paperId,
    required String quote,
    required int page,
  }) {
    final quoted =
        quote.trim().split('\n').map((line) => '> ${line.trim()}').join('\n');
    return '$quoted\n> — [p. $page](papers://open/$paperId?page=$page)';
  }
}
