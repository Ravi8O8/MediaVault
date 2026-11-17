import 'dart:typed_data';
import 'package:encrypt/encrypt.dart';
import 'package:flutter/foundation.dart' show compute;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class _EncryptRequest {
  final String keyBase64;
  final Uint8List data;
  const _EncryptRequest(this.keyBase64, this.data);
}

class _DecryptRequest {
  final String keyBase64;
  final Uint8List data;
  const _DecryptRequest(this.keyBase64, this.data);
}

Uint8List _encryptInIsolate(_EncryptRequest req) {
  final key = Key.fromBase64(req.keyBase64);
  final iv = IV.fromSecureRandom(16);
  final encrypter = Encrypter(AES(key, mode: AESMode.cbc));
  final encrypted = encrypter.encryptBytes(req.data, iv: iv);
  final result = Uint8List(16 + encrypted.bytes.length);
  result.setRange(0, 16, iv.bytes);
  result.setRange(16, result.length, encrypted.bytes);
  return result;
}

Uint8List _decryptInIsolate(_DecryptRequest req) {
  final key = Key.fromBase64(req.keyBase64);
  final iv = IV(Uint8List.fromList(req.data.sublist(0, 16)));
  final cipherText = req.data.sublist(16);
  final encrypter = Encrypter(AES(key, mode: AESMode.cbc));
  final decrypted = encrypter.decryptBytes(Encrypted(cipherText), iv: iv);
  return Uint8List.fromList(decrypted);
}

class CryptoService {
  static const _secureStorage = FlutterSecureStorage();
  static const _keyStorageKey = 'vault_aes_key';

  static Future<Key>? _keyFuture;

  static Future<Key> _getKey() {
    return _keyFuture ??= _loadOrCreateKey();
  }

  static Future<Key> _loadOrCreateKey() async {
    try {
      final keyString = await _secureStorage.read(key: _keyStorageKey);
      if (keyString != null) {
        return Key.fromBase64(keyString);
      }
      final key = Key.fromSecureRandom(32);
      await _secureStorage.write(key: _keyStorageKey, value: key.base64);
      return key;
    } catch (_) {
      _keyFuture = null;
      rethrow;
    }
  }

  /// Публичный доступ к ключу (base64) — нужен для комбинированного изолята
  /// в ThumbnailCache (расшифровка + сжатие в одном проходе).
  static Future<String> getKeyBase64() async {
    final key = await _getKey();
    return key.base64;
  }

  /// Всегда выполняется в отдельном изоляте — UI-поток не блокируется.
  static Future<Uint8List> encryptData(Uint8List data) async {
    final key = await _getKey();
    return compute(_encryptInIsolate, _EncryptRequest(key.base64, data));
  }

  /// Всегда выполняется в отдельном изоляте — критично для скролла сетки:
  /// даже маленькая расшифровка не должна задерживать кадр.
  static Future<Uint8List> decryptData(Uint8List encryptedData) async {
    final key = await _getKey();
    return compute(
      _decryptInIsolate,
      _DecryptRequest(key.base64, encryptedData),
    );
  }
}
