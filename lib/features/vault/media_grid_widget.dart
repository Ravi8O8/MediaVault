import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../core/app_theme_service.dart';
import '../../core/crypto_service.dart';
import '../../core/database_service.dart';
import '../../core/folder_import_service.dart';
import '../../core/thumbnail_cache.dart';
import '../../core/ui_helpers.dart';

class ImportTaskItem {
  final String sourcePath;
  final String basename;
  final String? folderPath;
  final String mediaType;
  final int? albumId;

  const ImportTaskItem({
    required this.sourcePath,
    required this.basename,
    required this.mediaType,
    this.folderPath,
    this.albumId,
  });
}

class MediaImporter {
  static Future<int> importFiles(
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
        showAppSnackBar(context, 'Не удалось открыть галерею: $e', isError: true);
      }
      return 0;
    }
    if (!context.mounted || files.isEmpty) return 0;

    final tasks = files.map((f) {
      final ext = p.extension(f.path).toLowerCase();
      final isVideo = FolderImportService.videoExts.contains(ext);
      return ImportTaskItem(
        sourcePath: f.path,
        basename: p.basename(f.path),
        mediaType: isVideo ? 'video' : 'image',
        albumId: albumId,
      );
    }).toList();

    return _runImportDialog(context, db, tasks);
  }

  static Future<int> importFolder(
    BuildContext context,
    DatabaseService db, {
    int? albumId,
  }) async {
    if (!Platform.isAndroid) {
      if (context.mounted) {
        showAppSnackBar(context, 'Импорт папок доступен только на Android',
            isError: true);
      }
      return 0;
    }

    final granted = await _ensureStoragePermission();
    if (!granted) {
      if (context.mounted) {
        showAppSnackBar(context,
            'Нужен доступ к файлам. Разрешите в настройках приложения.',
            isError: true);
      }
      return 0;
    }
    if (!context.mounted) return 0;

    String? dirPath;
    try {
      dirPath = await FilePicker.platform.getDirectoryPath(
        dialogTitle: 'Выберите папку для импорта',
      );
    } catch (e) {
      if (context.mounted) {
        showAppSnackBar(context, 'Ошибка выбора папки: $e', isError: true);
      }
      return 0;
    }
    if (dirPath == null || dirPath.isEmpty) return 0;
    if (!dirPath.startsWith('/')) {
      if (context.mounted) {
        showAppSnackBar(context,
            'Эта папка недоступна для чтения. Выберите папку во внутреннем хранилище.',
            isError: true);
      }
      return 0;
    }

    List<FolderImportFile> files;
    try {
      files = await FolderImportService.scan(dirPath);
    } catch (e) {
      if (context.mounted) {
        showAppSnackBar(context, 'Ошибка сканирования: $e', isError: true);
      }
      return 0;
    }

    if (files.isEmpty) {
      if (context.mounted) {
        showAppSnackBar(context, 'В выбранной папке нет медиафайлов');
      }
      return 0;
    }

    if (!context.mounted) return 0;

    final tasks = files.map((f) {
      return ImportTaskItem(
        sourcePath: f.file.path,
        basename: p.basename(f.file.path),
        mediaType: f.mediaType,
        folderPath: f.relativeFolder,
        albumId: albumId,
      );
    }).toList();

    return _runImportDialog(context, db, tasks);
  }

  static Future<int> _runImportDialog(
    BuildContext context,
    DatabaseService db,
    List<ImportTaskItem> tasks,
  ) async {
    if (tasks.isEmpty) return 0;
    final result = await showDialog<int>(
      context: context,
      barrierDismissible: false,
      barrierColor: Colors.black.withValues(alpha: 0.75),
      builder: (_) => ImportProgressDialog(tasks: tasks, db: db),
    );
    return result ?? 0;
  }

  static Future<bool> _ensureStoragePermission() async {
    final storage = await Permission.storage.status;
    if (storage.isGranted) return true;
    final manage = await Permission.manageExternalStorage.status;
    if (manage.isGranted) return true;

    final r1 = await Permission.storage.request();
    if (r1.isGranted) return true;
    final r2 = await Permission.manageExternalStorage.request();
    return r2.isGranted;
  }
}

