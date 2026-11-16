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
import 'media_viewer_screen.dart';
import 'trash_screen.dart';

class VaultScreen extends StatefulWidget {
  final DatabaseService db;
  const VaultScreen({super.key, required this.db});
  @override
  State<VaultScreen> createState() => _VaultScreenState();
}

class _VaultScreenState extends State<VaultScreen> {
  bool _secure = false;
  bool _isLoading = true;
  bool _showFavoritesOnly = false;
  List<Map<String, dynamic>> _mediaItems = [];
  List<Map<String, dynamic>> _albums = [];
  int? _selectedAlbumId;

  @override
  void initState() {
    super.initState();
    FlutterWindowManagerPlus.setSecure(false);
    _loadData();
  }

  Future<void> _loadData() async {
    List<Map<String, dynamic>> items;
    if (_showFavoritesOnly) {
      items = await widget.db.getFavoriteMediaItems();
    } else if (_selectedAlbumId == null) {
      items = await widget.db.getAllMediaItems();
    } else {
      items = await widget.db.getMediaByAlbum(_selectedAlbumId!);
    }
    final albums = await widget.db.getAllAlbums();
    if (mounted) {
      setState(() {
        _mediaItems = items;
        _albums = albums;
        _isLoading = false;
      });
    }
  }

  Future<void> _importMedia() async {
    final choice = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: const Color(0xFF232526),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 12),
            ListTile(
              leading: const Icon(Icons.image, color: Colors.tealAccent),
              title: const Text('Фото', style: TextStyle(color: Colors.white)),
              onTap: () => Navigator.pop(context, 'image'),
            ),
            ListTile(
              leading: const Icon(Icons.videocam, color: Colors.tealAccent),
              title: const Text('Видео', style: TextStyle(color: Colors.white)),
              onTap: () => Navigator.pop(context, 'video'),
            ),
            const SizedBox(height: 12),
          ],
        ),
      ),
    );
    if (choice == null) return;

    final picker = ImagePicker();
    final XFile? pickedFile = choice == 'video'
        ? await picker.pickVideo(source: ImageSource.gallery)
        : await picker.pickImage(source: ImageSource.gallery);
    if (pickedFile == null) return;

    setState(() => _isLoading = true);
    try {
      final originalBytes = await File(pickedFile.path).readAsBytes();
      final encryptedBytes = await CryptoService.encryptData(originalBytes);

      final appDir = await getApplicationDocumentsDirectory();
      final vaultDir = Directory(p.join(appDir.path, 'vault_files'));
      if (!await vaultDir.exists()) await vaultDir.create(recursive: true);

      final fileName = '${DateTime.now().millisecondsSinceEpoch}.enc';
      final encryptedFile = File(p.join(vaultDir.path, fileName));
      await encryptedFile.writeAsBytes(encryptedBytes);

      final ext = p.extension(pickedFile.path).toLowerCase();
      final mediaType = (ext == '.mp4' || ext == '.mov' || choice == 'video')
          ? 'video'
          : 'image';

      final newId = await widget.db.insertMediaItem(encryptedFile.path, mediaType);

      // Если пользователь находится внутри альбома — сразу кладём туда
      if (_selectedAlbumId != null) {
        await widget.db.moveMediaToAlbum(newId, _selectedAlbumId);
      }

      await _loadData();
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
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => MediaViewerScreen(mediaItem: item, db: widget.db),
      ),
    );
    _loadData();
  }

  void _openTrash() async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => TrashScreen(db: widget.db)),
    );
    _loadData();
  }

  Future<void> _createAlbum() async {
    final controller = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF232526),
        title: const Text('Новый альбом', style: TextStyle(color: Colors.white)),
        content: TextField(
          controller: controller,
          autofocus: true,
          style: const TextStyle(color: Colors.white),
          decoration: const InputDecoration(
            hintText: 'Название',
            hintStyle: TextStyle(color: Colors.white54),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Отмена', style: TextStyle(color: Colors.white54)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, controller.text.trim()),
            child: const Text('Создать', style: TextStyle(color: Colors.tealAccent)),
          ),
        ],
      ),
    );
    if (name != null && name.isNotEmpty) {
      await widget.db.insertAlbum(name);
      await _loadData();
    }
  }

  Future<void> _showItemMenu(Map<String, dynamic> item) async {
    final isFav = (item['is_favorite'] as int? ?? 0) == 1;
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF232526),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 16),
              ListTile(
                leading: Icon(
                  isFav ? Icons.favorite : Icons.favorite_border,
                  color: Colors.pinkAccent,
                ),
                title: Text(
                  isFav ? 'Убрать из избранного' : 'В избранное',
                  style: const TextStyle(color: Colors.white),
                ),
                onTap: () async {
                  Navigator.pop(context);
                  await widget.db.toggleFavorite(item['id'], !isFav);
                  await _loadData();
                },
              ),
              ListTile(
                leading: const Icon(Icons.folder_open, color: Colors.tealAccent),
                title: const Text('Переместить в альбом',
                    style: TextStyle(color: Colors.white)),
                onTap: () async {
                  Navigator.pop(context);
                  await _showAlbumPicker(item['id']);
                },
              ),
              const SizedBox(height: 16),
            ],
          ),
        );
      },
    );
  }

  Future<void> _showAlbumPicker(int mediaId) async {
    final currentAlbumId = _selectedAlbumId;
    final selected = await showDialog<Map<String, dynamic>?>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF232526),
        title: const Text('Выберите альбом',
            style: TextStyle(color: Colors.white)),
        content: SizedBox(
          width: double.maxFinite,
          child: ListView(
            shrinkWrap: true,
            children: [
              ListTile(
                leading: const Icon(Icons.folder_off, color: Colors.white54),
                title: const Text('Без альбома',
                    style: TextStyle(color: Colors.white)),
                onTap: () => Navigator.pop(context, {'id': null}),
              ),
              ..._albums.map((a) => ListTile(
                    leading: Icon(
                      a['id'] == currentAlbumId
                          ? Icons.folder
                          : Icons.folder_outlined,
                      color: Colors.tealAccent,
                    ),
                    title: Text(a['name'],
                        style: const TextStyle(color: Colors.white)),
                    onTap: () => Navigator.pop(context, a),
                  )),
            ],
          ),
        ),
      ),
    );
    if (selected != null) {
      await widget.db.moveMediaToAlbum(mediaId, selected['id']);
      await _loadData();
    }
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
                  icon: const Icon(Icons.delete_outline, color: Colors.white),
                  onPressed: _openTrash,
                ),
                IconButton(
                  icon: Icon(
                    _secure ? Icons.visibility_off : Icons.visibility,
                    color: Colors.white,
                  ),
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
                    SizedBox(
                      height: 40,
                      child: ListView(
                        scrollDirection: Axis.horizontal,
                        children: [
                          ChoiceChip(
                            label: const Text('Все'),
                            selected: _selectedAlbumId == null &&
                                !_showFavoritesOnly,
                            onSelected: (_) {
                              setState(() {
                                _selectedAlbumId = null;
                                _showFavoritesOnly = false;
                              });
                              _loadData();
                            },
                          ),
                          const SizedBox(width: 8),
                          ChoiceChip(
                            avatar: const Icon(Icons.favorite,
                                size: 16, color: Colors.pinkAccent),
                            label: const Text('Избранное'),
                            selected: _showFavoritesOnly,
                            onSelected: (v) {
                              setState(() {
                                _showFavoritesOnly = v;
                                _selectedAlbumId = null;
                              });
                              _loadData();
                            },
                          ),
                          const SizedBox(width: 8),
                          ..._albums.map((a) => Padding(
                                padding: const EdgeInsets.only(right: 8),
                                child: ChoiceChip(
                                  label: Text(a['name']),
                                  selected: _selectedAlbumId == a['id'] &&
                                      !_showFavoritesOnly,
                                  onSelected: (_) {
                                    setState(() {
                                      _selectedAlbumId = a['id'];
                                      _showFavoritesOnly = false;
                                    });
                                    _loadData();
                                  },
                                ),
                              )),
                          ActionChip(
                            avatar: const Icon(Icons.add, size: 16),
                            label: const Text('Альбом'),
                            onPressed: _createAlbum,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),
                    Expanded(
                      child: _isLoading
                          ? const Center(
                              child: CircularProgressIndicator(
                                  color: Colors.tealAccent))
                          : _mediaItems.isEmpty
                              ? Center(
                                  child: Text(
                                    _showFavoritesOnly
                                        ? 'Нет избранных файлов\nОтметьте файлы сердечком'
                                        : 'Хранилище пусто\nНажмите + чтобы добавить файл',
                                    textAlign: TextAlign.center,
                                    style: TextStyle(
                                      color:
                                          Colors.white.withValues(alpha: 0.5),
                                    ),
                                  ),
                                )
                              : GridView.builder(
                                  gridDelegate:
                                      const SliverGridDelegateWithFixedCrossAxisCount(
                                    crossAxisCount: 3,
                                    crossAxisSpacing: 8,
                                    mainAxisSpacing: 8,
                                  ),
                                  itemCount: _mediaItems.length,
                                  itemBuilder: (context, index) {
                                    final item = _mediaItems[index];
                                    final isFav =
                                        (item['is_favorite'] as int? ?? 0) == 1;
                                    final isVideo =
                                        item['media_type'] == 'video';
                                    return GestureDetector(
                                      onTap: () => _openViewer(item),
                                      onLongPress: () => _showItemMenu(item),
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

class _EncryptedThumbnail extends StatelessWidget {
  final String filePath;
  final bool isVideo;
  const _EncryptedThumbnail({required this.filePath, this.isVideo = false});

  @override
  Widget build(BuildContext context) {
    // Для видео не тратим ресурсы на полную расшифровку — показываем иконку
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
