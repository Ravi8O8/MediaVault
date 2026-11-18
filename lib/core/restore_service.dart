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

    final appDir = await getApplicationDocumentsDirectory();
    final vaultDir = Directory(p.join(appDir.path, 'vault_files'));
    if (!await vaultDir.exists()) await vaultDir.create(recursive: true);

    // ── STREAMING UNZIP: открываем ZIP как InputFileStream, не в RAM ──
    // archive 4.x: ZipDecoder().decodeStream(InputStream)
    Archive archive;
    if (ext == '.mvault') {
      // Расшифровываем .mvault во временный ZIP потоково
      final tmpZip = p.join(
          (await getTemporaryDirectory()).path,
          'restore_${DateTime.now().microsecondsSinceEpoch}.zip');
      final ok = await CryptoService.decryptFileStreaming(
        inputPath: file.path,
        outputPath: tmpZip,
      );
      if (!ok) return {'ok': 0, 'err': -3};
      archive = ZipDecoder().decodeStream(InputFileStream(tmpZip));
    } else {
      archive = ZipDecoder().decodeStream(InputFileStream(file.path));
    }

    int ok = 0, err = 0;
    int i = 0;
    final total = archive.files.length;

    for (final entry in archive) {
      i++;
      if (!entry.isFile) continue;
      try {
        final data = entry.content; // InputStream, не List<int>
        if (data == null) continue;

        final tmpDec = p.join(
            (await getTemporaryDirectory()).path,
            'restore_${DateTime.now().microsecondsSinceEpoch}_${i}.tmp');
        final out = File(tmpDec).openWrite();
        // Читаем поток и пишем на диск
        final input = data as InputStream;
        await for (final chunk in input) {
          out.add(chunk);
        }
        await out.flush();
        await out.close();

        final encName =
            '${DateTime.now().microsecondsSinceEpoch}_restored.enc';
        final encFile = File(p.join(vaultDir.path, encName));
        final okEnc = await CryptoService.encryptFileStreaming(
          inputPath: tmpDec,
          outputPath: encFile.path,
        );
        if (!okEnc) throw Exception('encrypt failed');

        final fext = p.extension(entry.name).toLowerCase();
        final isVideo = ['.mp4', '.mov', '.avi', '.mkv'].contains(fext);

        final id = await db.insertMediaItem(
          encFile.path,
          isVideo ? 'video' : 'image',
          encryptionType: VaultEncryptionType.aesCtr.key,
          sizeBytes: await File(tmpDec).length(),
        );
        await ThumbnailCache.generateAndSaveForMedia(
            id, encFile.path, isVideo, VaultEncryptionType.aesCtr);
        try {
          await File(tmpDec).delete();
        } catch (_) {}
        ok++;
      } catch (_) {
        err++;
      }
      onProgress(i, total);
    }
    return {'ok': ok, 'err': err};
  }
}
