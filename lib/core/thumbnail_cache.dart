import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:encrypt/encrypt.dart';
import 'package:flutter/foundation.dart' show compute;
import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
// Замена video_thumbnail на ym_video_thumbnail
import 'package:ym_video_thumbnail/ym_video_thumbnail.dart';

import 'crypto_service.dart';

class _ThumbRequest {
  final Uint8List encryptedBytes;
  final String keyBase64;
  final String typeKey;
  const _ThumbRequest(this.encryptedBytes, this.keyBase64, this.typeKey);
}

Uint8List? _decryptAndThumbnailInIsolate(_ThumbRequest req) {
  try {
    Uint8List data;
    if (req.typeKey == 'none') {
      data = req.encryptedBytes;
    } else {
      if (req.encryptedBytes.length < 16) return null;
      final key = Key.fromBase64(req.keyBase64);
      final iv = IV(Uint8List.fromList(req.encryptedBytes.sublist(0, 16)));
      final cipherText = req.encryptedBytes.sublist(16);
      final mode = req.typeKey == 'aes_ctr' ? AESMode.ctr : AESMode.cbc;
      final encrypter = Encrypter(AES(key, mode: mode));
      final decrypted = encrypter.decryptBytes(Encrypted(cipherText), iv: iv);
      data = Uint8List.fromList(decrypted);
    }

    final decoded = img.decodeImage(data);
    if (decoded == null) return null;

    img.Image resized = decoded;
    if (decoded.width > ThumbnailCache._thumbMaxWidth) {
      resized = img.copyResize(
        decoded,
        width: ThumbnailCache._thumbMaxWidth,
        interpolation: img.Interpolation.linear,
      );
    }

    return Uint8List.fromList(
        img.encodeJpg(resized, quality: ThumbnailCache._jpegQuality));
  } catch (_) {
    return null;
  }
}

class ThumbnailCache {
  static final Map<String, Uint8List> _cache = {};
  static const int _maxSize = 200;
  static const int _thumbMaxWidth = 240;
  static const int _jpegQuality = 72;

  static int _activeLoads = 0;
  static const int _maxConcurrent = 6;
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
      _cache[filePath] = value; // LRU
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

  static Future<String> _thumbPathFor(int mediaId) async {
    final appDir = await getApplicationDocumentsDirectory();
    return p.join(appDir.path, 'vault_thumbs', '$mediaId.jpg');
  }

  static Future<Uint8List?> _readFromDisk(int mediaId) async {
    try {
      final path = await _thumbPathFor(mediaId);
      final f = File(path);
      if (!await f.exists()) return null;
      return await f.readAsBytes();
    } catch (_) {
      return null;
    }
  }

  static Future<void> _writeToDisk(int mediaId, Uint8List thumb) async {
    try {
      final path = await _thumbPathFor(mediaId);
      final f = File(path);
      final parent = f.parent;
      if (!await parent.exists()) await parent.create(recursive: true);
      await f.writeAsBytes(thumb, flush: true);
    } catch (_) {}
  }

  static Future<void> evictDisk(int mediaId) async {
    try {
      final path = await _thumbPathFor(mediaId);
      final f = File(path);
      if (await f.exists()) await f.delete();
    } catch (_) {}
  }

  static Future<Uint8List?> load(
    String filePath, {
    int? mediaId,
    bool isVideo = false,
    VaultEncryptionType encryptionType = VaultEncryptionType.aesCbc,
    bool Function()? isCancelled,
  }) async {
    final cached = get(filePath);
    if (cached != null) return cached;

    if (mediaId != null) {
      final fromDisk = await _readFromDisk(mediaId);
      if (fromDisk != null) {
        put(filePath, fromDisk);
        return fromDisk;
      }
    }

    await _acquire();
    try {
      if (isCancelled?.call() ?? false) return null;

      final again = get(filePath);
      if (again != null) return again;

      final file = File(filePath);
      if (!await file.exists()) return null;

      final Uint8List? thumb;
      if (isVideo) {
        thumb = await _loadVideoThumbnail(file, encryptionType, isCancelled);
      } else {
        final encryptedBytes = await file.readAsBytes();
        if (isCancelled?.call() ?? false) return null;
        final keyBase64 = await CryptoService.getKeyBase64();
        thumb = await compute(
          _decryptAndThumbnailInIsolate,
          _ThumbRequest(encryptedBytes, keyBase64, encryptionType.key),
        );
      }
      if (thumb == null) return null;

      if (isCancelled?.call() ?? false) return null;

      put(filePath, thumb);
      if (mediaId != null) {
        unawaited(_writeToDisk(mediaId, thumb));
      }
      return thumb;
    } catch (_) {
      return null;
    } finally {
      _release();
    }
  }

  static Future<void> generateAndSaveForMedia(
    int mediaId,
    String encryptedPath,
    bool isVideo,
    VaultEncryptionType encryptionType,
  ) async {
    try {
      final file = File(encryptedPath);
      if (!await file.exists()) return;

      Uint8List? thumb;
      if (isVideo) {
        thumb = await _loadVideoThumbnail(file, encryptionType, null);
      } else {
        final encryptedBytes = await file.readAsBytes();
        final keyBase64 = await CryptoService.getKeyBase64();
        thumb = await compute(
          _decryptAndThumbnailInIsolate,
          _ThumbRequest(encryptedBytes, keyBase64, encryptionType.key),
        );
      }

      if (thumb != null) {
        await _writeToDisk(mediaId, thumb);
      }
    } catch (_) {}
  }

  static Future<Uint8List?> _loadVideoThumbnail(
    File encryptedFile,
    VaultEncryptionType type,
    bool Function()? isCancelled,
  ) async {
    File? tmpFile;
    try {
      final encrypted = await encryptedFile.readAsBytes();
      if (isCancelled?.call() ?? false) return null;
      final decrypted = await CryptoService.decryptData(encrypted, type: type);

      final tempDir = await getTemporaryDirectory();
      final tmpPath =
          '${tempDir.path}/vthumb_${DateTime.now().microsecondsSinceEpoch}.mp4';
      tmpFile = File(tmpPath);
      await tmpFile.writeAsBytes(decrypted, flush: true);

      if (isCancelled?.call() ?? false) return null;

      // API ym_video_thumbnail идентичен video_thumbnail
      return await VideoThumbnail.thumbnailData(
        video: tmpPath,
        imageFormat: ImageFormat.jpeg,
        quality: 60,
        maxWidth: _thumbMaxWidth,
      );
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
