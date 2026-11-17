import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:encrypt/encrypt.dart';
import 'package:flutter/foundation.dart' show compute;
import 'package:image/image.dart' as img;
import 'package:path_provider/path_provider.dart';
import 'package:video_thumbnail/video_thumbnail.dart';

import 'crypto_service.dart';

class _ThumbRequest {
  final Uint8List encryptedBytes;
  final String keyBase64;
  const _ThumbRequest(this.encryptedBytes, this.keyBase64);
}

Uint8List? _decryptAndThumbnailInIsolate(_ThumbRequest req) {
  try {
    final key = Key.fromBase64(req.keyBase64);
    final iv = IV(Uint8List.fromList(req.encryptedBytes.sublist(0, 16)));
    final cipherText = req.encryptedBytes.sublist(16);
    final encrypter = Encrypter(AES(key, mode: AESMode.cbc));
    final decrypted = encrypter.decryptBytes(Encrypted(cipherText), iv: iv);

    final decoded = img.decodeImage(Uint8List.fromList(decrypted));
    if (decoded == null) return null;

    img.Image resized = decoded;
    if (decoded.width > ThumbnailCache._thumbMaxWidth) {
      resized = img.copyResize(
        decoded,
        width: ThumbnailCache._thumbMaxWidth,
        interpolation: img.Interpolation.linear,
      );
    }

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
    bool isVideo = false,
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

      final Uint8List? thumb;
      if (isVideo) {
        thumb = await _loadVideoThumbnail(file, isCancelled);
      } else {
        final encryptedBytes = await file.readAsBytes();
        if (isCancelled?.call() ?? false) return null;
        final keyBase64 = await CryptoService.getKeyBase64();
        thumb = await compute(
          _decryptAndThumbnailInIsolate,
          _ThumbRequest(encryptedBytes, keyBase64),
        );
      }
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

  static Future<Uint8List?> _loadVideoThumbnail(
    File encryptedFile,
    bool Function()? isCancelled,
  ) async {
    File? tmpFile;
    try {
      final encrypted = await encryptedFile.readAsBytes();
      if (isCancelled?.call() ?? false) return null;
      final decrypted = await CryptoService.decryptData(encrypted);

      final tempDir = await getTemporaryDirectory();
      final tmpPath =
          '${tempDir.path}/vthumb_${DateTime.now().microsecondsSinceEpoch}.mp4';
      tmpFile = File(tmpPath);
      await tmpFile.writeAsBytes(decrypted, flush: true);

      if (isCancelled?.call() ?? false) return null;

      final thumb = await VideoThumbnail.thumbnailData(
        video: tmpPath,
        imageFormat: ImageFormat.JPEG,
        quality: 60,
        maxWidth: _thumbMaxWidth,
      );
      return thumb;
    } catch (_) {
      return null;
    } finally {
      if (tmpFile != null) {
        try {
          await tmpFile.delete();
        } catch (_) {}
      }
    }
  }

  static void clear() => _cache.clear();
}
