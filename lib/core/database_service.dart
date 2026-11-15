import 'dart:convert';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:path/path.dart';
import 'package:sqflite_sqlcipher/sqflite.dart';

class DatabaseService {
  static const _keyStorageKey = 'db_encryption_key';
  static const _secureStorage = FlutterSecureStorage();
  late Database _db;

  Database get db => _db;

  Future<void> init() async {
    // 1. Получаем (или создаём) ключ шифрования в Android Keystore
    var key = await _secureStorage.read(key: _keyStorageKey);
    if (key == null) {
      key = base64UrlEncode(List.generate(32, (_) => DateTime.now().microsecond % 256));
      await _secureStorage.write(key: _keyStorageKey, value: key);
    }

    // 2. Открываем зашифрованную БД
    final dbPath = join(await getDatabasesPath(), 'vault.db');
    _db = await openDatabase(
      dbPath,
      password: key,
      version: 1,
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE media_items (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            file_path TEXT NOT NULL,
            media_type TEXT NOT NULL,
            created_at INTEGER NOT NULL,
            is_favorite INTEGER DEFAULT 0,
            album_id INTEGER,
            deleted_at INTEGER
          )
        ''');
        await db.execute('''
          CREATE TABLE albums (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            name TEXT NOT NULL,
            created_at INTEGER NOT NULL
          )
        ''');
      },
    );
  }
}
