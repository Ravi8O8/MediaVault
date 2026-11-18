import 'dart:io';

import 'package:archive/archive_io.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:photo_manager/photo_manager.dart';
import 'package:saf/saf.dart';

import 'crypto_service.dart';
import 'database_service.dart';

class ExportResult {
  final int ok;
  final int failed;
  final String? error;
  final String? outputPath;

  const ExportResult({
    this.ok = 0,
    this.failed = 0,
    this.error,
    this.outputPath,
  });

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
    this.encType = VaultEncryptionType.aesCtr,
  });
}

// Вспомогательный класс для фонового сжатия
class _ZipJob {
  final List<Map<String, String>> files;
  final String zipPath;
  _ZipJob(this.files, this.zipPath);
}

Future<String> _createZipInIsolate(_ZipJob job) async {
  final encoder = ZipFileEncoder();
  encoder.create(job.zipPath);
  for (final file in job.files) {
    await encoder.addFile(File(file['path']!), file['name']!);
  }
  encoder.close();
  return job.zipPath;
}

class ExportToGalleryService {
  ExportToGalleryService._();
  static final _saf = Saf();

  static Future<ExportResult> export(
    DatabaseService db,
    List<int> ids, {
    required ExportOptions options,
    required void Function(int done, int total) onProgress,
    required void Function(String status, String currentFile) onStatus,
    required bool Function() isCancelled,
  }) async {
    if (ids.isEmpty) return ExportResult.empty;

    if (options.toZip) {
      return _exportAsZipStreaming(db, ids, options, onProgress, onStatus, isCancelled);
    }
    return _exportToGallery(db, ids, options, onProgress, onStatus, isCancelled);
  }

  static Future<ExportResult> _exportToGallery(
    DatabaseService db,
    List<int> ids,
    ExportOptions options,
    void Function(int, int) onProgress,
    void Function(String, String) onStatus,
    bool Function() isCancelled,
  ) async {
    final ps = await PhotoManager.requestPermissionExtend();
    if (!ps.isAuth && !ps.hasAccess) {
      return const ExportResult(error: 'Нет доступа к галерее');
    }

    int ok = 0, failed = 0, processed = 0;
    final tempDir = await getTemporaryDirectory();

    for (final id in ids) {
      if (isCancelled()) break;
      String? tmpOut;
      try {
        final row = await _getRow(db, id);
        if (row == null) {
          failed++;
          continue;
        }
        final type = encryptionTypeFromKey(row['encryption_type'] as String?);
        final mediaType = row['media_type'] as String? ?? 'image';
        final stamp = DateTime.now().microsecondsSinceEpoch;
        
        onStatus('Подготовка', 'Файл $processed из ${ids.length}');

        tmpOut = p.join(
          tempDir.path,
          'exp_${id}_$stamp.${mediaType == 'video' ? 'mp4' : 'jpg'}',
        );

        await CryptoService.decryptFileTo(
          inputPath: row['file_path'] as String,
          outputPath: tmpOut,
          type: type,
        );

        if (mediaType == 'video') {
          await PhotoManager.editor.saveVideo(
            File(tmpOut),
            title: 'mediavault_${id}_$stamp.mp4',
          );
        } else if (options.compressImages) {
          final webp = await FlutterImageCompress.compressWithFile(
            tmpOut,
            quality: 95,
            format: CompressFormat.webp,
          );
          if (webp != null && webp.isNotEmpty) {
            await PhotoManager.editor.saveImage(
              webp,
              filename: 'mediavault_${id}_$stamp.webp',
            );
          } else {
            await PhotoManager.editor.saveImage(
              await File(tmpOut).readAsBytes(),
              filename: 'mediavault_${id}_$stamp.jpg',
            );
          }
        } else {
          await PhotoManager.editor.saveImage(
            await File(tmpOut).readAsBytes(),
            filename: 'mediavault_${id}_$stamp.jpg',
          );
        }
        ok++;
      } catch (_) {
        failed++;
      } finally {
        if (tmpOut != null) {
          try {
            final f = File(tmpOut);
            if (await f.exists()) await f.delete();
          } catch (_) {}
        }
      }
      processed++;
      onProgress(processed, ids.length);
    }
    return ExportResult(ok: ok, failed: failed);
  }

