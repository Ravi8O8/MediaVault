import 'dart:io';
import 'dart:typed_data';

import 'package:aes_encrypt_file/aes_encrypt_file.dart';
import 'package:encrypt/encrypt.dart' as enc;
import 'package:flutter/foundation.dart' show compute;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

enum VaultEncryptionType { aesCbc, aesCtr, none }

extension VaultEncryptionTypeX on VaultEncryptionType {
  String get key {
    switch (this) {
      case VaultEncryptionType.aesCbc:
        return 'aes_cbc';
      case VaultEncryptionType.aesCtr:
        return 'aes_ctr';
      case VaultEncryptionType.none:
        return 'none';
    }
  }

  String get label {
    switch (this) {
      case VaultEncryptionType.aesCbc:
        return 'AES-256-CBC (legacy)';
      case VaultEncryptionType.aesCtr:
        return 'AES-256-CTR (потоковый)';
      case VaultEncryptionType.none:
        return 'Без шифрования';
    }
  }

  String get description {
    switch (this) {
      case VaultEncryptionType.aesCbc:
        return 'Старый формат. Только чтение.';
      case VaultEncryptionType.aesCtr:
        return 'Нативный streaming. Любой размер, RAM ~const.';
      case VaultEncryptionType.none:
        return 'Файлы на диске читаемы. Не рекомендуется.';
    }
  }
}

VaultEncryptionType encryptionTypeFromKey(String? k) {
  switch (k) {
    case 'aes_ctr':
      return VaultEncryptionType.aesCtr;
    case 'none':
      return VaultEncryptionType.none;
    default:
      return VaultEncryptionType.aesCbc;
  }
}

// ── legacy in-memory helpers (только для чтения старых CBC) ──
class _EncryptRequest {
  final String keyBase64;
  final Uint8List data;
  final String typeKey;
  const _EncryptRequest(this.keyBase64, this.data, this.typeKey);
}

class _DecryptRequest {
  final String keyBase64;
  final Uint8List data;
  final String typeKey;
  const _DecryptRequest(this.keyBase64, this.data, this.typeKey);
}

Uint8List _encryptInIsolate(_EncryptRequest req) {
  if (req.typeKey == 'none') return req.data;
  final key = enc.Key.fromBase64(req.keyBase64);
  final iv = enc.IV.fromSecureRandom(16);
  final mode = req.typeKey == 'aes_ctr' ? enc.AESMode.ctr : enc.AESMode.cbc;
  final encrypter = enc.Encrypter(enc.AES(key, mode: mode));
  final encrypted = encrypter.encryptBytes(req.data, iv: iv);
  final result = Uint8List(16 + encrypted.bytes.length);
  result.setRange(0, 16, iv.bytes);
  result.setRange(16, result.length, encrypted.bytes);
  return result;
}

Uint8List _decryptInIsolate(_DecryptRequest req) {
  if (req.typeKey == 'none') return req.data;
  if (req.data.length < 16) return Uint8List(0);
  final key = enc.Key.fromBase64(req.keyBase64);
  final iv = enc.IV(Uint8List.fromList(req.data.sublist(0, 16)));
  final cipherText = req.data.sublist(16);
  final mode = req.typeKey == 'aes_ctr' ? enc.AESMode.ctr : enc.AESMode.cbc;
  final encrypter = enc.Encrypter(enc.AES(key, mode: mode));
  final decrypted =
      encrypter.decryptBytes(enc.Encrypted(cipherText), iv: iv);
  return Uint8List.fromList(decrypted);
}

class CryptoService {
  CryptoService._();

  static const _secureStorage = FlutterSecureStorage();
  static const _keyStorageKey = 'vault_aes_key';

  static final _aesFile = AesEncryptFile();

  static Future<enc.Key>? _keyFuture;

  static Future<enc.Key> _getKey() {
    return _keyFuture ??= _loadOrCreateKey();
  }

  static Future<enc.Key> _loadOrCreateKey() async {
    try {
      final keyString = await _secureStorage.read(key: _keyStorageKey);
      if (keyString != null) return enc.Key.fromBase64(keyString);
      final key = enc.Key.fromSecureRandom(32);
      await _secureStorage.write(key: _keyStorageKey, value: key.base64);
      return key;
    } catch (_) {
      _keyFuture = null;
      rethrow;
    }
  }

  static Future<String> getKeyBase64() async => (await _getKey()).base64;

  // ── STREAMING API (рекомендуется для 100+ ГБ) ──

  /// Шифрует файл потоково (AES-256-CTR, native).
  /// IV генерируется автоматически и пишется в начало выходного файла.
  static Future<bool> encryptFileStreaming({
    required String inputPath,
    required String outputPath,
  }) async {
    final key = await _getKey();
    return _aesFile.encryptFile(
      inputPath: inputPath,
      outputPath: outputPath,
      key: key.base64,
      // iv не передаём → генерируется и сохраняется в файл
    );
  }

  /// Расшифровывает потоковый файл (IV читается из начала файла).
  static Future<bool> decryptFileStreaming({
    required String inputPath,
    required String outputPath,
  }) async {
    final key = await _getKey();
    return _aesFile.decryptFile(
      inputPath: inputPath,
      outputPath: outputPath,
      key: key.base64,
    );
  }

  /// Универсальный decrypt файла с учётом типа из БД.
  /// Для `aesCtr` — streaming; для `aesCbc` — legacy in-memory.
  static Future<void> decryptFileTo({
    required String inputPath,
    required String outputPath,
    required VaultEncryptionType type,
  }) async {
    if (type == VaultEncryptionType.none) {
      await File(inputPath).copy(outputPath);
      return;
    }
    if (type == VaultEncryptionType.aesCtr) {
      final ok = await decryptFileStreaming(
        inputPath: inputPath,
        outputPath: outputPath,
      );
      if (!ok) throw Exception('Streaming decrypt failed');
      return;
    }
    // legacy CBC
    final bytes = await File(inputPath).readAsBytes();
    final dec = await decryptData(bytes, type: type);
    await File(outputPath).writeAsBytes(dec, flush: true);
  }

  // ── LEGACY in-memory API (только для старых файлов / мелких операций) ──

  static Future<Uint8List> encryptData(
    Uint8List data, {
    VaultEncryptionType type = VaultEncryptionType.aesCbc,
  }) async {
    if (type == VaultEncryptionType.none) return data;
    final key = await _getKey();
    return compute(
      _encryptInIsolate,
      _EncryptRequest(key.base64, data, type.key),
    );
  }

  static Future<Uint8List> decryptData(
    Uint8List encryptedData, {
    VaultEncryptionType type = VaultEncryptionType.aesCbc,
  }) async {
    if (type == VaultEncryptionType.none) return encryptedData;
    final key = await _getKey();
    return compute(
      _decryptInIsolate,
      _DecryptRequest(key.base64, encryptedData, type.key),
    );
  }
}
