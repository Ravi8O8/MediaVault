import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'crypto_service.dart';

class ThumbnailCache {
  static final Map<String, Uint8List> _cache = {};
  static const int _maxSize = 100; // Храним меньше картинок, чтобы не лагало

  static int _activeLoads = 0;
  static const int _maxConcurrent = 3;
  static final List<Completer<void>> _waiters = [];

  static Future<void> _acquire() async {
    if (_activeLoads < _maxConcurrent) {
      _activeLoads++;
      return;
    }
    final completer = Completer<void>();
    _waiters.add(completer);
    await completer.future;
  }

  static void _release() {
    if (_waiters.isNotEmpty) {
      final next = _waiters.removeAt(0);
      next.complete();
    } else {
      _activeLoads--;
    }
  }

  static Uint8List? get(String filePath) {
    if (_cache.containsKey(filePath)) {
      final value = _cache.remove(filePath)!;
      _cache[filePath] = value;
      return value;
    }
    return null;
  }

  static void put(String filePath, Uint8List value) {
    if (_cache.length >= _maxSize) {
      _cache.remove(_cache.keys.first);
    }
    _cache[filePath] = value;
  }

  static void evict(String filePath) => _cache.remove(filePath);
  static int debugCount() => _cache.length;

  static Future<Uint8List?> load(
    String filePath, {
    bool Function()? isCancelled,
  }) async {
    final cached = get(filePath);
    if (cached != null) return cached;

    await _acquire();
    try {
      if (isCancelled?.call() ?? false) return null;

      final again = get(filePath);
      if (again != null) return again;

      final file = File(filePath);
      final encryptedBytes = await file.readAsBytes();
      final decrypted = await CryptoService.decryptData(encryptedBytes);

      if (isCancelled?.call() ?? false) return null;

      put(filePath, decrypted);
      return decrypted;
    } finally {
      _release();
    }
  }

  static void clear() => _cache.clear();
}
