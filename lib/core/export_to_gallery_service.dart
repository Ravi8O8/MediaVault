import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:path_provider/path_provider.dart';
import 'package:photo_manager/photo_manager.dart';

import 'crypto_service.dart';
import 'database_service.dart';

class ExportResult {
  final int ok;
  final int failed;
  final String? error;

  const ExportResult({this.ok = 0, this.failed = 0, this.error});

  static const ExportResult empty = ExportResult();
}

class ExportToGalleryService {
  ExportToGalleryService._();

  static Future<ExportResult> export(
    DatabaseService db,
    List<int> ids, {
    required bool compressImages,
    required void Function(int done, int total) onProgress,
    required bool Function() isCancelled,
  }) async {
    if (ids.isEmpty) return ExportResult.empty;

    final ps = await PhotoManager.requestPermissionExtend();
    if (!ps.isAuth && !ps.hasAccess) {
      return const ExportResult(error: 'Нет доступа к галерее');
    }

    int ok = 0;
    int failed = 0;

    for (int i = 0; i < ids.length; i++) {
      if (isCancelled()) break;
      try {
        await _exportOne(db, ids[i], compressImages);
        ok++;
      } catch (_) {
        failed++;
      }
      onProgress(i + 1, ids.length);
    }

    return ExportResult(ok: ok, failed: failed);
  }

  static Future<void> _exportOne(
    DatabaseService db,
    int id,
    bool compressImages,
  ) async {
    final rows = await db.db.query(
      'media_items',
      columns: ['file_path', 'media_type'],
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    if (rows.isEmpty) throw Exception('not found');

    final path = rows.first['file_path'] as String;
    final type = rows.first['media_type'] as String? ?? 'image';

    final encryptedFile = File(path);
    if (!await encryptedFile.exists()) throw Exception('file missing');

    final encrypted = await encryptedFile.readAsBytes();
    final decrypted = await CryptoService.decryptData(encrypted);

    if (type == 'video') {
      await _saveVideo(id, decrypted);
      return;
    }

    await _saveImage(id, decrypted, compressImages);
  }

  static Future<void> _saveImage(
    int id,
    Uint8List decrypted,
    bool compress,
  ) async {
    if (compress) {
      final webp = await _compressToWebp(decrypted);
      if (webp != null && webp.isNotEmpty) {
        await PhotoManager.editor.saveImage(
          webp,
          filename: 'mediavault_${id}_${_stamp()}.webp',
        );
        return;
      }
    }
    await PhotoManager.editor.saveImage(
      decrypted,
      filename: 'mediavault_${id}_${_stamp()}.jpg',
    );
  }

  static Future<void> _saveVideo(int id, Uint8List decrypted) async {
    final tempDir = await getTemporaryDirectory();
    final tmpPath =
        '${tempDir.path}/exp_${id}_${DateTime.now().microsecondsSinceEpoch}.mp4';
    final tmp = File(tmpPath);
    try {
      await tmp.writeAsBytes(decrypted, flush: true);
      await PhotoManager.editor.saveVideo(
        tmp,
        title: 'mediavault_${id}_${_stamp()}.mp4',
      );
    } finally {
      try {
        await tmp.delete();
      } catch (_) {}
    }
  }

  static Future<Uint8List?> _compressToWebp(Uint8List input) async {
    try {
      return await FlutterImageCompress.compressWithList(
        input,
        quality: 95,
        format: CompressFormat.webp,
      );
    } catch (_) {
      return null;
    }
  }

  static String _stamp() {
    final now = DateTime.now();
    return '${now.year}'
        '${now.month.toString().padLeft(2, '0')}'
        '${now.day.toString().padLeft(2, '0')}_'
        '${now.hour.toString().padLeft(2, '0')}'
        '${now.minute.toString().padLeft(2, '0')}'
        '${now.second.toString().padLeft(2, '0')}';
  }
}
