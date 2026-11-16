import 'dart:io';

import 'package:flutter/foundation.dart' show compute;

import 'database_service.dart';

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

  static const StorageStats empty = StorageStats(
    totalBytes: 0,
    totalFiles: 0,
    activeFiles: 0,
    trashedFiles: 0,
    dbBytes: 0,
  );

  static String formatBytes(int bytes) {
    if (bytes <= 0) return '0 Б';
    if (bytes < 1024) return '$bytes Б';
    if (bytes < 1024 * 1024) {
      return '${(bytes / 1024).toStringAsFixed(1)} КБ';
    }
    if (bytes < 1024 * 1024 * 1024) {
      return '${(bytes / 1024 / 1024).toStringAsFixed(1)} МБ';
    }
    return '${(bytes / 1024 / 1024 / 1024).toStringAsFixed(2)} ГБ';
  }
}

class StorageStatsService {
  StorageStatsService._();

  static Future<StorageStats> computeStats(DatabaseService db) async {
    final List<Map<String, dynamic>> active;
    final List<Map<String, dynamic>> trashed;
    try {
      active = await db.getAllMediaItems();
      trashed = await db.getDeletedMediaItems();
    } catch (_) {
      return StorageStats.empty;
    }

    final paths = <String>[];
    for (final r in active) {
      final p = r['file_path'];
      if (p is String && p.isNotEmpty) paths.add(p);
    }
    for (final r in trashed) {
      final p = r['file_path'];
      if (p is String && p.isNotEmpty) paths.add(p);
    }

    final int totalBytes = paths.isEmpty
        ? 0
        : await compute(_sumFileSizesInIsolate, paths);

    int dbBytes = 0;
    try {
      final f = File(db.db.path);
      if (await f.exists()) dbBytes = await f.length();
    } catch (_) {}

    return StorageStats(
      totalBytes: totalBytes,
      totalFiles: paths.length,
      activeFiles: active.length,
      trashedFiles: trashed.length,
      dbBytes: dbBytes,
    );
  }

  static int _sumFileSizesInIsolate(List<String> paths) {
    int total = 0;
    for (final p in paths) {
      try {
        total += File(p).lengthSync();
      } catch (_) {}
    }
    return total;
  }
}
