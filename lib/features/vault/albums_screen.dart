import 'dart:typed_data';
import 'package:flutter/material.dart';
import '../../core/app_theme_service.dart';
import '../../core/database_service.dart';
import '../../core/thumbnail_cache.dart';
import 'media_grid_widget.dart';
import 'media_viewer_screen.dart';
import 'vault_screen.dart';

class AlbumsTab extends StatefulWidget {
  final DatabaseService db;
  final int dataVersion;
  final VoidCallback? onDataChanged;
  const AlbumsTab({super.key, required this.db, required this.dataVersion, this.onDataChanged});
  @override
  State<AlbumsTab> createState() => _AlbumsTabState();
}

class _AlbumsTabState extends State<AlbumsTab> {
  List<Map<String, dynamic>> _albums = [];
  Map<int, int> _counts = {};
  Map<int, Uint8List?> _covers = {};
  bool _loading = true;

  @override
  void initState() { super.initState(); _load(); }

  @override
  void didUpdateWidget(covariant AlbumsTab old) {
    super.didUpdateWidget(old);
    if (old.dataVersion != widget.dataVersion) _load();
  }

  Future<void> _load() async {
    final albums = await widget.db.getAllAlbums();
    final counts = <int, int>{};
    final covers = <int, Uint8List?>{};
    await Future.wait(albums.map((a) async {
      final albumId = a['id'] as int;
      final items = await widget.db.getMediaByAlbum(albumId);
      counts[albumId] = items.length;
      final coverId = a['cover_media_id'] as int?;
      if (coverId != null) covers[albumId] = await _loadCover(coverId);
    }));
    if (mounted) setState(() { _albums = albums; _counts = counts; _covers = covers; _loading = false; });
  }

  Future<Uint8List?> _loadCover(int coverMediaId) async {
    try {
      final rows = await widget.db.db.query('media_items', columns: ['file_path', 'media_type'], where: 'id = ?', whereArgs: [coverMediaId], limit: 1);
      if (rows.isEmpty || rows.first['media_type'] != 'image') return null;
      return await ThumbnailCache.load(rows.first['file_path'] as String);
    } catch (_) { return null; }
  }

