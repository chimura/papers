import 'package:sqflite/sqflite.dart';

import '../app_database.dart';

/// A saved search: a serialized LibraryFilter plus the search text, shown
/// alongside real collections and re-evaluated live when opened.
class SmartCollectionRecord {
  final int? id;
  final String name;
  final String filterJson;
  final DateTime createdAt;

  const SmartCollectionRecord({
    this.id,
    required this.name,
    required this.filterJson,
    required this.createdAt,
  });

  Map<String, dynamic> toMap() => {
        if (id != null) 'id': id,
        'name': name,
        'filter_json': filterJson,
        'created_at': createdAt.toIso8601String(),
      };

  static SmartCollectionRecord fromMap(Map<String, dynamic> map) =>
      SmartCollectionRecord(
        id: map['id'] as int?,
        name: map['name'] as String,
        filterJson: map['filter_json'] as String,
        createdAt: DateTime.parse(map['created_at'] as String),
      );
}

class SmartCollectionDao {
  final AppDatabase _appDatabase;

  SmartCollectionDao({AppDatabase? appDatabase})
      : _appDatabase = appDatabase ?? AppDatabase.instance;

  Future<Database> get _db => _appDatabase.database;

  Future<int> insert(SmartCollectionRecord record) async {
    final db = await _db;
    return db.insert('smart_collections', record.toMap());
  }

  Future<List<SmartCollectionRecord>> getAll() async {
    final db = await _db;
    final rows = await db.query('smart_collections', orderBy: 'name ASC');
    return rows.map(SmartCollectionRecord.fromMap).toList();
  }

  Future<int> update(SmartCollectionRecord record) async {
    final db = await _db;
    return db.update('smart_collections', record.toMap(),
        where: 'id = ?', whereArgs: [record.id]);
  }

  Future<int> delete(int id) async {
    final db = await _db;
    return db.delete('smart_collections', where: 'id = ?', whereArgs: [id]);
  }
}
