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
    // FileType.any — показываем ВСЕ файлы, чтобы .mvault не скрывался
    final result = await FilePicker.platform.pickFiles(
      type: FileType.any,
    );
    if (result == null || result.files.single.path == null) {
      return {'ok': 0, 'err': -1};
    }

    final file = File(result.files.single.path!);
    final ext = p.extension(file.path).toLowerCase();

    if (ext != '.zip' && ext != '.mvault') {
      return {'ok': 0, 'err': -2};
    }

    final bytes = await file.readAsBytes();
    Uint8List zipData = bytes;

    if (ext == '.mvault') {
      if (bytes.length < 5 ||
          bytes[0] != 0x4D ||
          bytes[1] != 0x56 ||
          bytes[2] != 0x4C ||
          bytes[3] != 0x54) {
        return {'ok': 0, 'err': -2};
      }
      final enc = bytes.sublist(4);
      try {
        zipData = await CryptoService.decryptData(enc, type: VaultEncryptionType.aesCbc);
      } catch (_) {
        try {
          zipData = await CryptoService.decryptData(enc, type: VaultEncryptionType.aesCtr);
        } catch (_) {
          return {'ok': 0, 'err': -3};
        }
      }
    }

    final archive = ZipDecoder().decodeBytes(zipData);
    int ok = 0;
    int err = 0;
    final appDir = await getApplicationDocumentsDirectory();
    final vaultDir = Directory(p.join(appDir.path, 'vault_files'));
    if (!await vaultDir.exists()) await vaultDir.create(recursive: true);

    int i = 0;
    final total = archive.files.length;

    for (final file in archive) {
      i++;
      if (file.isFile) {
        try {
          final data = Uint8List.fromList(file.content as List<int>);
          final encrypted = await CryptoService.encryptData(data);
          final fileName = '${DateTime.now().microsecondsSinceEpoch}_restored.enc';
          final encFile = File(p.join(vaultDir.path, fileName));
          await encFile.writeAsBytes(encrypted, flush: true);

          final fext = p.extension(file.name).toLowerCase();
          final isVideo = ['.mp4', '.mov', '.avi', '.mkv'].contains(fext);

          final id = await db.insertMediaItem(
            encFile.path,
            isVideo ? 'video' : 'image',
            encryptionType: VaultEncryptionType.aesCbc.key,
            sizeBytes: data.length,
          );

          await ThumbnailCache.generateAndSaveForMedia(id, encFile.path, isVideo, VaultEncryptionType.aesCbc);
          ok++;
        } catch (_) {
          err++;
        }
      }
      onProgress(i, total);
    }

    return {'ok': ok, 'err': err};
  }
}
