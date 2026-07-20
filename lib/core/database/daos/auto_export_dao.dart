import 'package:sqflite/sqflite.dart';

import '../app_database.dart';

/// A .bib file kept in sync with the library (or one collection).
class AutoExportRecord {
  final int? id;
  final String targetPath;
  final String scope;
  final int? collectionId;
  final DateTime? lastExported;

  const AutoExportRecord({
    this.id,
    required this.targetPath,
    this.scope = 'library',
    this.collectionId,
    this.lastExported,
  });

  Map<String, dynamic> toMap() => {
        if (id != null) 'id': id,
        'target_path': targetPath,
        'scope': scope,
        'collection_id': collectionId,
        'last_exported': lastExported?.toIso8601String(),
      };

  static AutoExportRecord fromMap(Map<String, dynamic> map) => AutoExportRecord(
        id: map['id'] as int?,
        targetPath: map['target_path'] as String,
        scope: map['scope'] as String? ?? 'library',
        collectionId: map['collection_id'] as int?,
        lastExported: map['last_exported'] != null
            ? DateTime.parse(map['last_exported'] as String)
            : null,
      );
}

class AutoExportDao {
  final AppDatabase _appDatabase;

  AutoExportDao({AppDatabase? appDatabase})
      : _appDatabase = appDatabase ?? AppDatabase.instance;

  Future<Database> get _db => _appDatabase.database;

  Future<int> insert(AutoExportRecord record) async {
    final db = await _db;
    return db.insert('auto_exports', record.toMap());
  }

  Future<List<AutoExportRecord>> getAll() async {
    final db = await _db;
    final rows = await db.query('auto_exports', orderBy: 'id ASC');
    return rows.map(AutoExportRecord.fromMap).toList();
  }

  Future<int> delete(int id) async {
    final db = await _db;
    return db.delete('auto_exports', where: 'id = ?', whereArgs: [id]);
  }

  Future<void> markExported(int id, DateTime when) async {
    final db = await _db;
    await db.update(
      'auto_exports',
      {'last_exported': when.toIso8601String()},
      where: 'id = ?',
      whereArgs: [id],
    );
  }
}
