import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive_io.dart';
import 'package:file_picker/file_picker.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'crypto_service.dart';
import 'database_service.dart';
import 'thumbnail_cache.dart';

class RestoreService {
  static Future<Map<String, int>> restoreFromArchive(
    DatabaseService db, {
    required void Function(int done, int total) onProgress,
  }) async {
    final result = await FilePicker.platform.pickFiles(type: FileType.any);
    if (result == null || result.files.single.path == null) {
      return {'ok': 0, 'err': -1};
    }

    final file = File(result.files.single.path!);
    final ext = p.extension(file.path).toLowerCase();
    if (ext != '.zip' && ext != '.mvault') return {'ok': 0, 'err': -2};

    final tempDir = await getTemporaryDirectory();
    String zipPath = file.path;

    // 1) .mvault → расшифровываем в temp .zip потоково
    if (ext == '.mvault') {
      final raf = await file.open();
      final magic = Uint8List(4);
      final read = await raf.readInto(magic);
      await raf.close();
      if (read < 4 ||
          magic[0] != 0x4D ||
          magic[1] != 0x56 ||
          magic[2] != 0x4C ||
          magic[3] != 0x54) {
        return {'ok': 0, 'err': -2};
      }

      final bodyPath = p.join(tempDir.path,
          'restore_${DateTime.now().microsecondsSinceEpoch}.body');
      await _skipFirstBytes(file.path, bodyPath, 4);

      final zipDecPath = p.join(tempDir.path,
          'restore_${DateTime.now().microsecondsSinceEpoch}.zip');
      final ok = await CryptoService.decryptFileStreaming(
        inputPath: bodyPath,
        outputPath: zipDecPath,
      );
      try {
        await File(bodyPath).delete();
      } catch (_) {}
      if (!ok) return {'ok': 0, 'err': -3};
      zipPath = zipDecPath;
    }

    // 2) Streaming unzip
    int ok = 0, err = 0, i = 0;

    try {
      final inputStream = InputFileStream(zipPath);
      final archive = ZipDecoder().decodeStream(inputStream);
      final total = archive.files.length;
      final vaultDir = await _ensureVaultDir();

      for (final entry in archive) {
        i++;
        if (!entry.isFile) {
          onProgress(i, total);
          continue;
        }

        String? tmpDec;
        try {
          tmpDec = p.join(tempDir.path,
              'restore_${DateTime.now().microsecondsSinceEpoch}_$i.tmp');

          final out = File(tmpDec).openWrite();
          try {
            // archive 4.x: для потокового чтения используем getContent()
            final content = entry.getContent();
            if (content != null) {
              final buf = Uint8List(64 * 1024);
              while (true) {
                final chunk = content.readBytes(buf.length);
                if (chunk == null || chunk.isEmpty) break;
                out.add(chunk);
              }
            } else {
              // fallback для небольших файлов
              final bytes = entry.readBytes();
              if (bytes != null) out.add(bytes);
            }
            await out.flush();
          } finally {
            await out.close();
          }

          final sizeBytes = await File(tmpDec).length();
          final encName =
              '${DateTime.now().microsecondsSinceEpoch}_restored_$i.enc';
          final encFile = File(p.join(vaultDir.path, encName));

          final okEnc = await CryptoService.encryptFileStreaming(
            inputPath: tmpDec,
            outputPath: encFile.path,
          );
          if (!okEnc) throw Exception('encrypt failed');

          final fext = p.extension(entry.name).toLowerCase();
          final isVideo =
              ['.mp4', '.mov', '.avi', '.mkv', '.webm'].contains(fext);

          final id = await db.insertMediaItem(
            encFile.path,
            isVideo ? 'video' : 'image',
            encryptionType: VaultEncryptionType.aesCtr.key,
            sizeBytes: sizeBytes,
          );

          await ThumbnailCache.generateAndSaveForMedia(
            id,
            encFile.path,
            isVideo,
            VaultEncryptionType.aesCtr,
          );
          ok++;
        } catch (_) {
          err++;
        } finally {
          if (tmpDec != null) {
            try {
              final f = File(tmpDec);
              if (await f.exists()) await f.delete();
            } catch (_) {}
          }
        }

        onProgress(i, total);
      }

      try {
        inputStream.closeSync();
      } catch (_) {}
    } catch (_) {
      err++;
    } finally {
      if (ext == '.mvault' && zipPath != file.path) {
        try {
          await File(zipPath).delete();
        } catch (_) {}
      }
    }

    return {'ok': ok, 'err': err};
  }

  static Future<Directory> _ensureVaultDir() async {
    final appDir = await getApplicationDocumentsDirectory();
    final vaultDir = Directory(p.join(appDir.path, 'vault_files'));
    if (!await vaultDir.exists()) await vaultDir.create(recursive: true);
    return vaultDir;
  }

  static Future<void> _skipFirstBytes(
    String src,
    String dst,
    int skip,
  ) async {
    final raf = await File(src).open();
    try {
      await raf.setPosition(skip);
      final out = await File(dst).open(mode: FileMode.write);
      try {
        final buf = Uint8List(64 * 1024);
        int read;
        while ((read = await raf.readInto(buf)) > 0) {
          await out.writeFrom(buf, 0, read);
        }
      } finally {
        await out.close();
      }
    } finally {
      await raf.close();
    }
  }
}
