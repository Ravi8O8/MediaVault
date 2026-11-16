import 'dart:typed_data';
import 'package:encrypt/encrypt.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class CryptoService {
  static const _secureStorage = FlutterSecureStorage();
  static const _keyStorageKey = 'vault_aes_key';

  /// Получает или генерирует 32-байтовый ключ (AES-256)
  static Future<Key> _getKey() async {
    var keyString = await _secureStorage.read(key: _keyStorageKey);
    if (keyString == null) {
      final key = Key.fromSecureRandom(32); // 256 бит
      await _secureStorage.write(key: _keyStorageKey, value: key.base64);
      return key;
    }
    return Key.fromBase64(keyString);
  }

  /// Шифрует данные и возвращает IV + зашифрованные данные
  static Future<Uint8List> encryptData(Uint8List data) async {
    final key = await _getKey();
    final iv = IV.fromSecureRandom(16); // Уникальный IV для каждого файла
    final encrypter = Encrypter(AES(key, mode: AESMode.cbc));

    final encrypted = encrypter.encryptBytes(data, iv: iv);
    
    // Склеиваем IV (16 байт) + зашифрованные данные
    final result = Uint8List(16 + encrypted.bytes.length);
    result.setRange(0, 16, iv.bytes);
    result.setRange(16, result.length, encrypted.bytes);
    return result;
  }

  /// Расшифровывает данные, извлекая IV из первых 16 байт
  static Future<Uint8List> decryptData(Uint8List encryptedData) async {
    final key = await _getKey();
    final iv = IV(Uint8List.fromList(encryptedData.sublist(0, 16)));
    final cipherText = encryptedData.sublist(16);
    
    final encrypter = Encrypter(AES(key, mode: AESMode.cbc));
    final decrypted = encrypter.decryptBytes(Encrypted(cipherText), iv: iv);
    
    return Uint8List.fromList(decrypted);
  }
}
