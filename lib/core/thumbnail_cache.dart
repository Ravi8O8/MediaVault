import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show compute;
import 'package:image/image.dart' as img;

import 'crypto_service.dart';

/// Кэш миниатюр. Хранит МАЛЕНЬКИЕ JPEG-превью (до 400 px, ~30-60 КБ),
/// а не полные расшифрованные байты. Это ключ к производительности:
/// 100 записей × 50 КБ = ~5 МБ вместо 100 × 5 МБ = 500 МБ.
class ThumbnailCache {
  static final Map<String, Uint8List> _cache = {};
  static const int _maxSize = 100;
  static const int _thumbMaxWidth = 400;
  static const int _jpegQuality = 82;

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
      _cache[filePath] = value; // LRU: touch
      return value;
    }
    return null;
  }

  static void put(String filePath, Uint8List value) {
    while (_cache.length >= _maxSize) {
      _cache.remove(_cache.keys.first);
    }
    _cache[filePath] = value;
  }

  static void evict(String filePath) => _cache.remove(filePath);
  static int debugCount() => _cache.length;

  /// Возвращает МАЛЕНЬКУЮ JPEG-миниатюру (не полный файл!).
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
      if (!await file.exists()) return null;
      final encryptedBytes = await file.readAsBytes();
      final decrypted = await CryptoService.decryptData(encryptedBytes);

      if (isCancelled?.call() ?? false) return null;

      // Тяжёлая работа (decode + resize + encode) — в отдельном изоляте,
      // чтобы не фризить UI.
      final thumb = await compute(_makeThumbnailInIsolate, decrypted);
      if (thumb == null) return null;

      if (isCancelled?.call() ?? false) return null;

      put(filePath, thumb);
      return thumb;
    } catch (_) {
      return null;
    } finally {
      _release();
    }
  }

  static void clear() => _cache.clear();
}

/// Выполняется в изоляте — можно блокировать сколько нужно.
Uint8List? _makeThumbnailInIsolate(Uint8List decrypted) {
  try {
    final decoded = img.decodeImage(decrypted);
    if (decoded == null) return null;

    img.Image resized = decoded;
    if (decoded.width > ThumbnailCache._thumbMaxWidth) {
      resized = img.copyResize(
        decoded,
        width: ThumbnailCache._thumbMaxWidth,
        interpolation: img.Interpolation.linear,
      );
    }

    final encoded = img.encodeJpg(resized, quality: ThumbnailCache._jpegQuality);
    return Uint8List.fromList(encoded);
  } catch (_) {
    return null;
  }
}
