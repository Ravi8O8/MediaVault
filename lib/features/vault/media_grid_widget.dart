
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import '../../core/crypto_service.dart';
import '../../core/database_service.dart';

class MediaImporter {
  static Future<int> importMedia(
    BuildContext context,
    DatabaseService db, {
    int? albumId,
  }) async {
    final picker = ImagePicker();
    final List<XFile> files = await picker.pickMultipleMedia();
    if (!context.mounted) return 0; // Исправление линтера
    if (files.isEmpty) return 0;

    final total = files.length;
    final messenger = ScaffoldMessenger.of(context);

    messenger.showSnackBar(
      SnackBar(
        content: Text('Импорт 0/$total...'),
        duration: const Duration(minutes: 5),
      ),
    );

    int success = 0;

    for (int i = 0; i < files.length; i++) {
      final file = files[i];
      try {
        messenger.hideCurrentSnackBar();
        messenger.showSnackBar(
          SnackBar(
            content: Text('Импорт ${i + 1}/$total...'),
            duration: const Duration(minutes: 5),
          ),
        );

        final originalBytes = await File(file.path).readAsBytes();
        final encryptedBytes = await CryptoService.encryptData(originalBytes);

        final appDir = await getApplicationDocumentsDirectory();
        final vaultDir = Directory(p.join(appDir.path, 'vault_files'));
        if (!await vaultDir.exists()) await vaultDir.create(recursive: true);

        final fileName =
            '${DateTime.now().microsecondsSinceEpoch}_$i.enc';
        final encryptedFile = File(p.join(vaultDir.path, fileName));
        await encryptedFile.writeAsBytes(encryptedBytes, flush: true);

        final ext = p.extension(file.path).toLowerCase();
        const videoExts = {'.mp4', '.mov', '.avi', '.mkv', '.webm', '.3gp'};
        final mediaType = videoExts.contains(ext) ? 'video' : 'image';

        final newId =
            await db.insertMediaItem(encryptedFile.path, mediaType);
        if (albumId != null) {
          await db.moveMediaToAlbum(newId, albumId);
        }
        success++;
      } catch (e) {
        debugPrint('Import error for ${file.path}: $e');
      }
    }

    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(
      SnackBar(
        content: Text(
          success == total
              ? 'Импортировано файлов: $success'
              : 'Импортировано: $success из $total',
        ),
      ),
    );

    return success;
  }
}

class MediaGridWidget extends StatelessWidget {
  final List<Map<String, dynamic>> items;
  final ValueChanged<int> onItemTap;
  final ValueChanged<int> onItemLongPress;
  final String emptyMessage;

  const MediaGridWidget({
    super.key,
    required this.items,
    required this.onItemTap,
    required this.onItemLongPress,
    required this.emptyMessage,
  });

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Text(
            emptyMessage,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.5),
              fontSize: 14,
            ),
          ),
        ),
      );
    }
    return GridView.builder(
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        crossAxisSpacing: 8,
        mainAxisSpacing: 8,
      ),
      itemCount: items.length,
      itemBuilder: (context, index) {
        final item = items[index];
        final isFav = (item['is_favorite'] as int? ?? 0) == 1;
        final isVideo = item['media_type'] == 'video';
        return GestureDetector(
          onTap: () => onItemTap(index),
          onLongPress: () => onItemLongPress(index),
          child: Stack(
            fit: StackFit.expand,
            children: [
              _EncryptedThumbnail(
                filePath: item['file_path'],
                isVideo: isVideo,
              ),
              if (isFav)
                const Positioned(
                  top: 4,
                  right: 4,
                  child: Icon(
                    Icons.favorite,
                    color: Colors.pinkAccent,
                    size: 18,
                  ),
                ),
              if (isVideo)
                const Center(
                  child: Icon(
                    Icons.play_circle_fill,
                    color: Colors.white70,
                    size: 36,
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}

class _EncryptedThumbnail extends StatelessWidget {
  final String filePath;
  final bool isVideo;
  const _EncryptedThumbnail({required this.filePath, this.isVideo = false});

  @override
  Widget build(BuildContext context) {
    if (isVideo) {
      return Container(
        decoration: BoxDecoration(
          color: Colors.black26,
          borderRadius: BorderRadius.circular(8),
        ),
        child: const Center(
          child: Icon(Icons.videocam, color: Colors.white54, size: 32),
        ),
      );
    }
    return FutureBuilder<Uint8List>(
      future: _loadAndDecrypt(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return Container(
            decoration: BoxDecoration(
              color: Colors.white10,
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Center(
              child: CircularProgressIndicator(
                  strokeWidth: 2, color: Colors.tealAccent),
            ),
          );
        }
        if (snapshot.hasError || !snapshot.hasData) {
          return Container(
            decoration: BoxDecoration(
              color: Colors.red.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Icon(Icons.broken_image, color: Colors.redAccent),
          );
        }
        return ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: Image.memory(snapshot.data!, fit: BoxFit.cover),
        );
      },
    );
  }

  Future<Uint8List> _loadAndDecrypt() async {
    final file = File(filePath);
    final encryptedBytes = await file.readAsBytes();
    return await CryptoService.decryptData(encryptedBytes);
  }
}
