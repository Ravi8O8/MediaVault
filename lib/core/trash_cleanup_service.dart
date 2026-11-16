import 'dart:io';
import 'database_service.dart';

class TrashCleanupResult {
  final int removedCount;
  final int removedBytes;

  const TrashCleanupResult({
    required this.removedCount,
    required this.removedBytes,
  });

  static const TrashCleanupResult empty =
      TrashCleanupResult(removedCount: 0, removedBytes: 0);
}

class TrashCleanupService {
  TrashCleanupService._();

  static const int defaultDaysOld = 30; // Значение по умолчанию

  static Future<TrashCleanupResult> purgeOldTrash(
    DatabaseService db, {
    int daysOld = defaultDaysOld,
    void Function(String path)? onDeleted,
  }) async {
    if (daysOld <= 0) return TrashCleanupResult.empty; // Если выключено

    final cutoff = DateTime.now()
        .subtract(Duration(days: daysOld))
        .millisecondsSinceEpoch;

    final List<Map<String, dynamic>> trashed;
    try {
      trashed = await db.getDeletedMediaItems();
    } catch (_) {
      return TrashCleanupResult.empty;
    }
    if (trashed.isEmpty) return TrashCleanupResult.empty;

    final toDelete = <Map<String, dynamic>>[];
    for (final row in trashed) {
      final deletedAt = row['deleted_at'];
      if (deletedAt is! int) continue;
      if (deletedAt < cutoff) toDelete.add(row);
    }
    return _purge(db, toDelete, onDeleted: onDeleted);
  }

  static Future<TrashCleanupResult> purgeAll(
    DatabaseService db, {
    void Function(String path)? onDeleted,
  }) async {
    final List<Map<String, dynamic>> trashed;
    try {
      trashed = await db.getDeletedMediaItems();
    } catch (_) {
      return TrashCleanupResult.empty;
    }
    return _purge(db, trashed, onDeleted: onDeleted);
  }

  static Future<TrashCleanupResult> _purge(
    DatabaseService db,
    List<Map<String, dynamic>> rows, {
    void Function(String path)? onDeleted,
  }) async {
    if (rows.isEmpty) return TrashCleanupResult.empty;

    int removedBytes = 0;
    int removedCount = 0;

    for (final row in rows) {
      final idRaw = row['id'];
      final pathRaw = row['file_path'];
      if (idRaw is! int) continue;
      final path = pathRaw is String ? pathRaw : '';

      if (path.isNotEmpty) {
        try {
          final f = File(path);
          if (await f.exists()) {
            removedBytes += await f.length();
          }
        } catch (_) {}
      }
      try {
        await db.permanentlyDeleteMediaItem(idRaw, path);
        removedCount++;
      } catch (_) {
        continue;
      }
      if (path.isNotEmpty) onDeleted?.call(path);
    }

    return TrashCleanupResult(
      removedCount: removedCount,
      removedBytes: removedBytes,
    );
  }
}
