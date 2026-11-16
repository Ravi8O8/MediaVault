import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:video_player/video_player.dart';
import '../../core/crypto_service.dart';
import '../../core/database_service.dart';

class MediaViewerScreen extends StatefulWidget {
  final Map<String, dynamic> mediaItem;
  final DatabaseService db;
  const MediaViewerScreen({
    super.key,
    required this.mediaItem,
    required this.db,
  });
  @override
  State<MediaViewerScreen> createState() => _MediaViewerScreenState();
}

class _MediaViewerScreenState extends State<MediaViewerScreen> {
  Uint8List? _decryptedBytes;
  bool _isLoading = true;
  bool _isFavorite = false;
  VideoPlayerController? _videoController;
  File? _tempVideoFile;

  @override
  void initState() {
    super.initState();
    _isFavorite = (widget.mediaItem['is_favorite'] as int? ?? 0) == 1;
    _loadMedia();
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

  Future<void> _loadMedia() async {
    try {
      final file = File(widget.mediaItem['file_path']);
      final encryptedBytes = await file.readAsBytes();
      final decrypted = await CryptoService.decryptData(encryptedBytes);

      if (widget.mediaItem['media_type'] == 'video') {
        final tempDir = await getTemporaryDirectory();
        final tempFile = File(
          '${tempDir.path}/temp_video_${widget.mediaItem['id']}.mp4',
        );
        await tempFile.writeAsBytes(decrypted);
        _tempVideoFile = tempFile;
        _videoController = VideoPlayerController.file(tempFile);
        await _videoController!.initialize();
        await _videoController!.play();
        await _videoController!.setLooping(true);
      } else {
        _decryptedBytes = decrypted;
      }
    } catch (_) {
      // Ошибка расшифровки/инициализации
    } finally {
      if (mounted) setState(() => _isLoading = false);
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
            child: const Text('Отмена', style: TextStyle(color: Colors.white54)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Удалить',
                style: TextStyle(color: Colors.redAccent)),
          ),
        ],
      ),
    );
    if (confirm == true) {
      await widget.db.softDeleteMediaItem(widget.mediaItem['id']);
      if (mounted) Navigator.pop(context);
    }
  }

  Future<void> _toggleFavorite() async {
    final newVal = !_isFavorite;
    await widget.db.toggleFavorite(widget.mediaItem['id'], newVal);
    if (mounted) setState(() => _isFavorite = newVal);
  }

  Future<void> _shareFile() async {
    try {
      final tempDir = await getTemporaryDirectory();
      final isVideo = widget.mediaItem['media_type'] == 'video';
      final shareFileName =
          isVideo ? 'shared_video.mp4' : 'shared_image.jpg';
      final shareFile = File('${tempDir.path}/$shareFileName');

      if (isVideo) {
        if (_tempVideoFile == null) return;
        await _tempVideoFile!.copy(shareFile.path);
      } else {
        if (_decryptedBytes == null) return;
        await shareFile.writeAsBytes(_decryptedBytes!);
      }

      await Share.shareXFiles([XFile(shareFile.path)]);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Ошибка экспорта: $e')),
        );
      }
    }
  }

  void _togglePlayPause() {
    if (_videoController == null) return;
    setState(() {
      _videoController!.value.isPlaying
          ? _videoController!.pause()
          : _videoController!.play();
    });
  }

  Widget _buildVideoView() {
    if (_videoController == null || !_videoController!.value.isInitialized) {
      return const Text(
        'Не удалось воспроизвести видео',
        style: TextStyle(color: Colors.redAccent),
      );
    }
    return GestureDetector(
      onTap: _togglePlayPause,
      child: Stack(
        alignment: Alignment.center,
        children: [
          AspectRatio(
            aspectRatio: _videoController!.value.aspectRatio,
            child: VideoPlayer(_videoController!),
          ),
          if (!_videoController!.value.isPlaying)
            const Icon(
              Icons.play_circle_fill,
              color: Colors.white70,
              size: 80,
            ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isVideo = widget.mediaItem['media_type'] == 'video';
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.white),
        actions: [
          IconButton(
            icon: Icon(
              _isFavorite ? Icons.favorite : Icons.favorite_border,
              color: Colors.pinkAccent,
            ),
            onPressed: _toggleFavorite,
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
      body: Center(
        child: _isLoading
            ? const CircularProgressIndicator(color: Colors.tealAccent)
            : isVideo
                ? _buildVideoView()
                : (_decryptedBytes != null
                    ? InteractiveViewer(
                        panEnabled: true,
                        minScale: 0.5,
                        maxScale: 4.0,
                        child: Image.memory(
                          _decryptedBytes!,
                          fit: BoxFit.contain,
                        ),
                      )
                    : const Text(
                        'Не удалось расшифровать файл',
                        style: TextStyle(color: Colors.redAccent),
                      )),
      ),
    );
  }
}
