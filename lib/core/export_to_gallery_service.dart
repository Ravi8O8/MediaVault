import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive_io.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:photo_manager/photo_manager.dart';

import 'crypto_service.dart';
import 'database_service.dart';

class ExportResult {
  final int ok;
  final int failed;
  final String? error;
  final String? zipPath;

  const ExportResult({this.ok = 0, this.failed = 0, this.error, this.zipPath});

  static const ExportResult empty = ExportResult();
}

class ExportOptions {
  final bool compressImages;
  final bool toZip;
  final bool encryptZip;
  final VaultEncryptionType encType;

  const ExportOptions({
    this.compressImages = false,
    this.toZip = false,
    this.encryptZip = false,
    this.encType = VaultEncryptionType.aesCbc,
  });
}

class ExportToGalleryService {
  ExportToGalleryService._();

  static Future<ExportResult> export(
    DatabaseService db,
    List<int> ids, {
    required ExportOptions options,
    required void Function(int done, int total) onProgress,
    required bool Function() isCancelled,
  }) async {
    if (ids.isEmpty) return ExportResult.empty;

    if (options.toZip) {
      return _exportAsZip(db, ids, options, onProgress, isCancelled);
    }

    final ps = await PhotoManager.requestPermissionExtend();
    if (!ps.isAuth && !ps.hasAccess) {
      return const ExportResult(error: 'Нет доступа к галерее');
    }

    int ok = 0;
    int failed = 0;
    int processed = 0;

    final queue = List<int>.from(ids);
    final workers = <Future>[];
    const poolSize = 3;

    for (int w = 0; w < poolSize; w++) {
      workers.add(Future(() async {
        while (queue.isNotEmpty && !isCancelled()) {
          final id = queue.removeAt(0);
          try {
            await _exportOneToGallery(db, id, options.compressImages);
            ok++;
          } catch (_) {
            failed++;
          }
          processed++;
          onProgress(processed, ids.length);
        }
      }));
    }

    await Future.wait(workers);
    return ExportResult(ok: ok, failed: failed);
  }

  static Future<void> _exportOneToGallery(
    DatabaseService db,
    int id,
    bool compress,
  ) async {
    final rows = await db.db.query(
      'media_items',
      columns: ['file_path', 'media_type', 'encryption_type'],
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    if (rows.isEmpty) throw Exception('not found');

    final path = rows.first['file_path'] as String;
    final type = rows.first['media_type'] as String? ?? 'image';
    final encType =
        encryptionTypeFromKey(rows.first['encryption_type'] as String?);

    final encryptedFile = File(path);
    if (!await encryptedFile.exists()) throw Exception('file missing');

    final encrypted = await encryptedFile.readAsBytes();
    final decrypted = await CryptoService.decryptData(encrypted, type: encType);

    if (type == 'video') {
      await _saveVideo(id, decrypted);
      return;
    }

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

  static Future<ExportResult> _exportAsZip(
    DatabaseService db,
    List<int> ids,
    ExportOptions options,
    void Function(int, int) onProgress,
    bool Function() isCancelled,
  ) async {
    int processed = 0;
    final archive = Archive();

    for (final id in ids) {
      if (isCancelled()) break;
      try {
        final rows = await db.db.query(
          'media_items',
          columns: ['file_path', 'media_type', 'encryption_type'],
          where: 'id = ?',
          whereArgs: [id],
          limit: 1,
        );
        if (rows.isEmpty) continue;

        final path = rows.first['file_path'] as String;
        final type = rows.first['media_type'] as String? ?? 'image';
        final encType =
            encryptionTypeFromKey(rows.first['encryption_type'] as String?);

        final file = File(path);
        if (!await file.exists()) continue;

        final encrypted = await file.readAsBytes();
        final decrypted =
            await CryptoService.decryptData(encrypted, type: encType);

        String name =
            'mediavault_${id}_${_stamp()}.${type == 'video' ? 'mp4' : 'jpg'}';
        Uint8List dataToStore = decrypted;

        if (type != 'video' && options.compressImages) {
          final webp = await _compressToWebp(decrypted);
          if (webp != null) {
            name = 'mediavault_${id}_${_stamp()}.webp';
            dataToStore = webp;
          }
        }

        // archive 3.6.1: конструктор positional — (name, size, content)
        archive.addFile(ArchiveFile(name, dataToStore.length, dataToStore));
      } catch (_) {}
      processed++;
      onProgress(processed, ids.length);
    }

    if (archive.isEmpty) return const ExportResult(error: 'Архив пуст');

    final zipBytesRaw = ZipEncoder().encode(archive);
    if (zipBytesRaw == null) {
      return const ExportResult(error: 'Не удалось собрать архив');
    }
    final zipData = Uint8List.fromList(zipBytesRaw);

    String finalZipName = 'MediaVault_Backup_${_stamp()}.zip';
    Uint8List finalData = zipData;

    if (options.encryptZip) {
      finalZipName = 'MediaVault_Backup_${_stamp()}.mvault';
      finalData = await CryptoService.encryptData(
        zipData,
        type: options.encType,
      );
    }

    // Открываем системное окно «Сохранить как»
    try {
      final savedPath = await FilePicker.platform.saveFile(
        dialogTitle: 'Сохранить архив',
        fileName: finalZipName,
        type: FileType.custom,
        allowedExtensions: [options.encryptZip ? 'mvault' : 'zip'],
        bytes: finalData,
      );

      if (savedPath == null) {
        return const ExportResult(error: 'Сохранение отменено');
      }

      return ExportResult(ok: ids.length, zipPath: savedPath);
    } catch (e) {
      return ExportResult(error: 'Ошибка сохранения: $e');
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
