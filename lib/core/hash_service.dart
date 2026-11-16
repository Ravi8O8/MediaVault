import 'dart:typed_data';

class HashService {
  HashService._();

  /// Детерминированный хэш для поиска дубликатов.
  /// FNV-1a (32 бит) + сумма байтов (32 бит) + длина (64 бит).
  /// Для личного хранилища до ~10 000 файлов коллизий практически нет.
  static String hashBytes(Uint8List bytes) {
    int h = 0x811c9dc5;
    int sum = 0;
    for (int i = 0; i < bytes.length; i++) {
      final b = bytes[i];
      h = ((h ^ b) * 0x01000193) & 0xFFFFFFFF;
      sum = (sum + b) & 0xFFFFFFFF;
    }
    return '${h.toRadixString(16).padLeft(8, '0')}'
        '${sum.toRadixString(16).padLeft(8, '0')}'
        '${bytes.length.toRadixString(16)}';
  }
}
