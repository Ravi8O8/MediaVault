import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:video_player/video_player.dart';

import '../../core/crypto_service.dart';
import '../../core/database_service.dart';
import '../../core/storage_stats_service.dart';

class MediaViewerScreen extends StatefulWidget {
  final List<Map<String, dynamic>> items;
  final int initialIndex;
  final DatabaseService db;

  const MediaViewerScreen({
    super.key,
    required this.items,
    required this.initialIndex,
    required this.db,
  });

  @override
  State<MediaViewerScreen> createState() => _MediaViewerScreenState();
}

class _MediaViewerScreenState extends State<MediaViewerScreen> {
  late final PageController _pageController;
  late int _currentIndex;
  late List<Map<String, dynamic>> _items;

  @override
  void initState() {
    super.initState();
    _items = List<Map<String, dynamic>>.from(widget.items);
    _currentIndex = widget.initialIndex;
    _pageController = PageController(initialPage: _currentIndex);
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  Map<String, dynamic> get _currentItem => _items[_currentIndex];
  bool get _currentIsFav => (_currentItem['is_favorite'] as int? ?? 0) == 1;

  Future<void> _toggleFavorite() async {
    final newVal = !_currentIsFav;
    await widget.db.toggleFavorite(_currentItem['id'], newVal);
    if (mounted) {
      setState(() => _items[_currentIndex]['is_favorite'] = newVal ? 1 : 0);
    }
  }

  Future<void> _deleteItem() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF232526),
        title: const Text('Удалить файл?',
            style: TextStyle(color: Colors.white)),
        content: const Text(
          'Файл будет перемещен в корзину.',
          style: TextStyle(color: Colors.white54),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child:
                const Text('Отмена', style: TextStyle(color: Colors.white54)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Удалить',
                style: TextStyle(color: Colors.redAccent)),
          ),
        ],
      ),
    );
    if (confirm != true) return;
    await widget.db.softDeleteMediaItem(_currentItem['id']);
    if (mounted) Navigator.pop(context, true);
  }

  Future<void> _shareFile() async {
    try {
      final item = _currentItem;
      final isVideo = item['media_type'] == 'video';
      final encrypted = await File(item['file_path']).readAsBytes();
      final decrypted = await CryptoService.decryptData(encrypted);

      final tempDir = await getTemporaryDirectory();
      final name = isVideo
          ? 'shared_${item['id']}.mp4'
          : 'shared_${item['id']}.jpg';
      final shareFile = File('${tempDir.path}/$name');
      await shareFile.writeAsBytes(decrypted);

      await Share.shareXFiles([XFile(shareFile.path)]);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Ошибка экспорта: $e')),
        );
      }
    }
  }

  Future<void> _showInfo() async {
    final item = _currentItem;
    final path = item['file_path'] as String;
    final isVideo = item['media_type'] == 'video';

    int encBytes = 0;
    try {
      final f = File(path);
      if (await f.exists()) encBytes = await f.length();
    } catch (_) {}

    String? dimensions;
    if (!isVideo) {
      try {
        final enc = await File(path).readAsBytes();
        final dec = await CryptoService.decryptData(enc);
        final codec = await ui.instantiateImageCodec(dec);
        final frame = await codec.getNextFrame();
        dimensions = '${frame.image.width} × ${frame.image.height}';
        frame.image.dispose();
        codec.dispose();
      } catch (_) {}
    }

    final createdAt = item['created_at'] is int
        ? DateTime.fromMillisecondsSinceEpoch(item['created_at'] as int)
        : null;
    final dateLabel = createdAt != null
        ? '${createdAt.day.toString().padLeft(2, '0')}.'
            '${createdAt.month.toString().padLeft(2, '0')}.'
            '${createdAt.year} '
            '${createdAt.hour.toString().padLeft(2, '0')}:'
            '${createdAt.minute.toString().padLeft(2, '0')}'
        : '—';

    final baseName = path.split(Platform.pathSeparator).last;

    if (!mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (ctx) => ClipRRect(
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        child: BackdropFilter(
          filter: ui.ImageFilter.blur(sigmaX: 24, sigmaY: 24),
          child: Container(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
            decoration: BoxDecoration(
              color: const Color(0xFF232526).withValues(alpha: 0.92),
              border: Border.all(color: Colors.white12),
              borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(28)),
            ),
            child: SafeArea(
              top: false,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Center(
                    child: Container(
                      width: 40,
                      height: 4,
                      margin: const EdgeInsets.only(bottom: 16),
                      decoration: BoxDecoration(
                        color: Colors.white24,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  const Text(
                    'Информация о файле',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 16),
                  _InfoRow(label: 'Имя', value: baseName),
                  _InfoRow(
                    label: 'Тип',
                    value: isVideo ? 'Видео' : 'Изображение',
                  ),
                  _InfoRow(
                    label: 'Размер на диске',
                    value: StorageStats.formatBytes(encBytes),
                  ),
                  if (dimensions != null)
                    _InfoRow(label: 'Разрешение', value: dimensions),
                  _InfoRow(label: 'Добавлено', value: dateLabel),
                  _InfoRow(
                    label: 'В избранном',
                    value: _currentIsFav ? 'Да' : 'Нет',
                  ),
                  _InfoRow(label: 'ID', value: '${item['id']}'),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black.withValues(alpha: 0.6),
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.white),
        title: Text(
          '${_currentIndex + 1} / ${_items.length}',
          style: const TextStyle(color: Colors.white, fontSize: 14),
        ),
        actions: [
          IconButton(
            icon: Icon(
              _currentIsFav ? Icons.favorite : Icons.favorite_border,
              color: Colors.pinkAccent,
            ),
            onPressed: _toggleFavorite,
          ),
          IconButton(
            icon: const Icon(Icons.info_outline, color: Colors.white),
            onPressed: _showInfo,
          ),
          IconButton(
            icon: const Icon(Icons.share, color: Colors.white),
            onPressed: _shareFile,
          ),
          IconButton(
            icon: const Icon(Icons.delete_outline, color: Colors.redAccent),
            onPressed: _deleteItem,
          ),
        ],
      ),
      body: PageView.builder(
        controller: _pageController,
        itemCount: _items.length,
        onPageChanged: (i) => setState(() => _currentIndex = i),
        itemBuilder: (context, index) {
          return _ViewerPage(
            key: ValueKey(_items[index]['id']),
            item: _items[index],
            isActive: index == _currentIndex,
          );
        },
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  final String label;
  final String value;
  const _InfoRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 140,
            child: Text(
              label,
              style: const TextStyle(color: Colors.white54, fontSize: 13),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 13,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ViewerPage extends StatefulWidget {
  final Map<String, dynamic> item;
  final bool isActive;

  const _ViewerPage({
    super.key,
    required this.item,
    required this.isActive,
  });

  @override
  State<_ViewerPage> createState() => _ViewerPageState();
}

class _ViewerPageState extends State<_ViewerPage> {
  Uint8List? _imageBytes;
  bool _loading = true;
  String? _error;
  VideoPlayerController? _videoController;
  File? _tempVideoFile;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant _ViewerPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    final c = _videoController;
    if (c != null &&
        c.value.isInitialized &&
        oldWidget.isActive != widget.isActive) {
      if (widget.isActive) {
        c.play();
      } else {
        c.pause();
      }
    }
  }

  @override
  void dispose() {
    _videoController?.dispose();
    if (_tempVideoFile != null) {
      try {
        _tempVideoFile!.deleteSync();
      } catch (_) {}
    }
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final file = File(widget.item['file_path']);
      final encrypted = await file.readAsBytes();
      final decrypted = await CryptoService.decryptData(encrypted);

      if (widget.item['media_type'] == 'video') {
        final tempDir = await getTemporaryDirectory();
        final tempFile = File(
          '${tempDir.path}/mediavault_preview_${widget.item['id']}.mp4',
        );
        await tempFile.writeAsBytes(decrypted);
        _tempVideoFile = tempFile;

        final controller = VideoPlayerController.file(tempFile);
        await controller.initialize();
        await controller.setLooping(true);
        if (widget.isActive) await controller.play();

        if (mounted) {
          setState(() {
            _videoController = controller;
            _loading = false;
          });
        }
      } else {
        if (mounted) {
          setState(() {
            _imageBytes = decrypted;
            _loading = false;
          });
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _loading = false;
        });
      }
    }
  }

  void _togglePlayPause() {
    final c = _videoController;
    if (c == null) return;
    setState(() {
      c.value.isPlaying ? c.pause() : c.play();
    });
  }

  String _fmt(Duration d) {
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  Widget _buildVideo() {
    final c = _videoController;
    if (c == null || !c.value.isInitialized) {
      return _loading
          ? const Center(
              child: CircularProgressIndicator(color: Colors.tealAccent))
          : Center(
              child: Text(
                'Ошибка видео: ${_error ?? 'неизвестно'}',
                style: const TextStyle(color: Colors.redAccent),
              ),
            );
    }

    return SafeArea(
      child: Column(
        children: [
          Expanded(
            child: GestureDetector(
              onTap: _togglePlayPause,
              child: Center(
                child: AspectRatio(
                  aspectRatio: c.value.aspectRatio,
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      VideoPlayer(c),
                      if (!c.value.isPlaying)
                        const Icon(
                          Icons.play_circle_fill,
                          color: Colors.white70,
                          size: 80,
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          _VideoControls(
            controller: c,
            onTogglePlay: _togglePlayPause,
            formatDuration: _fmt,
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (widget.item['media_type'] == 'video') return _buildVideo();

    if (_loading) {
      return const Center(
        child: CircularProgressIndicator(color: Colors.tealAccent),
      );
    }
    if (_imageBytes == null) {
      return const Center(
        child: Text(
          'Не удалось расшифровать файл',
          style: TextStyle(color: Colors.redAccent),
        ),
      );
    }
    return InteractiveViewer(
      panEnabled: true,
      minScale: 0.5,
      maxScale: 5.0,
      child: Center(
        child: Image.memory(_imageBytes!, fit: BoxFit.contain),
      ),
    );
  }
}

class _VideoControls extends StatelessWidget {
  final VideoPlayerController controller;
  final VoidCallback onTogglePlay;
  final String Function(Duration) formatDuration;

  const _VideoControls({
    required this.controller,
    required this.onTogglePlay,
    required this.formatDuration,
  });

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final pos = controller.value.position;
        final dur = controller.value.duration;
        final maxMs =
            dur.inMilliseconds > 0 ? dur.inMilliseconds.toDouble() : 1.0;
        final valMs = pos.inMilliseconds
            .clamp(0, dur.inMilliseconds > 0 ? dur.inMilliseconds : 0)
            .toDouble();

        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          color: Colors.black.withValues(alpha: 0.5),
          child: Row(
            children: [
              IconButton(
                icon: Icon(
                  controller.value.isPlaying ? Icons.pause : Icons.play_arrow,
                  color: Colors.white,
                ),
                onPressed: onTogglePlay,
              ),
              Text(
                formatDuration(pos),
                style: const TextStyle(color: Colors.white70, fontSize: 12),
              ),
              Expanded(
                child: SliderTheme(
                  data: SliderTheme.of(context).copyWith(
                    activeTrackColor: Colors.tealAccent,
                    thumbColor: Colors.tealAccent,
                    inactiveTrackColor: Colors.white24,
                    trackHeight: 3,
                    thumbShape:
                        const RoundSliderThumbShape(enabledThumbRadius: 7),
                  ),
                  child: Slider(
                    value: valMs,
                    max: maxMs,
                    onChanged: (v) => controller
                        .seekTo(Duration(milliseconds: v.toInt())),
                  ),
                ),
              ),
              Text(
                formatDuration(dur),
                style: const TextStyle(color: Colors.white70, fontSize: 12),
              ),
            ],
          ),
        );
      },
    );
  }
}
