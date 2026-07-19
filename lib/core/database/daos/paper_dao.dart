import 'package:sqflite/sqflite.dart';

import '../../models/author_model.dart';
import '../../models/paper_model.dart';
import '../app_database.dart';

class PaperDao {
  final AppDatabase _appDatabase;

  PaperDao({AppDatabase? appDatabase})
      : _appDatabase = appDatabase ?? AppDatabase.instance;

  Future<Database> get _db => _appDatabase.database;

  Future<int> insertPaper(PaperModel paper) async {
    final db = await _db;
    return db.transaction((txn) async {
      final paperId = await txn.insert('papers', paper.toMap());

      for (var i = 0; i < paper.authors.length; i++) {
        final author = paper.authors[i];
        final authorId = await _insertOrGetAuthor(txn, author);
        await txn.insert('paper_authors', {
          'paper_id': paperId,
          'author_id': authorId,
          'position': i,
        });
      }

      for (final tagName in paper.tags) {
        final tagId = await _insertOrGetTag(txn, tagName);
        await txn.insert('paper_tags', {
          'paper_id': paperId,
          'tag_id': tagId,
        });
      }

      return paperId;
    });
  }

  /// Updates the paper row and rewrites its author/tag relations to match
  /// [paper]. Use this instead of [updatePaper] when authors or tags changed.
  Future<void> updatePaperWithRelations(PaperModel paper) async {
    final db = await _db;
    await db.transaction((txn) async {
      await txn.update(
        'papers',
        paper.toMap(),
        where: 'id = ?',
        whereArgs: [paper.id],
      );

      await txn.delete('paper_authors',
          where: 'paper_id = ?', whereArgs: [paper.id]);
      for (var i = 0; i < paper.authors.length; i++) {
        final authorId = await _insertOrGetAuthor(txn, paper.authors[i]);
        await txn.insert('paper_authors', {
          'paper_id': paper.id,
          'author_id': authorId,
          'position': i,
        });
      }

      await txn.delete('paper_tags',
          where: 'paper_id = ?', whereArgs: [paper.id]);
      for (final tagName in paper.tags) {
        final tagId = await _insertOrGetTag(txn, tagName);
        await txn.insert('paper_tags', {
          'paper_id': paper.id,
          'tag_id': tagId,
        });
      }
    });
  }

  Future<int> _insertOrGetAuthor(Transaction txn, AuthorModel author) async {
    // given_name may be null; SQL `= NULL` never matches, so branch on it.
    final hasGivenName = author.givenName != null;
    final existing = await txn.query(
      'authors',
      where: hasGivenName
          ? 'family_name = ? AND given_name = ?'
          : 'family_name = ? AND given_name IS NULL',
      whereArgs: [
        author.familyName,
        if (hasGivenName) author.givenName,
      ],
    );
    if (existing.isNotEmpty) {
      return existing.first['id'] as int;
    }
    return txn.insert('authors', author.toMap());
  }

  Future<int> _insertOrGetTag(Transaction txn, String tagName) async {
    final existing = await txn.query(
      'tags',
      where: 'name = ?',
      whereArgs: [tagName],
    );
    if (existing.isNotEmpty) {
      return existing.first['id'] as int;
    }
    return txn.insert('tags', {'name': tagName});
  }

  Future<List<PaperModel>> getAllPapers({
    String? orderBy,
    bool descending = true,
  }) async {
    final db = await _db;
    final order = orderBy ?? 'date_added';
    final dir = descending ? 'DESC' : 'ASC';
    final rows = await db.query('papers', orderBy: '$order $dir');

    final papers = <PaperModel>[];
    for (final row in rows) {
      final paper = PaperModel.fromMap(row);
      final authors = await _getAuthorsForPaper(db, paper.id!);
      final tags = await _getTagsForPaper(db, paper.id!);
      papers.add(paper.copyWith(authors: authors, tags: tags));
    }
    return papers;
  }

  Future<PaperModel?> getPaperById(int id) async {
    final db = await _db;
    final rows = await db.query('papers', where: 'id = ?', whereArgs: [id]);
    if (rows.isEmpty) return null;

    final paper = PaperModel.fromMap(rows.first);
    final authors = await _getAuthorsForPaper(db, id);
    final tags = await _getTagsForPaper(db, id);
    return paper.copyWith(authors: authors, tags: tags);
  }

  Future<PaperModel?> getPaperByDoi(String doi) async {
    final db = await _db;
    final rows = await db.query('papers', where: 'doi = ?', whereArgs: [doi]);
    if (rows.isEmpty) return null;
    return PaperModel.fromMap(rows.first);
  }

  Future<List<AuthorModel>> _getAuthorsForPaper(Database db, int paperId) async {
    final rows = await db.rawQuery('''
      SELECT a.* FROM authors a
      INNER JOIN paper_authors pa ON a.id = pa.author_id
      WHERE pa.paper_id = ?
      ORDER BY pa.position
    ''', [paperId]);
    return rows.map(AuthorModel.fromMap).toList();
  }

  Future<List<String>> _getTagsForPaper(Database db, int paperId) async {
    final rows = await db.rawQuery('''
      SELECT t.name FROM tags t
      INNER JOIN paper_tags pt ON t.id = pt.tag_id
      WHERE pt.paper_id = ?
    ''', [paperId]);
    return rows.map((r) => r['name'] as String).toList();
  }

  Future<int> updatePaper(PaperModel paper) async {
    final db = await _db;
    return db.update(
      'papers',
      paper.toMap(),
      where: 'id = ?',
      whereArgs: [paper.id],
    );
  }

  Future<int> deletePaper(int id) async {
    final db = await _db;
    return db.delete('papers', where: 'id = ?', whereArgs: [id]);
  }

  Future<void> toggleFavorite(int id, bool isFavorite) async {
    final db = await _db;
    await db.update(
      'papers',
      {'is_favorite': isFavorite ? 1 : 0},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<List<PaperModel>> searchPapers(String query) async {
    final ftsQuery = _toFtsQuery(query);
    if (ftsQuery.isEmpty) return [];

    final db = await _db;
    final rows = await db.rawQuery('''
      SELECT p.* FROM papers p
      INNER JOIN papers_fts fts ON p.id = fts.rowid
      WHERE papers_fts MATCH ?
      ORDER BY rank
    ''', [ftsQuery]);

    final papers = <PaperModel>[];
    for (final row in rows) {
      final paper = PaperModel.fromMap(row);
      final authors = await _getAuthorsForPaper(db, paper.id!);
      final tags = await _getTagsForPaper(db, paper.id!);
      papers.add(paper.copyWith(authors: authors, tags: tags));
    }
    return papers;
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
}
