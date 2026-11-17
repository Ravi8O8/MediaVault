import 'dart:io';

import 'package:path/path.dart' as p;

class FolderImportFile {
  final File file;
  final String relativeFolder; // '' если файл в корне выбранной папки
  final String mediaType;

  const FolderImportFile({
    required this.file,
    required this.relativeFolder,
    required this.mediaType,
  });
}

class FolderImportService {
  FolderImportService._();

  static const imageExts = {
    '.jpg', '.jpeg', '.png', '.webp', '.gif', '.bmp', '.heic', '.heif'
  };
  static const videoExts = {
    '.mp4', '.mov', '.avi', '.mkv', '.webm', '.3gp', '.m4v', '.flv'
  };

  /// Рекурсивно сканирует [rootPath], возвращает список медиа-файлов
  /// с относительным путём внутри выбранной папки.
  static Future<List<FolderImportFile>> scan(String rootPath) async {
    final dir = Directory(rootPath);
    if (!await dir.exists()) {
      throw Exception('Папка не найдена: $rootPath');
    }

    final result = <FolderImportFile>[];

    await for (final entity in dir.list(recursive: true, followLinks: false)) {
      if (entity is! File) continue;

      final ext = p.extension(entity.path).toLowerCase();
      final isImage = imageExts.contains(ext);
      final isVideo = videoExts.contains(ext);
      if (!isImage && !isVideo) continue;

      final relFile = p.relative(entity.path, from: rootPath);
      final relFolder = p.dirname(relFile);
      final normalizedFolder = relFolder == '.'
          ? ''
          : relFolder.replaceAll(r'\', '/');

      result.add(FolderImportFile(
        file: entity,
        relativeFolder: normalizedFolder,
        mediaType: isVideo ? 'video' : 'image',
      ));
    }

    result.sort((a, b) {
      final cmp = a.relativeFolder.compareTo(b.relativeFolder);
      if (cmp != 0) return cmp;
      return a.file.path.compareTo(b.file.path);
    });

    return result;
  }
}
