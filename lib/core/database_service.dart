import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:path/path.dart';
import 'package:sqflite_sqlcipher/sqflite.dart';

class DatabaseService {
  static const _keyStorageKey = 'db_encryption_key';
  static const _secureStorage = FlutterSecureStorage();
  late Database _db;
  Database get db => _db;

  Future<void> init() async {
    var key = await _secureStorage.read(key: _keyStorageKey);
    if (key == null) {
      final rnd = Random.secure();
      final bytes = List<int>.generate(32, (_) => rnd.nextInt(256));
      key = base64UrlEncode(bytes);
      await _secureStorage.write(key: _keyStorageKey, value: key);
    }
    final dbPath = join(await getDatabasesPath(), 'vault.db');
    _db = await openDatabase(
      dbPath,
      password: key,
      version: 3,
      onCreate: (db, version) async {
        await db.execute(
          '''CREATE TABLE media_items (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            file_path TEXT NOT NULL,
            media_type TEXT NOT NULL,
            created_at INTEGER NOT NULL,
            is_favorite INTEGER DEFAULT 0,
            album_id INTEGER,
            deleted_at INTEGER,
            file_hash TEXT,
            folder_path TEXT
          )''',
        );
        await db.execute(
          '''CREATE TABLE albums (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            name TEXT NOT NULL,
            created_at INTEGER NOT NULL,
            cover_media_id INTEGER
          )''',
        );
      },
      onUpgrade: (db, oldV, newV) async {
        if (oldV < 2) {
          try {
            await db.execute('ALTER TABLE media_items ADD COLUMN file_hash TEXT');
          } catch (_) {}
          try {
            await db.execute('ALTER TABLE albums ADD COLUMN cover_media_id INTEGER');
          } catch (_) {}
        }
        if (oldV < 3) {
          try {
            await db.execute('ALTER TABLE media_items ADD COLUMN folder_path TEXT');
          } catch (_) {}
        }
      },
    );
  }

  // ---------- MEDIA ----------

  Future<int> insertMediaItem(String filePath, String mediaType,
      {String? folderPath, int? albumId}) async {
    return await _db.insert('media_items', {
      'file_path': filePath,
      'media_type': mediaType,
      'created_at': DateTime.now().millisecondsSinceEpoch,
      'folder_path': folderPath,
      'album_id': albumId,
    });
  }

  Future<List<Map<String, dynamic>>> getAllMediaItems() async {
    return await _db.query('media_items',
        where: 'deleted_at IS NULL', orderBy: 'created_at DESC');
  }

  Future<List<Map<String, dynamic>>> searchMediaItems(String query) async {
    final q = '%${query.trim()}%';
    return await _db.query(
      'media_items',
      where: 'deleted_at IS NULL AND file_path LIKE ?',
      whereArgs: [q],
      orderBy: 'created_at DESC',
    );
  }

  Future<List<Map<String, dynamic>>> getDeletedMediaItems() async {
    return await _db.query('media_items',
        where: 'deleted_at IS NOT NULL', orderBy: 'deleted_at DESC');
  }

