import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';

import '../../core/database_service.dart';
import '../../core/thumbnail_cache.dart';
import 'media_grid_widget.dart';
import 'media_viewer_screen.dart';

class AlbumsTab extends StatefulWidget {
  final DatabaseService db;
  const AlbumsTab({super.key, required this.db});

  @override
  State<AlbumsTab> createState() => _AlbumsTabState();
}

class _AlbumsTabState extends State<AlbumsTab> {
  List<Map<String, dynamic>> _albums = [];
  Map<int, int> _counts = {};
  Map<int, Uint8List?> _covers = {};
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final albums = await widget.db.getAllAlbums();
    final counts = <int, int>{};
    final covers = <int, Uint8List?>{};
    for (final a in albums) {
      final albumId = a['id'] as int;
      final items = await widget.db.getMediaByAlbum(albumId);
      counts[albumId] = items.length;
      final coverId = a['cover_media_id'] as int?;
      if (coverId != null) {
        covers[albumId] = await _loadCover(coverId);
      }
    }
    if (mounted) {
      setState(() {
        _albums = albums;
        _counts = counts;
        _covers = covers;
        _loading = false;
      });
    }
  }

  Future<Uint8List?> _loadCover(int coverMediaId) async {
    try {
      final rows = await widget.db.db.query(
        'media_items',
        columns: ['file_path', 'media_type'],
        where: 'id = ?',
        whereArgs: [coverMediaId],
        limit: 1,
      );
      if (rows.isEmpty) return null;
      if (rows.first['media_type'] != 'image') return null;
      return await ThumbnailCache.load(rows.first['file_path'] as String);
    } catch (_) {
      return null;
    }
  }

  Future<void> _createAlbum() async {
    final controller = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF232526),
        title: const Text('Новый альбом',
            style: TextStyle(color: Colors.white)),
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
            child:
                const Text('Отмена', style: TextStyle(color: Colors.white54)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, controller.text.trim()),
            child: const Text('Создать',
                style: TextStyle(color: Colors.tealAccent)),
          ),
        ],
      ),
    );
    if (name != null && name.isNotEmpty) {
      await widget.db.insertAlbum(name);
      await _load();
    }
  }

  Future<void> _openAlbum(Map<String, dynamic> album) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => AlbumDetailScreen(
          db: widget.db,
          albumId: album['id'] as int,
          albumName: album['name'] as String,
        ),
      ),
    );
    _load();
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(
          child: CircularProgressIndicator(color: Colors.tealAccent));
    }
    return Stack(
      children: [
        if (_albums.isEmpty)
          Center(
            child: Padding(
              padding: const EdgeInsets.all(32),
              child: Text(
                'Пока нет альбомов\nНажмите + чтобы создать',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.5),
                ),
              ),
            ),
          )
        else
          GridView.builder(
            padding: const EdgeInsets.all(4),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              crossAxisSpacing: 12,
              mainAxisSpacing: 12,
              childAspectRatio: 0.9,
            ),
            itemCount: _albums.length,
            itemBuilder: (context, index) {
              final album = _albums[index];
              final albumId = album['id'] as int;
              final count = _counts[albumId] ?? 0;
              final cover = _covers[albumId];
              return GestureDetector(
                onTap: () => _openAlbum(album),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(16),
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      if (cover != null)
                        Image.memory(
                          cover,
                          fit: BoxFit.cover,
                          gaplessPlayback: true,
                        )
                      else
                        DecoratedBox(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                              colors: [
                                Colors.teal.withValues(alpha: 0.35),
                                Colors.teal.withValues(alpha: 0.08),
                              ],
                            ),
                          ),
                        ),
                      if (cover != null)
                        DecoratedBox(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                              colors: [
                                Colors.black.withValues(alpha: 0.15),
                                Colors.black.withValues(alpha: 0.80),
                              ],
                            ),
                          ),
                        ),
                      Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          border: Border.all(
                            color: Colors.white.withValues(alpha: 0.15),
                          ),
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Icon(Icons.folder,
                                color: Colors.tealAccent, size: 30),
                            const Spacer(),
                            Text(
                              album['name'] as String,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 15,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              '$count файлов',
                              style: const TextStyle(
                                color: Colors.white70,
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        Positioned(
          right: 16,
          bottom: 16,
          child: GlassButton(
            icon: const Icon(Icons.create_new_folder, color: Colors.white),
            onTap: _createAlbum,
          ),
        ),
      ],
    );
  }
}

