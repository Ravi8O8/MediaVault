import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show compute;
import 'package:crypto/crypto.dart' as crypto; // входит в encrypt-транзитивно

class HashService {
  HashService._();

  /// SHA-256 от расшифрованных байтов (в изоляте для больших файлов).
  /// Если файл < 4 МБ — считаем синхронно на месте, чтобы не плодить изоляты.
  static Future<String> hashDecryptedBytes(Uint8List bytes) async {
    if (bytes.length < 4 * 1024 * 1024) {
      return _hashSync(bytes);
    }
    return compute(_hashSync, bytes);
  }

  static Future<String> hashFileByPath(
    String path,
    Future<Uint8List> Function() decryptor,
  ) async {
    final file = File(path);
    if (!await file.exists()) return '';
    final bytes = await file.readAsBytes();
    final dec = await decryptor();
    return hashDecryptedBytes(dec);
  }

  static String _hashSync(Uint8List bytes) {
    return crypto.sha256.convert(bytes).toString();
  }
}
