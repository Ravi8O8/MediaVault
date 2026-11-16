import 'dart:typed_data';
import 'package:encrypt/encrypt.dart';
import 'package:flutter/foundation.dart';
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

  /// Порог, выше которого шифрование/расшифровка уходят в изолят.
  /// Мелкие файлы (миниатюры) обрабатываются синхронно — так быстрее.
  static const _isolateThreshold = 512 * 1024; // 512 KB

  static Future<Key> _getKey() async {
    var keyString = await _secureStorage.read(key: _keyStorageKey);
    if (keyString == null) {
      final key = Key.fromSecureRandom(32);
      await _secureStorage.write(key: _keyStorageKey, value: key.base64);
      return key;
    }
    return Key.fromBase64(keyString);
  }

  static Uint8List _encryptSync(Key key, Uint8List data) {
    final iv = IV.fromSecureRandom(16);
    final encrypter = Encrypter(AES(key, mode: AESMode.cbc));
    final encrypted = encrypter.encryptBytes(data, iv: iv);
    final result = Uint8List(16 + encrypted.bytes.length);
    result.setRange(0, 16, iv.bytes);
    result.setRange(16, result.length, encrypted.bytes);
    return result;
  }

  static Uint8List _decryptSync(Key key, Uint8List encryptedData) {
    final iv = IV(Uint8List.fromList(encryptedData.sublist(0, 16)));
    final cipherText = encryptedData.sublist(16);
    final encrypter = Encrypter(AES(key, mode: AESMode.cbc));
    final decrypted = encrypter.decryptBytes(Encrypted(cipherText), iv: iv);
    return Uint8List.fromList(decrypted);
  }

  static Future<Uint8List> encryptData(Uint8List data) async {
    final key = await _getKey();
    if (data.length < _isolateThreshold) {
      return _encryptSync(key, data);
    }
    return compute(_encryptInIsolate, _EncryptRequest(key.base64, data));
  }

  static Future<Uint8List> decryptData(Uint8List encryptedData) async {
    final key = await _getKey();
    if (encryptedData.length < _isolateThreshold) {
      return _decryptSync(key, encryptedData);
    }
    return compute(
      _decryptInIsolate,
      _DecryptRequest(key.base64, encryptedData),
    );
  }
}
