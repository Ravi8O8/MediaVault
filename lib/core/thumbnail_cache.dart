import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'crypto_service.dart';

/// LRU-кэш миниатюр с ограничением параллельных расшифровок.
/// - Хранит до 500 уменьшенных картинок (~15 МБ RAM)
/// - Не более 3 одновременных расшифровок (защита от лагов)
/// - Поддерживает отмену, если элемент уже прокрутили
class ThumbnailCache {
  static final Map<String, Uint8List> _cache = {};
  static const int _maxSize = 500;

  // --- Семафор: не больше 3 одновременных загрузок ---
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

  // --- Основное API ---

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

  /// Расшифровывает, ресайзит до targetWidth и кэширует.
  /// [isCancelled] вызывается после получения слота в очереди —
  /// если вернёт true, загрузка прерывается (элемент уже не на экране).
  static Future<Uint8List?> load(
    String filePath, {
    int targetWidth = 300,
    bool Function()? isCancelled,
  }) async {
    final cached = get(filePath);
    if (cached != null) return cached;

    await _acquire();
    try {
      if (isCancelled?.call() ?? false) return null;

      // Двойная проверка: пока ждали слот, мог загрузить кто-то другой
      final again = get(filePath);
      if (again != null) return again;

      final file = File(filePath);
      final encryptedBytes = await file.readAsBytes();
      final decrypted = await CryptoService.decryptData(encryptedBytes);

      if (isCancelled?.call() ?? false) return null;

      final resized = await _resize(decrypted, targetWidth);
      put(filePath, resized);
      return resized;
    } finally {
      _release();
    }
  }

  static Future<Uint8List> _resize(Uint8List bytes, int targetWidth) async {
    final codec =
        await ui.instantiateImageCodec(bytes, targetWidth: targetWidth);
    final frame = await codec.getNextFrame();
    final byteData =
        await frame.image.toByteData(format: ui.ImageByteFormat.png);
    frame.image.dispose();
    codec.dispose();
    return byteData!.buffer.asUint8List();
  }

  static void clear() {
    _cache.clear();
  }
}
