import 'dart:io';
import 'dart:typed_data';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import '../../core/crypto_service.dart';
import '../../core/database_service.dart';
import '../../core/thumbnail_cache.dart';

/// Состояние импорта для обновления UI диалога.
class ImportState {
  final int processed;
  final int total;
  final String currentFileName;

  ImportState({
    required this.processed,
    required this.total,
    required this.currentFileName,
  });
}

class MediaImporter {
  static Future<int> importMedia(
    BuildContext context,
    DatabaseService db, {
    int? albumId,
  }) async {
    final picker = ImagePicker();
    final List<XFile> files = await picker.pickMultipleMedia();
    
    if (!context.mounted) return 0;
    if (files.isEmpty) return 0;

    final total = files.length;
    final state = ValueNotifier<ImportState>(
      ImportState(processed: 0, total: total, currentFileName: ''),
    );
    bool isCancelled = false;

    // Показываем диалог
    showDialog(
      context: context,
      barrierDismissible: false,
      barrierColor: Colors.black.withValues(alpha: 0.6),
      builder: (dialogContext) => ImportProgressDialog(
        state: state,
        onCancel: () {
          isCancelled = true;
          Navigator.pop(dialogContext);
        },
      ),
    );

    int success = 0;

    for (int i = 0; i < files.length; i++) {
      if (isCancelled) break; // Прерываем цикл, если нажали "Отмена"

      final file = files[i];
      state.value = ImportState(
        processed: i,
        total: total,
        currentFileName: p.basename(file.path),
      );

      try {
        final originalBytes = await File(file.path).readAsBytes();
        final encryptedBytes = await CryptoService.encryptData(originalBytes);

        final appDir = await getApplicationDocumentsDirectory();
        final vaultDir = Directory(p.join(appDir.path, 'vault_files'));
        if (!await vaultDir.exists()) await vaultDir.create(recursive: true);

        final fileName = '${DateTime.now().microsecondsSinceEpoch}_$i.enc';
        final encryptedFile = File(p.join(vaultDir.path, fileName));
        await encryptedFile.writeAsBytes(encryptedBytes, flush: true);

        final ext = p.extension(file.path).toLowerCase();
        const videoExts = {'.mp4', '.mov', '.avi', '.mkv', '.webm', '.3gp'};
        final mediaType = videoExts.contains(ext) ? 'video' : 'image';

        final newId = await db.insertMediaItem(encryptedFile.path, mediaType);
        if (albumId != null) {
          await db.moveMediaToAlbum(newId, albumId);
        }
        success++;
      } catch (e) {
        debugPrint('Import error for ${file.path}: $e');
      }
    }

    state.value = ImportState(
      processed: files.length,
      total: total,
      currentFileName: '',
    );

    // Закрываем диалог, если он еще открыт
    if (context.mounted) {
      Navigator.of(context, rootNavigator: true).pop();
    }

    return success;
  }
}

/// Красивое окно прогресса с размытием (Liquid Glass style).
class ImportProgressDialog extends StatelessWidget {
  final ValueNotifier<ImportState> state;
  final VoidCallback onCancel;

  const ImportProgressDialog({
    super.key,
    required this.state,
    required this.onCancel,
  });

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      elevation: 0,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(24),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
          child: Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: const Color(0xFF232526).withValues(alpha: 0.85),
              borderRadius: BorderRadius.circular(24),
              border: Border.all(
                color: Colors.white.withValues(alpha: 0.15),
                width: 1.5,
              ),
            ),
            child: ValueListenableBuilder<ImportState>(
              valueListenable: state,
              builder: (context, value, child) {
                final progress = value.total > 0
                    ? value.processed / value.total
                    : 0.0;

                return Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Анимированная иконка
                    TweenAnimationBuilder<double>(
                      tween: Tween(begin: 0, end: 1),
                      duration: const Duration(seconds: 2),
                      builder: (context, val, _) {
                        return Transform.rotate(
                          angle: val * 2 * 3.14159,
                          child: const Icon(
                            Icons.sync,
                            color: Colors.tealAccent,
                            size: 48,
                          ),
                        );
                      },
                    ),
                    const SizedBox(height: 20),
                    const Text(
                      'Шифрование файлов',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '${value.processed} из ${value.total}',
                      style: const TextStyle(
                        color: Colors.tealAccent,
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 16),
                    // Прогресс-бар
                    ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: LinearProgressIndicator(
                        value: progress,
                        minHeight: 6,
                        backgroundColor: Colors.white24,
                        valueColor: const AlwaysStoppedAnimation<Color>(
                          Colors.tealAccent,
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    // Имя текущего файла
                    SizedBox(
                      height: 20,
                      child: Text(
                        value.currentFileName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          color: Colors.white54,
                          fontSize: 12,
                        ),
                      ),
                    ),
                    const SizedBox(height: 24),
                    // Кнопка отмены
                    TextButton(
                      onPressed: onCancel,
                      style: TextButton.styleFrom(
                        foregroundColor: Colors.redAccent,
                        padding: const EdgeInsets.symmetric(
                            horizontal: 24, vertical: 12),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                          side: const BorderSide(color: Colors.redAccent),
                        ),
                      ),
                      child: const Text('Отменить импорт'),
                    ),
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );
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

class _EncryptedThumbnail extends StatefulWidget {
  final String filePath;
  final bool isVideo;
  const _EncryptedThumbnail({required this.filePath, this.isVideo = false});

  @override
  State<_EncryptedThumbnail> createState() => _EncryptedThumbnailState();
}

class _EncryptedThumbnailState extends State<_EncryptedThumbnail> {
  Uint8List? _bytes;
  bool _error = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (widget.isVideo) return;

    final cached = ThumbnailCache.get(widget.filePath);
    if (cached != null) {
      if (mounted) setState(() => _bytes = cached);
      return;
    }

    try {
      final decrypted = await ThumbnailCache.load(widget.filePath);
      if (mounted) setState(() => _bytes = decrypted);
    } catch (e) {
      if (mounted) setState(() => _error = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.isVideo) {
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
    if (_error) {
      return Container(
        decoration: BoxDecoration(
          color: Colors.red.withValues(alpha: 0.2),
          borderRadius: BorderRadius.circular(8),
        ),
        child: const Icon(Icons.broken_image, color: Colors.redAccent),
      );
    }
    if (_bytes == null) {
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
    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: Image.memory(
        _bytes!,
        fit: BoxFit.cover,
        cacheWidth: 300,
        gaplessPlayback: true,
      ),
    );
  }
}
