import 'dart:io';
import 'dart:typed_data';
import 'crypto_service.dart';

/// Простой LRU-кэш для расшифрованных миниатюр.
/// Хранит последние 100 расшифрованных картинок в оперативной памяти.
class ThumbnailCache {
  static final Map<String, Uint8List> _cache = {};
  static const int _maxSize = 100;

  static Uint8List? get(String filePath) {
    if (_cache.containsKey(filePath)) {
      // Перемещаем в конец (отмечаем как недавно использованное)
      final value = _cache.remove(filePath)!;
      _cache[filePath] = value;
      return value;
    }
    return null;
  }

  static void put(String filePath, Uint8List value) {
    if (_cache.length >= _maxSize) {
      _cache.remove(_cache.keys.first); // Удаляем самый старый
    }
    _cache[filePath] = value;
  }

  static Future<Uint8List> load(String filePath) async {
    final cached = get(filePath);
    if (cached != null) return cached;

    final file = File(filePath);
    final encryptedBytes = await file.readAsBytes();
    final decrypted = await CryptoService.decryptData(encryptedBytes);
    put(filePath, decrypted);
    return decrypted;
  }

  static void clear() {
    _cache.clear();
  }
}
