import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import 'crypto_service.dart';
import 'database_service.dart';

class ExportService {
  ExportService._();

  /// Дешифрует выбранные файлы во временную папку и открывает share-шит.
  /// Пользователь сам выберет «Сохранить в Downloads» / «Отправить» и т.д.
  /// Возвращает количество успешно экспортированных файлов.
  static Future<int> exportAndShare(
    DatabaseService db,
    List<int> ids, {
    void Function(int processed, int total)? onProgress,
  }) async {
    if (ids.isEmpty) return 0;

    final tmpRoot = await getTemporaryDirectory();
    final stamp = DateTime.now().millisecondsSinceEpoch;
    final outDir = Directory(p.join(tmpRoot.path, 'mv_export_$stamp'));
    if (!await outDir.exists()) await outDir.create(recursive: true);

    final outFiles = <XFile>[];
    int ok = 0;
    final total = ids.length;

    for (int i = 0; i < total; i++) {
      final id = ids[i];
      try {
        final rows = await db.db.query(
          'media_items',
          columns: ['file_path', 'media_type'],
          where: 'id = ?',
          whereArgs: [id],
          limit: 1,
        );
        if (rows.isEmpty) continue;
        final path = rows.first['file_path'] as String;
        final type = rows.first['media_type'] as String? ?? 'image';

        final file = File(path);
        if (!await file.exists()) continue;

        final enc = await file.readAsBytes();
        final dec = await CryptoService.decryptData(enc);

        final ext = type == 'video' ? 'mp4' : 'jpg';
        final name = 'mv_$stamp_$id.$ext';
        final outPath = p.join(outDir.path, name);
        await File(outPath).writeAsBytes(dec, flush: true);
        outFiles.add(XFile(outPath, mimeType: type == 'video' ? 'video/mp4' : 'image/jpeg'));
        ok++;
      } catch (_) {}
      onProgress?.call(i + 1, total);
    }

    if (outFiles.isNotEmpty) {
      await Share.shareXFiles(
        outFiles,
        subject: 'MediaVault export',
      );
    }
    return ok;
  }
}
