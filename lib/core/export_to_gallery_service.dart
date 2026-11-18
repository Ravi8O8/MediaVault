import 'dart:io';

import 'package:archive/archive_io.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:photo_manager/photo_manager.dart';
import 'package:share_plus/share_plus.dart';

import 'crypto_service.dart';
import 'database_service.dart';

class ExportResult {
  final int ok;
  final int failed;
  final String? error;
  final String? outputPath;
  const ExportResult({this.ok = 0, this.failed = 0, this.error, this.outputPath});
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
      return _exportAsZipStreaming(db, ids, options, onProgress, isCancelled);
    }
    return _exportToGallery(db, ids, options, onProgress, isCancelled);
  }

  static Future<ExportResult> _exportToGallery(
    DatabaseService db,
    List<int> ids,
    ExportOptions options,
    void Function(int, int) onProgress,
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
        tmpOut = p.join(tempDir.path,
            'exp_${id}_$stamp.${mediaType == 'video' ? 'mp4' : 'jpg'}');

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
    bool Function() isCancelled,
  ) async {
    final tempDir = await getTemporaryDirectory();
    final stamp = _stamp();
    final zipPath = p.join(tempDir.path, 'mv_export_$stamp.zip');
    final encoder = ZipFileEncoder();
    encoder.create(zipPath);

    int processed = 0;
    int ok = 0;

    try {
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

          await encoder.addFile(File(tmpDec), entryName);
          ok++;
        } catch (_) {
          // skip broken files
        } finally {
          if (tmpDec != null) {
            try {
              final f = File(tmpDec);
              if (await f.exists()) await f.delete();
            } catch (_) {}
          }
        }
        processed++;
        onProgress(processed, ids.length);
      }
    } finally {
      try {
        encoder.close();
      } catch (_) {}
    }

    final fileName = options.encryptZip
        ? 'MediaVault_Backup_$stamp.mvault'
        : 'MediaVault_Backup_$stamp.zip';

    String finalPath = zipPath;
    if (options.encryptZip) {
      final encPath = p.join(tempDir.path, 'mv_export_$stamp.enc');
      final okEnc = await CryptoService.encryptFileStreaming(
        inputPath: zipPath,
        outputPath: encPath,
      );
      if (!okEnc) {
        try {
          await File(zipPath).delete();
        } catch (_) {}
        return const ExportResult(error: 'Ошибка шифрования архива');
      }
      finalPath = p.join(tempDir.path, fileName);
      await _prependMagic(encPath, finalPath, [0x4D, 0x56, 0x4C, 0x54]);
      try {
        await File(zipPath).delete();
      } catch (_) {}
      try {
        await File(encPath).delete();
      } catch (_) {}
    }

    try {
      await Share.shareXFiles(
        [
          XFile(
            finalPath,
            mimeType: options.encryptZip
                ? 'application/octet-stream'
                : 'application/zip',
          )
        ],
        subject: 'MediaVault Backup',
      );
    } catch (_) {}

    return ExportResult(ok: ok, outputPath: finalPath);
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