class ImportProgressDialog extends StatefulWidget {
  final List<ImportTaskItem> tasks;
  final DatabaseService db;

  const ImportProgressDialog({
    super.key,
    required this.tasks,
    required this.db,
  });

  @override
  State<ImportProgressDialog> createState() => _ImportProgressDialogState();
}

class _ImportProgressDialogState extends State<ImportProgressDialog>
    with TickerProviderStateMixin {
  int _processed = 0;
  int _success = 0;
  int _failed = 0;
  bool _isCancelled = false;
  bool _isDone = false;
  String _currentName = '';
  String _currentPath = '';
  final List<String> _recentCompleted = [];

  late final AnimationController _pulseController;
  late final Animation<double> _pulseAnimation;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1100),
    )..repeat(reverse: true);
    _pulseAnimation = Tween<double>(begin: 0.96, end: 1.04).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );
    _startImport();
  }

  @override
  void dispose() {
    _isCancelled = true;
    _pulseController.dispose();
    super.dispose();
  }

  Future<void> _startImport() async {
    if (!mounted) return;
    final total = widget.tasks.length;

    if (total == 0) {
      if (mounted) Navigator.of(context).pop(0);
      return;
    }

    for (int i = 0; i < total; i++) {
      if (_isCancelled || !mounted) break;

      final task = widget.tasks[i];
      final displayPath = task.folderPath == null || task.folderPath!.isEmpty
          ? task.basename
          : '${task.folderPath}/${task.basename}';

      setState(() {
        _processed = i;
        _currentName = task.basename;
        _currentPath = task.folderPath ?? '';
      });

      try {
        final originalBytes = await File(task.sourcePath).readAsBytes();
        final encryptedBytes = await CryptoService.encryptData(originalBytes);

        final appDir = await getApplicationDocumentsDirectory();
        final vaultDir = Directory(p.join(appDir.path, 'vault_files'));
        if (!await vaultDir.exists()) await vaultDir.create(recursive: true);

        final fileName = '${DateTime.now().microsecondsSinceEpoch}_$i.enc';
        final encryptedFile = File(p.join(vaultDir.path, fileName));
        await encryptedFile.writeAsBytes(encryptedBytes, flush: true);

        await widget.db.insertMediaItem(
          encryptedFile.path,
          task.mediaType,
          folderPath: task.folderPath,
          albumId: task.albumId,
        );
        _success++;

        if (!mounted) return;
        setState(() {
          _recentCompleted.insert(0, displayPath);
          if (_recentCompleted.length > 4) _recentCompleted.removeLast();
        });
      } catch (e) {
        _failed++;
        debugPrint('Import error for ${task.sourcePath}: $e');
      }
    }

    if (!mounted) return;

    if (_pulseController.isAnimating) {
      _pulseController.stop();
    }

    setState(() => _isDone = true);
    await Future.delayed(const Duration(milliseconds: 700));
    if (mounted) Navigator.of(context).pop(_success);
  }

  void _cancel() {
    _isCancelled = true;
    if (mounted) Navigator.of(context).pop(_success);
  }

  @override
  Widget build(BuildContext context) {
    final total = widget.tasks.length;
    final progress = total > 0 ? _processed / total : 0.0;
    final percent = (progress * 100).round();
    final hasFolders = widget.tasks.any((t) =>
        t.folderPath != null && t.folderPath!.isNotEmpty);

    return PopScope(
      canPop: false,
      child: Dialog(
        backgroundColor: Colors.transparent,
        elevation: 0,
        insetPadding: const EdgeInsets.symmetric(horizontal: 20),
        child: Container(
          constraints: const BoxConstraints(maxWidth: 440),
          padding: const EdgeInsets.fromLTRB(24, 28, 24, 22),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0xFF1B2A38), Color(0xFF0E161F)],
            ),
            borderRadius: BorderRadius.circular(32),
            border: Border.all(
              color: Colors.tealAccent.withValues(alpha: 0.30),
              width: 1.5,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.tealAccent.withValues(alpha: 0.18),
                blurRadius: 48,
                spreadRadius: -6,
              ),
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.6),
                blurRadius: 32,
                spreadRadius: 4,
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _buildRing(progress, percent, total),
              const SizedBox(height: 22),
              Text(
                _isDone
                    ? 'Готово'
                    : hasFolders
                        ? 'Импорт папки'
                        : 'Импорт файлов',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 22,
                  fontWeight: FontWeight.w700,
                  letterSpacing: -0.5,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                _isDone
                    ? 'Импортировано: $_success${_failed > 0 ? ' • ошибок: $_failed' : ''}'
                    : 'Файлы надёжно шифруются',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: _isDone
                      ? Colors.tealAccent
                      : Colors.white.withValues(alpha: 0.55),
                  fontSize: 14,
                ),
              ),
              const SizedBox(height: 20),
              if (!_isDone) _buildCurrentItem(),
              if (!_isDone && _recentCompleted.isNotEmpty) ...[
                const SizedBox(height: 14),
                _buildRecentList(),
              ],
              const SizedBox(height: 22),
              if (!_isDone) _buildCancelButton(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildRing(double progress, int percent, int total) {
    return SizedBox(
      width: 144,
      height: 144,
      child: Stack(
        fit: StackFit.expand,
        children: [
          SizedBox.expand(
            child: CircularProgressIndicator(
              value: 1,
              strokeWidth: 8,
              valueColor: AlwaysStoppedAnimation(
                Colors.white.withValues(alpha: 0.06),
              ),
            ),
          ),
          SizedBox.expand(
            child: CircularProgressIndicator(
              value: _isDone ? 1.0 : progress,
              strokeWidth: 8,
              strokeCap: StrokeCap.round,
              valueColor:
                  const AlwaysStoppedAnimation<Color>(Colors.tealAccent),
            ),
          ),
          Center(
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 300),
              child: _isDone
                  ? const Icon(
                      Icons.check_circle_rounded,
                      key: ValueKey('done'),
                      color: Colors.tealAccent,
                      size: 62,
                    )
                  : Column(
                      key: const ValueKey('progress'),
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        ScaleTransition(
                          scale: _pulseAnimation,
                          child: Text(
                            '$percent%',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 36,
                              fontWeight: FontWeight.w800,
                              letterSpacing: -1.2,
                            ),
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '$_processed / $total',
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.5),
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCurrentItem() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
      ),
      child: Row(
        children: [
          Icon(
            Icons.insert_drive_file_outlined,
            color: Colors.tealAccent.withValues(alpha: 0.85),
            size: 18,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _currentName.isEmpty ? 'Подготовка…' : _currentName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.85),
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                if (_currentPath.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(
                      _currentPath,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: Colors.tealAccent.withValues(alpha: 0.7),
                        fontSize: 11,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRecentList() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: _recentCompleted.take(3).map((name) {
        return Padding(
          padding: const EdgeInsets.only(bottom: 6),
          child: Row(
            children: [
              const Icon(Icons.check_circle,
                  color: Colors.tealAccent, size: 14),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.35),
                    fontSize: 11,
                  ),
                ),
              ),
            ],
          ),
        );
      }).toList(),
    );
  }

  Widget _buildCancelButton() {
    return SizedBox(
      width: double.infinity,
      child: TextButton(
        onPressed: _cancel,
        style: TextButton.styleFrom(
          foregroundColor: Colors.redAccent,
          padding: const EdgeInsets.symmetric(vertical: 14),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: BorderSide(color: Colors.redAccent.withValues(alpha: 0.4)),
          ),
        ),
        child: const Text(
          'Отменить импорт',
          style: TextStyle(fontWeight: FontWeight.w600),
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
  final bool showFolderBadge;

  const MediaGridWidget({
    super.key,
    required this.items,
    required this.onItemTap,
    required this.onItemLongPress,
    required this.emptyMessage,
    this.selectedIds,
    this.onSelectionToggle,
    this.showFolderBadge = false,
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
      cacheExtent: 400,
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
        final folderPath = item['folder_path'] as String?;

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
                if (!_selectionMode &&
                    showFolderBadge &&
                    folderPath != null &&
                    folderPath.isNotEmpty)
                  Positioned(
                    left: 4,
                    right: 4,
                    bottom: 4,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 6, vertical: 3),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.55),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        folderPath,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white70,
                          fontSize: 9,
                        ),
                      ),
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
    } catch (_) {
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
        cacheWidth: 150,
        gaplessPlayback: true,
      ),
    );
  }
}
