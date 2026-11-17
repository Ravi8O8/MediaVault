import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:encrypt/encrypt.dart';
import 'package:flutter/foundation.dart' show compute;
import 'package:image/image.dart' as img;

import 'crypto_service.dart';

class _ThumbRequest {
  final Uint8List encryptedBytes;
  final String keyBase64;
  const _ThumbRequest(this.encryptedBytes, this.keyBase64);
}

/// Всё в одном изоляте: расшифровка AES-CBC → decode → resize → encode JPEG.
/// Один спавн вместо двух — заметно быстрее на слабых устройствах.
Uint8List? _decryptAndThumbnailInIsolate(_ThumbRequest req) {
  try {
    // 1. Расшифровка (первые 16 байт — IV, остальное — ciphertext)
    final key = Key.fromBase64(req.keyBase64);
    final iv = IV(Uint8List.fromList(req.encryptedBytes.sublist(0, 16)));
    final cipherText = req.encryptedBytes.sublist(16);
    final encrypter = Encrypter(AES(key, mode: AESMode.cbc));
    final decrypted = encrypter.decryptBytes(Encrypted(cipherText), iv: iv);

    // 2. Decode
    final decoded = img.decodeImage(Uint8List.fromList(decrypted));
    if (decoded == null) return null;

    // 3. Resize
    img.Image resized = decoded;
    if (decoded.width > ThumbnailCache._thumbMaxWidth) {
      resized = img.copyResize(
        decoded,
        width: ThumbnailCache._thumbMaxWidth,
        interpolation: img.Interpolation.linear,
      );
    }

    // 4. Encode
    final encoded = img.encodeJpg(
      resized,
      quality: ThumbnailCache._jpegQuality,
    );
    return Uint8List.fromList(encoded);
  } catch (_) {
    return null;
  }
}

class ThumbnailCache {
  static final Map<String, Uint8List> _cache = {};
  static const int _maxSize = 80;
  static const int _thumbMaxWidth = 240;
  static const int _jpegQuality = 72;

  static int _activeLoads = 0;
  static const int _maxConcurrent = 4;
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
    while (_cache.length >= _maxSize) {
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
      if (!await file.exists()) return null;
      final encryptedBytes = await file.readAsBytes();

      if (isCancelled?.call() ?? false) return null;

      // Один изолят делает всю работу: decrypt → decode → resize → encode
      final keyBase64 = await CryptoService.getKeyBase64();
      final thumb = await compute(
        _decryptAndThumbnailInIsolate,
        _ThumbRequest(encryptedBytes, keyBase64),
      );
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
