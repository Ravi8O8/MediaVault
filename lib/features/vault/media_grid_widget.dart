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

    final result = await showDialog<int>(
      context: context,
      barrierDismissible: false,
      barrierColor: Colors.black.withValues(alpha: 0.6),
      builder: (dialogContext) => ImportProgressDialog(
        files: files,
        db: db,
        albumId: albumId,
      ),
    );

    return result ?? 0;
  }
}

class ImportProgressDialog extends StatefulWidget {
  final List<XFile> files;
  final DatabaseService db;
  final int? albumId;

  const ImportProgressDialog({
    super.key,
    required this.files,
    required this.db,
    required this.albumId,
  });

  @override
  State<ImportProgressDialog> createState() => _ImportProgressDialogState();
}

class _ImportProgressDialogState extends State<ImportProgressDialog> {
  int _processed = 0;
  String _currentFileName = '';
  bool _isCancelled = false;
  int _success = 0;

  @override
  void initState() {
    super.initState();
    _startImport();
  }

  Future<void> _startImport() async {
    final total = widget.files.length;

    for (int i = 0; i < total; i++) {
      if (_isCancelled) break;

      final file = widget.files[i];
      if (mounted) {
        setState(() {
          _processed = i;
          _currentFileName = p.basename(file.path);
        });
      }

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

        final newId =
            await widget.db.insertMediaItem(encryptedFile.path, mediaType);
        if (widget.albumId != null) {
          await widget.db.moveMediaToAlbum(newId, widget.albumId!);
        }
        _success++;
      } catch (e) {
        debugPrint('Import error for ${file.path}: $e');
      }
    }

    if (mounted) {
      Navigator.of(context).pop(_success);
    }
  }

  void _cancel() {
    setState(() => _isCancelled = true);
    Navigator.of(context).pop(_success);
  }

  @override
  Widget build(BuildContext context) {
    final total = widget.files.length;
    final progress = total > 0 ? _processed / total : 0.0;

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
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
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
                  '$_processed из $total',
                  style: const TextStyle(
                    color: Colors.tealAccent,
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 16),
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
                SizedBox(
                  height: 20,
                  child: Text(
                    _currentFileName,
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
                TextButton(
                  onPressed: _cancel,
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

  /// Если задано И непусто — включается режим выделения.
  final Set<int>? selectedIds;

  /// Вызывается при тапе/долгом тапе в режиме выделения.
  final ValueChanged<int>? onSelectionToggle;

  const MediaGridWidget({
    super.key,
    required this.items,
    required this.onItemTap,
    required this.onItemLongPress,
    required this.emptyMessage,
    this.selectedIds,
    this.onSelectionToggle,
  });

  bool get _selectionMode =>
      selectedIds != null && selectedIds!.isNotEmpty;

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
      cacheExtent: 150,
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        crossAxisSpacing: 8,
        mainAxisSpacing: 8,
      ),
      itemCount: items.length,
      itemBuilder: (context, index) {
        final item = items[index];
        final id = item['id'] as int;
        final isFav = (item['is_favorite'] as int? ?? 0) == 1;
        final isVideo = item['media_type'] == 'video';
        final isSelected = selectedIds?.contains(id) ?? false;

        final VoidCallback onTap = _selectionMode
            ? () => onSelectionToggle?.call(index)
            : () => onItemTap(index);
        final VoidCallback onLong = _selectionMode
            ? () => onSelectionToggle?.call(index)
            : () => onItemLongPress(index);

        return RepaintBoundary(
          // КРИТИЧЕСКИ ВАЖНО: ValueKey заставляет Flutter пересоздать
          // виджет, если на этом месте оказался другой файл.
          key: ValueKey(item['file_path']),
          child: GestureDetector(
            onTap: onTap,
            onLongPress: onLong,
            child: Stack(
              fit: StackFit.expand,
              children: [
                _EncryptedThumbnail(
                  filePath: item['file_path'],
                  isVideo: isVideo,
                ),
                if (!_selectionMode && isFav)
                  const Positioned(
                    top: 4,
                    right: 4,
                    child: Icon(
                      Icons.favorite,
                      color: Colors.pinkAccent,
                      size: 18,
                    ),
                  ),
                if (!_selectionMode && isVideo)
                  const Center(
                    child: Icon(
                      Icons.play_circle_fill,
                      color: Colors.white70,
                      size: 36,
                    ),
                  ),
                if (_selectionMode)
                  Positioned(
                    top: 4,
                    right: 4,
                    child: Container(
                      width: 22,
                      height: 22,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: isSelected
                            ? Colors.tealAccent
                            : Colors.black.withValues(alpha: 0.5),
                        border: Border.all(
                          color: Colors.white,
                          width: 1.5,
                        ),
                      ),
                      child: isSelected
                          ? const Icon(
                              Icons.check,
                              size: 14,
                              color: Colors.black,
                            )
                          : null,
                    ),
                  ),
                if (_selectionMode && isSelected)
                  Positioned.fill(
                    child: IgnorePointer(
                      child: Container(
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: Colors.tealAccent,
                            width: 2,
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
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
  bool _disposed = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant _EncryptedThumbnail oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Дополнительная страховка: если путь поменялся, сбрасываем и грузим заново
    if (oldWidget.filePath != widget.filePath) {
      _bytes = null;
      _error = false;
      _load();
    }
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }

  Future<void> _load() async {
    if (widget.isVideo) return;

    final cached = ThumbnailCache.get(widget.filePath);
    if (cached != null) {
      if (mounted) setState(() => _bytes = cached);
      return;
    }

    try {
      final result = await ThumbnailCache.load(
        widget.filePath,
        isCancelled: () => _disposed || !mounted,
      );
      if (!_disposed && mounted && result != null) {
        setState(() => _bytes = result);
      }
    } catch (e) {
      if (!_disposed && mounted) setState(() => _error = true);
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
        gaplessPlayback: true,
      ),
    );
  }
}