  Future<void> softDeleteMediaItem(int id) async {
    await _db.update(
      'media_items',
      {'deleted_at': DateTime.now().millisecondsSinceEpoch},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<void> restoreMediaItem(int id) async {
    await _db.update('media_items', {'deleted_at': null},
        where: 'id = ?', whereArgs: [id]);
  }

  Future<void> permanentlyDeleteMediaItem(int id, String filePath) async {
    try {
      final file = File(filePath);
      if (await file.exists()) await file.delete();
    } catch (_) {}
    await _db.delete('media_items', where: 'id = ?', whereArgs: [id]);
  }

  Future<void> emptyTrash() async {
    final items = await getDeletedMediaItems();
    for (final item in items) {
      await permanentlyDeleteMediaItem(item['id'], item['file_path']);
    }
  }

  // ---------- FOLDERS ----------

  /// Все уникальные folder_path (только непустые), отсортированные.
  Future<List<String>> getAllFolderPaths() async {
    final rows = await _db.rawQuery(
      "SELECT DISTINCT folder_path FROM media_items "
      "WHERE deleted_at IS NULL AND folder_path IS NOT NULL AND folder_path != '' "
      "ORDER BY folder_path",
    );
    return rows.map((e) => e['folder_path'] as String).toList();
  }

  /// Файлы в конкретной папке (не в подпапках).
  /// [folderPath] = '' → файлы с пустым/нулевым folder_path (импортированы по одному).
  Future<List<Map<String, dynamic>>> getMediaByFolder(String folderPath) async {
    if (folderPath.isEmpty) {
      return await _db.query(
        'media_items',
        where: "deleted_at IS NULL AND (folder_path IS NULL OR folder_path = '')",
        orderBy: 'created_at DESC',
      );
    }
    return await _db.query(
      'media_items',
      where: 'deleted_at IS NULL AND folder_path = ?',
      whereArgs: [folderPath],
      orderBy: 'created_at DESC',
    );
  }

  /// Непосредственные подпапки для [parentPath].
  /// Например, для `arts/John` вернёт ['videos', 'arts'] (только имена).
  Future<List<String>> getSubfolders(String parentPath) async {
    final all = await getAllFolderPaths();
    final prefix = parentPath.isEmpty ? '' : '$parentPath/';
    final result = <String>{};
    for (final f in all) {
      if (parentPath.isNotEmpty && !f.startsWith(prefix)) continue;
      final rest = f.substring(prefix.length);
      if (rest.isEmpty) continue;
      result.add(rest.split('/').first);
    }
    return result.toList()..sort();
  }

  Future<int> countFilesInFolder(String folderPath) async {
    final rows = folderPath.isEmpty
        ? await _db.rawQuery(
            "SELECT COUNT(*) as cnt FROM media_items "
            "WHERE deleted_at IS NULL AND (folder_path IS NULL OR folder_path = '')",
          )
        : await _db.rawQuery(
            "SELECT COUNT(*) as cnt FROM media_items "
            "WHERE deleted_at IS NULL AND folder_path = ?",
            [folderPath],
          );
    return (rows.first['cnt'] as int?) ?? 0;
  }

  Future<int> countFilesWithoutFolder() async {
    final rows = await _db.rawQuery(
      "SELECT COUNT(*) as cnt FROM media_items "
      "WHERE deleted_at IS NULL AND (folder_path IS NULL OR folder_path = '')",
    );
    return (rows.first['cnt'] as int?) ?? 0;
  }

  // ---------- ALBUMS ----------

  Future<int> insertAlbum(String name) async {
    return await _db.insert('albums', {
      'name': name,
      'created_at': DateTime.now().millisecondsSinceEpoch,
    });
  }

  Future<List<Map<String, dynamic>>> getAllAlbums() async {
    return await _db.query('albums', orderBy: 'created_at DESC');
  }

  Future<void> moveMediaToAlbum(int mediaId, int? albumId) async {
    await _db.update('media_items', {'album_id': albumId},
        where: 'id = ?', whereArgs: [mediaId]);
  }

  Future<List<Map<String, dynamic>>> getMediaByAlbum(int albumId) async {
    return await _db.query('media_items',
        where: 'album_id = ? AND deleted_at IS NULL',
        whereArgs: [albumId],
        orderBy: 'created_at DESC');
  }

  Future<void> setAlbumCover(int albumId, int? mediaId) async {
    await _db.update('albums', {'cover_media_id': mediaId},
        where: 'id = ?', whereArgs: [albumId]);
  }

  // ---------- FAVORITES ----------

  Future<void> toggleFavorite(int mediaId, bool isFavorite) async {
    await _db.update(
      'media_items',
      {'is_favorite': isFavorite ? 1 : 0},
      where: 'id = ?',
      whereArgs: [mediaId],
    );
  }

  Future<List<Map<String, dynamic>>> getFavoriteMediaItems() async {
    return await _db.query('media_items',
        where: 'is_favorite = 1 AND deleted_at IS NULL',
        orderBy: 'created_at DESC');
  }

  // ---------- HASHES / DUPLICATES ----------

  Future<List<Map<String, dynamic>>> getActiveMediaWithoutHash() async {
    return await _db.query(
      'media_items',
      columns: ['id', 'file_path'],
      where: 'deleted_at IS NULL AND (file_hash IS NULL OR file_hash = "")',
    );
  }

  Future<void> setFileHash(int id, String hash) async {
    await _db.update('media_items', {'file_hash': hash},
        where: 'id = ?', whereArgs: [id]);
  }

  Future<List<Map<String, dynamic>>> findDuplicateGroups() async {
    final rows = await _db.rawQuery(
      '''SELECT file_hash, COUNT(*) as cnt, GROUP_CONCAT(id) as ids
         FROM media_items
         WHERE deleted_at IS NULL AND file_hash IS NOT NULL AND file_hash != ""
         GROUP BY file_hash
         HAVING cnt > 1
         ORDER BY cnt DESC''',
    );
    return rows;
  }

  Future<List<Map<String, dynamic>>> getMediaByIds(List<int> ids) async {
    if (ids.isEmpty) return [];
    final ph = List.filled(ids.length, '?').join(',');
    return await _db.query('media_items',
        where: 'id IN ($ph)', whereArgs: ids);
  }
}
