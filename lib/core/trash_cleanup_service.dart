import 'dart:io';
import 'package:sqflite_sqlcipher/sqflite.dart';
import 'thumbnail_cache.dart';   // ← если у тебя другой путь, поправь

class TrashCleanupService {
  static const String _table = 'media';   // ← имя таблицы
  static const int defaultDaysOld = 30;

  /// Удаляет из корзины файлы, у которых deleted_at старше [daysOld] дней.
  /// Возвращает количество удалённых записей.
  static Future<int> purgeOldTrash(
    Database db, {
    int daysOld = defaultDaysOld,
    ThumbnailCache? cache,
  }) async {
    final cutoff = DateTime.now()
        .subtract(Duration(days: daysOld))
        .millisecondsSinceEpoch;

    final rows = await db.query(
      _table,
      columns: ['id', 'file_path'],
      where: 'deleted_at IS NOT NULL AND deleted_at < ?',
      whereArgs: [cutoff],
    );
    if (rows.isEmpty) return 0;

    final ids = <int>[];
    for (final r in rows) {
      final id = r['id'] as int;
      final path = r['file_path'] as String;
      try {
        final f = File(path);
        if (await f.exists()) await f.delete();
      } catch (_) {}
      cache?.evict(path);   // см. метод ниже
      ids.add(id);
    }

    final placeholders = List.filled(ids.length, '?').join(',');
    await db.delete(
      _table,
      where: 'id IN ($placeholders)',
      whereArgs: ids,
    );
    return ids.length;
  }

  /// Полная очистка корзины (кнопка «Очистить всё»).
  static Future<int> purgeAll(
    Database db, {
    ThumbnailCache? cache,
  }) async {
    final rows = await db.query(
      _table,
      columns: ['id', 'file_path'],
      where: 'deleted_at IS NOT NULL',
    );
    if (rows.isEmpty) return 0;

    final ids = <int>[];
    for (final r in rows) {
      final id = r['id'] as int;
      final path = r['file_path'] as String;
      try {
        final f = File(path);
        if (await f.exists()) await f.delete();
      } catch (_) {}
      cache?.evict(path);
      ids.add(id);
    }
    final placeholders = List.filled(ids.length, '?').join(',');
    await db.delete(_table, where: 'id IN ($placeholders)', whereArgs: ids);
    return ids.length;
  }
}
