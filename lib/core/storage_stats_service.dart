import 'dart:io';
import 'package:flutter/foundation.dart' show compute;
import 'package:sqflite_sqlcipher/sqflite.dart';

class StorageStats {
  final int totalBytes;
  final int totalFiles;
  final int activeFiles;
  final int trashedFiles;
  final int dbBytes;
  const StorageStats({
    required this.totalBytes,
    required this.totalFiles,
    required this.activeFiles,
    required this.trashedFiles,
    required this.dbBytes,
  });

  static String formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes Б';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} КБ';
    if (bytes < 1024 * 1024 * 1024) {
      return '${(bytes / 1024 / 1024).toStringAsFixed(1)} МБ';
    }
    return '${(bytes / 1024 / 1024 / 1024).toStringAsFixed(2)} ГБ';
  }
}

class StorageStatsService {
  /// ⚠️ Замени 'media' на реальное имя таблицы, если у тебя другое.
  static const String _table = 'media';

  static Future<StorageStats> computeStats(Database db) async {
    final rows = await db.query(_table, columns: ['file_path', 'deleted_at']);
    final paths = <String>[];
    int active = 0;
    int trashed = 0;
    for (final r in rows) {
      paths.add(r['file_path'] as String);
      if (r['deleted_at'] == null) {
        active++;
      } else {
        trashed++;
      }
    }
    // Сумма размеров — в изоляте (для 10k+ файлов не вешает UI)
    final totalBytes = paths.isEmpty
        ? 0
        : await compute(_sumFileSizes, paths);

    int dbBytes = 0;
    try {
      final f = File(db.path);
      if (await f.exists()) dbBytes = await f.length();
    } catch (_) {}

    return StorageStats(
      totalBytes: totalBytes,
      totalFiles: paths.length,
      activeFiles: active,
      trashedFiles: trashed,
      dbBytes: dbBytes,
    );
  }

  static int _sumFileSizes(List<String> paths) {
    int total = 0;
    for (final p in paths) {
      try {
        total += File(p).lengthSync();
      } catch (_) {}
    }
    return total;
  }
}
