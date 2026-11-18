import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:encrypt/encrypt.dart' as enc;
import 'package:flutter/foundation.dart' show compute;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:pointycastle/export.dart' as pc;

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
        return 'AES-256-CTR (потоковый, любой размер)';
      case VaultEncryptionType.none:
        return 'Без шифрования';
    }
  }

  String get description {
    switch (this) {
      case VaultEncryptionType.aesCbc:
        return 'Старый формат. Только чтение.';
      case VaultEncryptionType.aesCtr:
        return 'Нативный streaming. RAM ~256 КБ, подходит для 4 ГБ+ видео.';
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

// ─────────────────────── STREAMING (pointycastle) ───────────────────────

class _FileCryptoRequest {
  final String inputPath;
  final String outputPath;
  final String keyBase64;
  final bool encrypt;
  final String? existingIvBase64; // null при шифровании → генерируется
  const _FileCryptoRequest({
    required this.inputPath,
    required this.outputPath,
    required this.keyBase64,
    required this.encrypt,
    this.existingIvBase64,
  });
}

Future<bool> _streamCryptoFile(_FileCryptoRequest req) async {
  final keyBytes = base64Decode(req.keyBase64);
  final input = File(req.inputPath);
  final output = File(req.outputPath);

  final rafIn = await input.open();
  final rafOut = await output.open(mode: FileMode.write);

  try {
    Uint8List iv;
    if (req.encrypt) {
      iv = Uint8List(16);
      final rng = Random.secure();
      for (int i = 0; i < 16; i++) {
        iv[i] = rng.nextInt(256);
      }
      await rafOut.writeFrom(iv);
    } else {
      iv = Uint8List(16);
      final read = await rafIn.readInto(iv);
      if (read < 16) return false;
    }

    final cipher = pc.SICBlockCipher(pc.AESEngine());
    cipher.init(req.encrypt, pc.ParametersWithIV(pc.KeyParameter(keyBytes), iv));

    const chunkSize = 256 * 1024; // кратно 16
    final buffer = Uint8List(chunkSize);

    int read;
    while ((read = await rafIn.readInto(buffer)) > 0) {
      final out = Uint8List(read);
      int offset = 0;
      while (offset < read) {
        final remaining = read - offset;
        if (remaining >= 16) {
          cipher.processBlock(buffer, offset, out, offset);
          offset += 16;
        } else {
          // последний неполный блок
          final padded = Uint8List(16);
          padded.setRange(0, remaining, buffer, offset);
          final blockOut = Uint8List(16);
          cipher.processBlock(padded, 0, blockOut, 0);
          out.setRange(offset, offset + remaining, blockOut.sublist(0, remaining));
          offset += remaining;
        }
      }
      await rafOut.writeFrom(out);
    }
  } finally {
    await rafIn.close();
    await rafOut.close();
  }
  return true;
}

// ─────────────────────── LEGACY in-memory (CBC) ───────────────────────

class _EncryptRequest {
  final String keyBase64;
  final Uint8List data;
  const _EncryptRequest(this.keyBase64, this.data);
}

class _DecryptRequest {
  final String keyBase64;
  final Uint8List data;
  final String typeKey;
  const _DecryptRequest(this.keyBase64, this.data, this.typeKey);
}

Uint8List _encryptCbcInIsolate(_EncryptRequest req) {
  final key = enc.Key.fromBase64(req.keyBase64);
  final iv = enc.IV.fromSecureRandom(16);
  final encrypter = enc.Encrypter(enc.AES(key, mode: enc.AESMode.cbc));
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
  final decrypted = encrypter.decryptBytes(enc.Encrypted(cipherText), iv: iv);
  return Uint8List.fromList(decrypted);
}

// ─────────────────────── PUBLIC API ───────────────────────

class CryptoService {
  CryptoService._();

  static const _secureStorage = FlutterSecureStorage();
  static const _keyStorageKey = 'vault_aes_key';

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

  /// Потоковое шифрование AES-256-CTR.
  /// Формат: [16 IV][ciphertext]. RAM ~256 КБ независимо от размера файла.
  /// Работает для файлов от 1 КБ до 100+ ГБ.
  static Future<bool> encryptFileStreaming({
    required String inputPath,
    required String outputPath,
  }) async {
    final key = await _getKey();
    return compute(_streamCryptoFile, _FileCryptoRequest(
      inputPath: inputPath,
      outputPath: outputPath,
      keyBase64: key.base64,
      encrypt: true,
    ));
  }

  /// Потоковое расшифрование AES-256-CTR.
  static Future<bool> decryptFileStreaming({
    required String inputPath,
    required String outputPath,
  }) async {
    final key = await _getKey();
    return compute(_streamCryptoFile, _FileCryptoRequest(
      inputPath: inputPath,
      outputPath: outputPath,
      keyBase64: key.base64,
      encrypt: false,
    ));
  }

  /// Универсальный decrypt файла в файл по типу из БД.
  /// - `aesCtr` → streaming (постоянная RAM)
  /// - `aesCbc` → legacy in-memory (старые файлы, до ~500 МБ)
  /// - `none` → копирование
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

  // ── LEGACY in-memory API (для мелких операций / старых файлов) ──

  static Future<Uint8List> encryptData(
    Uint8List data, {
    VaultEncryptionType type = VaultEncryptionType.aesCbc,
  }) async {
    if (type == VaultEncryptionType.none) return data;
    final key = await _getKey();
    return compute(_encryptCbcInIsolate, _EncryptRequest(key.base64, data));
  }

  static Future<Uint8List> decryptData(
    Uint8List encryptedData, {
    VaultEncryptionType type = VaultEncryptionType.aesCbc,
  }) async {
    if (type == VaultEncryptionType.none) return encryptedData;
    final key = await _getKey();
    return compute(_decryptInIsolate,
        _DecryptRequest(key.base64, encryptedData, type.key));
  }
}