  Future<void> _createAlbum() async {
    final controller = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Новый альбом'),
        content: TextField(controller: controller, autofocus: true, decoration: const InputDecoration(hintText: 'Название')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Отмена')),
          TextButton(onPressed: () => Navigator.pop(context, controller.text.trim()), child: const Text('Создать', style: TextStyle(color: Colors.tealAccent))),
        ],
      ),
    );
    controller.dispose();
    if (name != null && name.isNotEmpty) { await widget.db.insertAlbum(name); await _load(); widget.onDataChanged?.call(); }
  }

  Future<void> _renameAlbum(Map<String, dynamic> album) async {
    final controller = TextEditingController(text: album['name'] as String);
    final newName = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Переименовать'),
        content: TextField(controller: controller, autofocus: true, decoration: const InputDecoration(hintText: 'Название')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Отмена')),
          TextButton(onPressed: () => Navigator.pop(context, controller.text.trim()), child: const Text('Сохранить', style: TextStyle(color: Colors.tealAccent))),
        ],
      ),
    );
    controller.dispose();
    if (newName != null && newName.isNotEmpty) { await widget.db.renameAlbum(album['id'] as int, newName); await _load(); widget.onDataChanged?.call(); }
  }

  Future<void> _deleteAlbum(Map<String, dynamic> album) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Удалить альбом?'),
        content: Text('Альбом «${album['name']}» будет удалён. Файлы останутся.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Отмена')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Удалить', style: TextStyle(color: Colors.redAccent))),
        ],
      ),
    );
    if (confirm == true) { await widget.db.deleteAlbum(album['id'] as int); await _load(); widget.onDataChanged?.call(); }
  }

  Future<void> _showAlbumMenu(Map<String, dynamic> album) async {
    final action = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: Theme.of(context).bottomSheetTheme.backgroundColor,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const SizedBox(height: 16),
          ListTile(leading: const Icon(Icons.edit_outlined, color: Colors.tealAccent), title: const Text('Переименовать'), onTap: () => Navigator.pop(ctx, 'rename')),
          ListTile(leading: const Icon(Icons.delete_outline, color: Colors.redAccent), title: const Text('Удалить альбом'), onTap: () => Navigator.pop(ctx, 'delete')),
          const SizedBox(height: 16),
        ]),
      ),
    );
    if (!mounted) return;
    if (action == 'rename') await _renameAlbum(album);
    else if (action == 'delete') await _deleteAlbum(album);
  }

  Future<void> _openAlbum(Map<String, dynamic> album) async {
    await Navigator.push(context, MaterialPageRoute(builder: (_) => AlbumDetailScreen(db: widget.db, albumId: album['id'] as int, albumName: album['name'] as String)));
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator(color: Colors.tealAccent));
    return Stack(
      children: [
        if (_albums.isEmpty)
          Center(child: Text('Пока нет альбомов\nНажмите + чтобы создать', textAlign: TextAlign.center, style: TextStyle(color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.5))))
        else
          GridView.builder(
            padding: const EdgeInsets.all(4),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 2, crossAxisSpacing: 12, mainAxisSpacing: 12, childAspectRatio: 0.9),
            itemCount: _albums.length,
            itemBuilder: (context, index) {
              final album = _albums[index];
              final albumId = album['id'] as int;
              final count = _counts[albumId] ?? 0;
              final cover = _covers[albumId];
              return GestureDetector(
                onTap: () => _openAlbum(album),
                onLongPress: () => _showAlbumMenu(album),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(16),
                  child: Stack(fit: StackFit.expand, children: [
                    if (cover != null) Image.memory(cover, fit: BoxFit.cover, gaplessPlayback: true, cacheWidth: 300)
                    else const DecoratedBox(decoration: BoxDecoration(gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [Colors.teal, Colors.tealAccent]))),
                    if (cover != null) const DecoratedBox(decoration: BoxDecoration(gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Colors.black12, Colors.black87]))),
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(border: Border.all(color: Colors.white.withValues(alpha: 0.15)), borderRadius: BorderRadius.circular(16)),
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        const Icon(Icons.folder, color: Colors.tealAccent, size: 30),
                        const Spacer(),
                        Text(album['name'] as String, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w600)),
                        const SizedBox(height: 4),
                        Text('$count файлов', style: const TextStyle(color: Colors.white70, fontSize: 12)),
                      ]),
                    ),
                  ]),
                ),
              );
            },
          ),
        Positioned(right: 16, bottom: 16, child: FloatingActionButton(backgroundColor: Colors.teal, foregroundColor: Colors.white, onPressed: _createAlbum, child: const Icon(Icons.create_new_folder))),
      ],
    );
  }
}

class AlbumDetailScreen extends StatefulWidget {
  final DatabaseService db;
  final int albumId;
  final String albumName;
  const AlbumDetailScreen({super.key, required this.db, required this.albumId, required this.albumName});
  @override
  State<AlbumDetailScreen> createState() => _AlbumDetailScreenState();
}

class _AlbumDetailScreenState extends State<AlbumDetailScreen> {
  List<Map<String, dynamic>> _items = [];
  bool _loading = true;
  final ValueNotifier<Set<int>> _selectedIds = ValueNotifier<Set<int>>({});

  @override
  void initState() { super.initState(); _load(); }

  @override
  void dispose() { _selectedIds.dispose(); super.dispose(); }

  Future<void> _load() async {
    final sortOrder = AppThemeService.instance.sortOrder;
    final items = await widget.db.getMediaByAlbum(widget.albumId, sortOrder: sortOrder);
    if (mounted) {
      setState(() {
        _items = items;
        _loading = false;
        final validIds = items.map((e) => e['id'] as int).toSet();
        _selectedIds.value = _selectedIds.value.where(validIds.contains).toSet();
      });
    }
  }

  Future<void> _import() async {
    await MediaImporter.importFiles(context, widget.db, albumId: widget.albumId);
    await _load();
  }

  Future<void> _openViewer(int index) async {
    await Navigator.push<bool>(context, MaterialPageRoute(builder: (_) => MediaViewerScreen(items: _items, initialIndex: index, db: widget.db)));
    if (mounted) await _load();
  }

