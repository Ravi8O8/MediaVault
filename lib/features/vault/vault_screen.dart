import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_windowmanager_plus/flutter_windowmanager_plus.dart';
import 'package:image_picker/image_picker.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import '../../core/crypto_service.dart';
import '../../core/database_service.dart';
import 'media_viewer_screen.dart'; // Импортируем новый экран

class VaultScreen extends StatefulWidget {
  final DatabaseService db;
  const VaultScreen({super.key, required this.db});

  @override
  State<VaultScreen> createState() => _VaultScreenState();
}

class _VaultScreenState extends State<VaultScreen> {
  bool _secure = false;
  bool _isLoading = true;
  List<Map<String, dynamic>> _mediaItems = [];

  @override
  void initState() {
    super.initState();
    FlutterWindowManagerPlus.setSecure(false);
    _loadMedia();
  }

  @override
  void dispose() {
    FlutterWindowManagerPlus.setSecure(false);
    super.dispose();
  }

  Future<void> _loadMedia() async {
    final items = await widget.db.getAllMediaItems();
    if (mounted) {
      setState(() {
        _mediaItems = items;
        _isLoading = false;
      });
    }
  }

  Future<void> _importMedia() async {
    final picker = ImagePicker();
    final pickedFile = await picker.pickImage(source: ImageSource.gallery);
    if (pickedFile == null) return;

    setState(() => _isLoading = true);

    try {
      final originalBytes = await File(pickedFile.path).readAsBytes();
      final encryptedBytes = await CryptoService.encryptData(originalBytes);

      final appDir = await getApplicationDocumentsDirectory();
      final vaultDir = Directory(p.join(appDir.path, 'vault_files'));
      if (!await vaultDir.exists()) {
        await vaultDir.create(recursive: true);
      }

      final fileName = '${DateTime.now().millisecondsSinceEpoch}.enc';
      final encryptedFile = File(p.join(vaultDir.path, fileName));
      await encryptedFile.writeAsBytes(encryptedBytes);

      final ext = p.extension(pickedFile.path).toLowerCase();
      final mediaType = (ext == '.mp4' || ext == '.mov') ? 'video' : 'image';
      
      await widget.db.insertMediaItem(encryptedFile.path, mediaType);
      await _loadMedia();
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Файл зашифрован и добавлен')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Ошибка импорта: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _openViewer(Map<String, dynamic> item) async {
    // Открываем экран просмотра и ждем, пока он закроется
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => MediaViewerScreen(mediaItem: item, db: widget.db),
      ),
    );
    // После возвращения обновляем сетку (вдруг файл удалили)
    _loadMedia();
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: Stack(
        children: [
          GlassScaffold(
            background: const DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [Color(0xFF232526), Color(0xFF414345)],
                ),
              ),
            ),
            appBar: GlassAppBar(
              title: const Text('Хранилище'),
              actions: [
                IconButton(
                  icon: Icon(_secure ? Icons.visibility_off : Icons.visibility),
                  onPressed: () {
                    setState(() {
                      _secure = !_secure;
                      FlutterWindowManagerPlus.setSecure(_secure);
                    });
                  },
                ),
              ],
            ),
            body: SafeArea(
              child: Padding(
                padding: const EdgeInsets.only(
                  top: kToolbarHeight + 8,
                  left: 16,
                  right: 16,
                  bottom: 80,
                ),
                child: Column(
                  children: [
                    GlassContainer.card(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Row(
                          children: [
                            Expanded(
                              child: _StatChip(
                                icon: Icons.photo,
                                label: 'Фото',
                                count: _mediaItems.where((e) => e['media_type'] == 'image').length,
                              ),
                            ),
                            Expanded(
                              child: _StatChip(
                                icon: Icons.video_library,
                                label: 'Видео',
                                count: _mediaItems.where((e) => e['media_type'] == 'video').length,
                              ),
                            ),
                            Expanded(
                              child: _StatChip(
                                icon: Icons.folder,
                                label: 'Альбомы',
                                count: 0,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Expanded(
                      child: _isLoading
                          ? const Center(child: CircularProgressIndicator(color: Colors.tealAccent))
                          : _mediaItems.isEmpty
                              ? Center(
                                  child: Text(
                                    'Хранилище пусто\nНажмите + чтобы добавить файл',
                                    textAlign: TextAlign.center,
                                    style: TextStyle(color: Colors.white.withValues(alpha: 0.5)),
                                  ),
                                )
                              : GridView.builder(
                                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                                    crossAxisCount: 3,
                                    crossAxisSpacing: 8,
                                    mainAxisSpacing: 8,
                                  ),
                                  itemCount: _mediaItems.length,
                                  itemBuilder: (context, index) {
                                    final item = _mediaItems[index];
                                    return GestureDetector(
                                      onTap: () => _openViewer(item),
                                      child: _EncryptedThumbnail(filePath: item['file_path']),
                                    );
                                  },
                                ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          Positioned(
            right: 24,
            bottom: 24,
            child: GlassButton(
              icon: const Icon(Icons.add, color: Colors.white),
              onTap: _importMedia,
            ),
          ),
        ],
      ),
    );
  }
}

class _StatChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final int count;
  const _StatChip({required this.icon, required this.label, required this.count});

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, color: Colors.white70),
        const SizedBox(height: 4),
        FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(
            '$label ($count)',
            style: const TextStyle(fontSize: 12, color: Colors.white54),
          ),
        ),
      ],
    );
  }
}

class _EncryptedThumbnail extends StatelessWidget {
  final String filePath;
  const _EncryptedThumbnail({required this.filePath});

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Uint8List>(
      future: _loadAndDecrypt(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return Container(
            decoration: BoxDecoration(
              color: Colors.white10,
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Center(child: CircularProgressIndicator(strokeWidth: 2, color: Colors.tealAccent)),
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
          child: Image.memory(
            snapshot.data!,
            fit: BoxFit.cover,
          ),
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