  static Future<ExportResult> _exportAsZipStreaming(
    DatabaseService db,
    List<int> ids,
    ExportOptions options,
    void Function(int, int) onProgress,
    void Function(String, String) onStatus,
    bool Function() isCancelled,
  ) async {
    final dir = await _saf.pickDirectory();
    if (dir == null) {
      return const ExportResult(error: 'Папка не выбрана');
    }

    final tempDir = await getTemporaryDirectory();
    final stamp = _stamp();
    final zipPath = p.join(tempDir.path, 'mv_export_$stamp.zip');
    
    final filesToZip = <Map<String, String>>[];
    int processed = 0;

    onStatus('Подготовка', 'Расшифровка файлов...');

    // 1. Расшифровываем все файлы во временную папку
    for (final id in ids) {
      if (isCancelled()) break;
      String? tmpDec;
      try {
        final row = await _getRow(db, id);
        if (row == null) continue;
        final type = encryptionTypeFromKey(row['encryption_type'] as String?);
        final mediaType = row['media_type'] as String? ?? 'image';

        tmpDec = p.join(tempDir.path, 'tmp_${id}_$stamp.dec');

        await CryptoService.decryptFileTo(
          inputPath: row['file_path'] as String,
          outputPath: tmpDec,
          type: type,
        );

        final entryName = 'mediavault_${id}_$stamp'
            '.${mediaType == 'video' ? 'mp4' : 'jpg'}';
            
        filesToZip.add({'path': tmpDec, 'name': entryName});
      } catch (_) {
        // skip
      }
      processed++;
      onProgress(processed, ids.length);
    }

    if (filesToZip.isEmpty) return const ExportResult(error: 'Нет файлов для архивации');

    onStatus('Сжатие', 'Упаковка файлов в ZIP (может занять время)...');

    // 2. Создаем ZIP в фоновом изоляте
    try {
      await compute(_createZipInIsolate, _ZipJob(filesToZip, zipPath));
    } catch (e) {
      return ExportResult(error: 'Ошибка ZIP: $e');
    } finally {
      // Удаляем временные расшифрованные файлы
      for (final f in filesToZip) {
        try {
          await File(f['path']!).delete();
        } catch (_) {}
      }
    }

    final fileName = options.encryptZip
        ? 'MediaVault_Backup_$stamp.mvault'
        : 'MediaVault_Backup_$stamp.zip';

    String finalPath = zipPath;
    
    // 3. Шифруем, если нужно
    if (options.encryptZip) {
      onStatus('Шифрование', 'Защита архива паролем...');
      final encPath = p.join(tempDir.path, 'mv_export_$stamp.enc');
      final okEnc = await CryptoService.encryptFileStreaming(
        inputPath: zipPath,
        outputPath: encPath,
      );
      if (!okEnc) {
        try { await File(zipPath).delete(); } catch (_) {}
        return const ExportResult(error: 'Ошибка шифрования архива');
      }
      finalPath = p.join(tempDir.path, fileName);
      await _prependMagic(encPath, finalPath, [0x4D, 0x56, 0x4C, 0x54]);
      try { await File(zipPath).delete(); } catch (_) {}
      try { await File(encPath).delete(); } catch (_) {}
    }

    onStatus('Сохранение', 'Запись в выбранную папку...');

    // 4. Потоковая запись в SAF
    try {
      await _saf.writeFileStream(
        dir.uri,
        fileName,
        options.encryptZip ? 'application/octet-stream' : 'application/zip',
        File(finalPath).openRead(),
      );
    } catch (e) {
      try { await File(finalPath).delete(); } catch (_) {}
      return ExportResult(error: 'Ошибка записи: $e');
    }

    try { await File(finalPath).delete(); } catch (_) {}

    return ExportResult(ok: filesToZip.length, outputPath: fileName);
  }

  static Future<void> _prependMagic(
    String src,
    String dst,
    List<int> magic,
  ) async {
    final out = await File(dst).open(mode: FileMode.write);
    try {
      await out.writeFrom(magic);
      final inp = await File(src).openRead();
      await for (final chunk in inp) {
        await out.writeFrom(chunk);
      }
    } finally {
      await out.close();
    }
  }

  static Future<Map<String, dynamic>?> _getRow(
    DatabaseService db,
    int id,
  ) async {
    final rows = await db.db.query(
      'media_items',
      columns: ['file_path', 'media_type', 'encryption_type', 'size_bytes'],
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    return rows.isEmpty ? null : rows.first;
  }

  static String _stamp() {
    final n = DateTime.now();
    return '${n.year}${n.month.toString().padLeft(2, '0')}${n.day.toString().padLeft(2, '0')}_'
        '${n.hour.toString().padLeft(2, '0')}${n.minute.toString().padLeft(2, '0')}${n.second.toString().padLeft(2, '0')}';
  }
}
