import 'package:sqflite/sqflite.dart';

import '../app_database.dart';

class CollectionRecord {
  final int? id;
  final String name;
  final String? color;
  final int? parentId;
  final DateTime createdAt;

  const CollectionRecord({
    this.id,
    required this.name,
    this.color,
    this.parentId,
    required this.createdAt,
  });

  Map<String, dynamic> toMap() => {
        if (id != null) 'id': id,
        'name': name,
        'color': color,
        'parent_id': parentId,
        'created_at': createdAt.toIso8601String(),
      };

  static CollectionRecord fromMap(Map<String, dynamic> map) => CollectionRecord(
        id: map['id'] as int?,
        name: map['name'] as String,
        color: map['color'] as String?,
        parentId: map['parent_id'] as int?,
        createdAt: DateTime.parse(map['created_at'] as String),
      );
}

class CollectionDao {
  final AppDatabase _appDatabase;

  CollectionDao({AppDatabase? appDatabase})
      : _appDatabase = appDatabase ?? AppDatabase.instance;

  Future<Database> get _db => _appDatabase.database;

  Future<int> insert(CollectionRecord collection) async {
    final db = await _db;
    return db.insert('collections', collection.toMap());
  }

  Future<List<CollectionRecord>> getAll() async {
    final db = await _db;
    final rows = await db.query('collections', orderBy: 'name ASC');
    return rows.map(CollectionRecord.fromMap).toList();
  }

  Future<List<CollectionRecord>> getChildren(int parentId) async {
    final db = await _db;
    final rows = await db.query(
      'collections',
      where: 'parent_id = ?',
      whereArgs: [parentId],
      orderBy: 'name ASC',
    );
    return rows.map(CollectionRecord.fromMap).toList();
  }

  Future<List<CollectionRecord>> getRoots() async {
    final db = await _db;
    final rows = await db.query(
      'collections',
      where: 'parent_id IS NULL',
      orderBy: 'name ASC',
    );
    return rows.map(CollectionRecord.fromMap).toList();
  }

  Future<int> update(CollectionRecord collection) async {
    final db = await _db;
    return db.update(
      'collections',
      collection.toMap(),
      where: 'id = ?',
      whereArgs: [collection.id],
    );
  }

  Future<int> delete(int id) async {
    final db = await _db;
    return db.delete('collections', where: 'id = ?', whereArgs: [id]);
  }

  Future<void> addPaperToCollection(int paperId, int collectionId) async {
    final db = await _db;
    await db.insert('paper_collections', {
      'paper_id': paperId,
      'collection_id': collectionId,
    }, conflictAlgorithm: ConflictAlgorithm.ignore);
  }

  Future<void> removePaperFromCollection(int paperId, int collectionId) async {
    final db = await _db;
    await db.delete(
      'paper_collections',
      where: 'paper_id = ? AND collection_id = ?',
      whereArgs: [paperId, collectionId],
    );
  }

  Future<List<int>> getPaperIdsInCollection(int collectionId) async {
    final db = await _db;
    final rows = await db.query(
      'paper_collections',
      columns: ['paper_id'],
      where: 'collection_id = ?',
      whereArgs: [collectionId],
    );
    return rows.map((r) => r['paper_id'] as int).toList();
  }

  /// Paper ids in [collectionId] **and every descendant collection**, so
  /// filtering by a parent includes everything filed beneath it.
  Future<Set<int>> getPaperIdsInSubtree(int collectionId) async {
    final db = await _db;
    final rows = await db.rawQuery('''
      WITH RECURSIVE subtree(id) AS (
        SELECT id FROM collections WHERE id = ?
        UNION ALL
        SELECT c.id FROM collections c JOIN subtree s ON c.parent_id = s.id
      )
      SELECT DISTINCT paper_id FROM paper_collections
      WHERE collection_id IN (SELECT id FROM subtree)
    ''', [collectionId]);
    return rows.map((r) => r['paper_id'] as int).toSet();
  }

  /// True when [candidateParentId] is [collectionId] itself or one of its
  /// descendants — used to reject re-parenting that would create a cycle.
  Future<bool> wouldCreateCycle(int collectionId, int candidateParentId) async {
    if (collectionId == candidateParentId) return true;
    final db = await _db;
    final rows = await db.rawQuery('''
      WITH RECURSIVE subtree(id) AS (
        SELECT id FROM collections WHERE id = ?
        UNION ALL
        SELECT c.id FROM collections c JOIN subtree s ON c.parent_id = s.id
      )
      SELECT 1 FROM subtree WHERE id = ? LIMIT 1
    ''', [collectionId, candidateParentId]);
    return rows.isNotEmpty;
  }

  Future<void> setParent(int collectionId, int? parentId) async {
    final db = await _db;
    await db.update('collections', {'parent_id': parentId},
        where: 'id = ?', whereArgs: [collectionId]);
  }

  Future<void> addPapersToCollection(
      List<int> paperIds, int collectionId) async {
    if (paperIds.isEmpty) return;
    final db = await _db;
    await db.transaction((txn) async {
      for (final paperId in paperIds) {
        await txn.insert(
          'paper_collections',
          {'paper_id': paperId, 'collection_id': collectionId},
          conflictAlgorithm: ConflictAlgorithm.ignore,
        );
      }
    });
  }

  Future<Set<int>> getCollectionIdsForPaper(int paperId) async {
    final db = await _db;
    final rows = await db.query(
      'paper_collections',
      columns: ['collection_id'],
      where: 'paper_id = ?',
      whereArgs: [paperId],
    );
    return rows.map((r) => r['collection_id'] as int).toSet();
  }

  Future<List<String>> getAllTagNames() async {
    final db = await _db;
    final rows = await db.query('tags', orderBy: 'name ASC');
    return rows.map((r) => r['name'] as String).toList();
  }
}