  void _startSelection(int index) { _selectedIds.value = {..._selectedIds.value, _items[index]['id'] as int}; }
  void _addToSelection(int index) { _selectedIds.value = {..._selectedIds.value, _items[index]['id'] as int}; }
  void _toggleSelection(int index) {
    final id = _items[index]['id'] as int;
    final next = Set<int>.from(_selectedIds.value);
    if (!next.remove(id)) next.add(id);
    _selectedIds.value = next;
  }
  void _exitSelection() => _selectedIds.value = {};
  void _toggleSelectAll() {
    final allIds = _items.map((e) => e['id'] as int).toSet();
    if (_selectedIds.value.length == allIds.length) _selectedIds.value = {};
    else _selectedIds.value = allIds;
  }

  Future<void> _massMove() async {
    final result = await showAlbumPicker(context, widget.db);
    if (result == null) return;
    final albumId = result['id'] as int?;
    for (final id in _selectedIds.value.toList()) {
      await widget.db.moveMediaToAlbum(id, albumId);
    }
    _exitSelection();
    await _load();
  }

  Future<void> _massDelete() async {
    if (!await confirmDelete(context, _selectedIds.value.length)) return;
    for (final id in _selectedIds.value.toList()) {
      await widget.db.softDeleteMediaItem(id);
    }
    _exitSelection();
    await _load();
  }

  Future<void> _massFavorite() async {
    for (final id in _selectedIds.value.toList()) {
      await widget.db.toggleFavorite(id, true);
    }
    _exitSelection();
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    final themeService = AppThemeService.instance;
    final brightness = Theme.of(context).brightness;
    final onSurface = Theme.of(context).colorScheme.onSurface;

    return AnimatedBuilder(
      animation: themeService,
      builder: (context, _) {
        return Scaffold(
          backgroundColor: Colors.transparent,
          extendBodyBehindAppBar: true,
          body: Stack(
            children: [
              AnimatedContainer(
                duration: const Duration(milliseconds: 400),
                decoration: BoxDecoration(gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: themeService.gradientFor(brightness))),
              ),
              SafeArea(
                child: Padding(
                  padding: EdgeInsets.fromLTRB(12, MediaQuery.of(context).padding.top + kToolbarHeight + 12, 12, 12),
                  child: _loading ? const Center(child: CircularProgressIndicator(color: Colors.tealAccent))
                  : ValueListenableBuilder<Set<int>>(
                      valueListenable: _selectedIds,
                      builder: (context, selected, _) {
                        final selectionMode = selected.isNotEmpty;
                        return Stack(
                          children: [
                            MediaGridWidget(
                              items: _items,
                              emptyMessage: 'В этом альбоме пусто\nНажмите + чтобы добавить',
                              onItemTap: _openViewer,
                              onSelectionStart: _startSelection,
                              onSelectionAdd: _addToSelection,
                              onSelectionToggle: _toggleSelection,
                              selectionListenable: _selectedIds,
                            ),
                            if (selectionMode)
                              SelectionActionBar(
                                count: selected.length,
                                allSelected: selected.length == _items.length,
                                onClose: _exitSelection,
                                onSelectAll: _toggleSelectAll,
                                onFavorite: _massFavorite,
                                onMove: _massMove,
                                onExport: () async {},
                                onDelete: _massDelete,
                              ),
                          ],
                        );
                      },
                    ),
                ),
              ),
              Positioned(
                top: 0, left: 0, right: 0,
                child: AppBar(backgroundColor: Colors.transparent, elevation: 0, iconTheme: IconThemeData(color: onSurface), title: Text(widget.albumName, style: TextStyle(color: onSurface))),
              ),
              ValueListenableBuilder<Set<int>>(
                valueListenable: _selectedIds,
                builder: (context, selected, _) {
                  if (selected.isNotEmpty) return const SizedBox.shrink();
                  return Positioned(right: 16, bottom: 16, child: FloatingActionButton(backgroundColor: Colors.teal, foregroundColor: Colors.white, onPressed: _import, child: const Icon(Icons.add)));
                },
              ),
            ],
          ),
        );
      },
    );
  }
}
