import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../core/app_theme_service.dart';
import '../../core/crypto_service.dart';
import '../../core/database_service.dart';
import '../../core/thumbnail_cache.dart';
import '../../core/ui_helpers.dart';

class MediaImporter {
  static Future<int> importMedia(
    BuildContext context,
    DatabaseService db, {
    int? albumId,
  }) async {
    final picker = ImagePicker();
    List<XFile> files;
    try {
      files = await picker.pickMultipleMedia();
    } catch (e) {
      if (context.mounted) {
        showAppSnackBar(context, 'Не удалось открыть галерею: $e',
            isError: true);
      }
      return 0;
    }
    if (!context.mounted) return 0;
    if (files.isEmpty) return 0;

    final result = await showDialog<int>(
      context: context,
      barrierDismissible: false,
      barrierColor: Colors.black.withValues(alpha: 0.7),
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
  int _failed = 0;
  bool _isDone = false;

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
        _failed++;
        debugPrint('Import error for ${file.path}: $e');
      }
    }

    if (mounted) {
      setState(() => _isDone = true);
      await Future.delayed(const Duration(milliseconds: 400));
      if (mounted) Navigator.of(context).pop(_success);
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

    return PopScope(
      canPop: false, // запрет системного back во время импорта
      child: Dialog(
        backgroundColor: Colors.transparent,
        elevation: 0,
        insetPadding: const EdgeInsets.symmetric(horizontal: 24),
        child: Container(
          padding: const EdgeInsets.all(32),
          decoration: BoxDecoration(
            color: const Color(0xFF1A1A1A).withValues(alpha: 0.95),
            borderRadius: BorderRadius.circular(32),
            border:
                Border.all(color: Colors.white.withValues(alpha: 0.10), width: 1.5),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                width: 100,
                height: 100,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    CircularProgressIndicator(
                      value: _isDone ? 1.0 : progress,
                      strokeWidth: 6,
                      backgroundColor: Colors.white.withValues(alpha: 0.05),
                      valueColor: const AlwaysStoppedAnimation<Color>(
                          Colors.tealAccent),
                    ),
                    Center(
                      child: AnimatedSwitcher(
                        duration: const Duration(milliseconds: 300),
                        child: _isDone
                            ? const Icon(Icons.check_circle,
                                color: Colors.tealAccent, size: 48)
                            : TweenAnimationBuilder<double>(
                                tween: Tween(begin: 0, end: 1),
                                duration: const Duration(seconds: 3),
                                builder: (context, val, child) {
                                  return Transform.rotate(
                                      angle: val * 2 * math.pi, child: child);
                                },
                                child: const Icon(Icons.sync,
                                    color: Colors.tealAccent, size: 48),
                              ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 32),
              Text(
                _isDone ? 'Готово' : 'Шифрование',
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 22,
                    fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 8),
              Text(
                _isDone
                    ? 'Импортировано: $_success${_failed > 0 ? ', ошибок: $_failed' : ''}'
                    : '$_processed из $total',
                style: const TextStyle(
                    color: Colors.tealAccent,
                    fontSize: 16,
                    fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 24),
              Text(
                _isDone ? 'Файлы надежно зашифрованы' : _currentFileName,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.6),
                    fontSize: 13,
                    height: 1.4),
              ),
              const SizedBox(height: 32),
              if (!_isDone)
                TextButton(
                  onPressed: _cancel,
                  style: TextButton.styleFrom(
                    foregroundColor: Colors.redAccent,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                      side: BorderSide(
                          color: Colors.redAccent.withValues(alpha: 0.5)),
                    ),
                  ),
                  child: const Text('Отменить импорт'),
                ),
            ],
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
  final Set<int>? selectedIds;
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

  bool get _selectionMode => selectedIds != null && selectedIds!.isNotEmpty;

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
                color: Theme.of(context)
                    .colorScheme
                    .onSurface
                    .withValues(alpha: 0.5),
                fontSize: 14),
          ),
        ),
      );
    }

    final cols = AppThemeService.instance.gridColumns;

    return GridView.builder(
      cacheExtent: 150,
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: cols,
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
          key: ValueKey(item['file_path']),
          child: GestureDetector(
            onTap: onTap,
            onLongPress: onLong,
            child: Stack(
              fit: StackFit.expand,
              children: [
                _EncryptedThumbnail(
                    filePath: item['file_path'], isVideo: isVideo),
                if (!_selectionMode && isFav)
                  const Positioned(
                    top: 4,
                    right: 4,
                    child: Icon(Icons.favorite,
                        color: Colors.pinkAccent, size: 18),
                  ),
                if (!_selectionMode && isVideo)
                  const Center(
                    child: Icon(Icons.play_circle_fill,
                        color: Colors.white70, size: 36),
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
                        border: Border.all(color: Colors.white, width: 1.5),
                      ),
                      child: isSelected
                          ? const Icon(Icons.check,
                              size: 14, color: Colors.black)
                          : null,
                    ),
                  ),
                if (_selectionMode && isSelected)
                  Positioned.fill(
                    child: IgnorePointer(
                      child: Container(
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(8),
                          border:
                              Border.all(color: Colors.tealAccent, width: 2),
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

// ... остальной код без изменений до класса _EncryptedThumbnail ...

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
    if (widget.isVideo) return;
    // Синхронно достаём кэш — если есть, сразу покажем без setState.
    final cached = ThumbnailCache.get(widget.filePath);
    if (cached != null) {
      _bytes = cached;
    } else {
      _load();
    }
  }

  @override
  void didUpdateWidget(covariant _EncryptedThumbnail oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.filePath != widget.filePath) {
      _bytes = null;
      _error = false;
      if (widget.isVideo) return;
      final cached = ThumbnailCache.get(widget.filePath);
      if (cached != null) {
        _bytes = cached;
      } else {
        _load();
      }
    }
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }

  Future<void> _load() async {
    if (widget.isVideo) return;
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
            color: Colors.black26, borderRadius: BorderRadius.circular(8)),
        child: const Center(
            child: Icon(Icons.videocam, color: Colors.white54, size: 32)),
      );
    }
    if (_error) {
      return Container(
        decoration: BoxDecoration(
            color: Colors.red.withValues(alpha: 0.2),
            borderRadius: BorderRadius.circular(8)),
        child: const Icon(Icons.broken_image, color: Colors.redAccent),
      );
    }
    if (_bytes == null) {
      return Container(
        decoration: BoxDecoration(
            color: Colors.white10, borderRadius: BorderRadius.circular(8)),
        child: const Center(
            child: CircularProgressIndicator(
                strokeWidth: 2, color: Colors.tealAccent)),
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