class AlbumDetailScreen extends StatefulWidget {
  final DatabaseService db;
  final int albumId;
  final String albumName;

  const AlbumDetailScreen({
    super.key,
    required this.db,
    required this.albumId,
    required this.albumName,
  });

  @override
  State<AlbumDetailScreen> createState() => _AlbumDetailScreenState();
}

class _AlbumDetailScreenState extends State<AlbumDetailScreen> {
  List<Map<String, dynamic>> _items = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final items = await widget.db.getMediaByAlbum(widget.albumId);
    if (mounted) {
      setState(() {
        _items = items;
        _loading = false;
      });
    }
  }

  Future<void> _import() async {
    await MediaImporter.importMedia(context, widget.db,
        albumId: widget.albumId);
    await _load();
  }

  void _openViewer(int index) async {
    final changed = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => MediaViewerScreen(
          items: _items,
          initialIndex: index,
          db: widget.db,
        ),
      ),
    );
    if (changed == true) _load();
  }

  Future<void> _showItemMenu(int index) async {
    final item = _items[index];
    final isFav = (item['is_favorite'] as int? ?? 0) == 1;
    final isImage = item['media_type'] == 'image';

    final action = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: const Color(0xFF232526),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => SafeArea(
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
              onTap: () => Navigator.pop(context, 'fav'),
            ),
            if (isImage)
              ListTile(
                leading: const Icon(Icons.image_outlined,
                    color: Colors.tealAccent),
                title: const Text('Сделать обложкой',
                    style: TextStyle(color: Colors.white)),
                onTap: () => Navigator.pop(context, 'cover'),
              ),
            ListTile(
              leading: const Icon(Icons.folder_off, color: Colors.tealAccent),
              title: const Text('Убрать из альбома',
                  style: TextStyle(color: Colors.white)),
              onTap: () => Navigator.pop(context, 'remove'),
            ),
            ListTile(
              leading:
                  const Icon(Icons.delete_outline, color: Colors.redAccent),
              title: const Text('В корзину',
                  style: TextStyle(color: Colors.white)),
              onTap: () => Navigator.pop(context, 'delete'),
            ),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );

    if (!mounted) return;
    if (action == 'fav') {
      await widget.db.toggleFavorite(item['id'], !isFav);
      _load();
    } else if (action == 'cover') {
      await widget.db.setAlbumCover(widget.albumId, item['id'] as int);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Обложка обновлена')),
      );
    } else if (action == 'remove') {
      await widget.db.moveMediaToAlbum(item['id'], null);
      _load();
    } else if (action == 'delete') {
      await widget.db.softDeleteMediaItem(item['id']);
      _load();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF232526),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.white),
        title: Text(widget.albumName,
            style: const TextStyle(color: Colors.white)),
      ),
      body: _loading
          ? const Center(
              child: CircularProgressIndicator(color: Colors.tealAccent))
          : Padding(
              padding: const EdgeInsets.all(12),
              child: MediaGridWidget(
                items: _items,
                emptyMessage:
                    'В этом альбоме пусто\nНажмите + чтобы добавить',
                onItemTap: _openViewer,
                onItemLongPress: _showItemMenu,
              ),
            ),
      floatingActionButton: FloatingActionButton(
        backgroundColor: Colors.teal,
        onPressed: _import,
        child: const Icon(Icons.add, color: Colors.white),
      ),
    );
  }
}
