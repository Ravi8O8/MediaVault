import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_windowmanager_plus/flutter_windowmanager_plus.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';
import '../../core/database_service.dart';
import 'albums_screen.dart';
import 'media_grid_widget.dart';
import 'media_viewer_screen.dart';
import 'trash_screen.dart';

class VaultScreen extends StatefulWidget {
  final DatabaseService db;
  const VaultScreen({super.key, required this.db});

  @override
  State<VaultScreen> createState() => _VaultScreenState();
}

class _VaultScreenState extends State<VaultScreen> {
  int _currentTab = 0;
  bool _secure = false;

  @override
  void initState() {
    super.initState();
    FlutterWindowManagerPlus.setSecure(false);
  }

  void _toggleSecure() {
    setState(() {
      _secure = !_secure;
      FlutterWindowManagerPlus.setSecure(_secure);
    });
  }

  String get _title {
    switch (_currentTab) {
      case 0:
        return 'Хранилище';
      case 1:
        return 'Альбомы';
      case 2:
        return 'Избранное';
      case 3:
        return 'Корзина';
      default:
        return 'MediaVault';
    }
  }

  @override
  Widget build(BuildContext context) {
    final topPadding = MediaQuery.of(context).padding.top;
    return Material(
      color: Colors.transparent,
      child: Stack(
        children: [
          const DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [Color(0xFF232526), Color(0xFF414345)],
              ),
            ),
            child: SizedBox.expand(),
          ),
          Padding(
            padding: EdgeInsets.only(
              top: topPadding + kToolbarHeight + 8,
              bottom: 96,
              left: 8,
              right: 8,
            ),
            child: IndexedStack(
              index: _currentTab,
              children: [
                _AllMediaTab(db: widget.db),
                AlbumsTab(db: widget.db),
                _FavoritesTab(db: widget.db),
                TrashScreen(db: widget.db),
              ],
            ),
          ),
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: GlassAppBar(
              title: Text(_title),
              actions: [
                IconButton(
                  icon: Icon(
                    _secure ? Icons.visibility_off : Icons.visibility,
                    color: Colors.white,
                  ),
                  onPressed: _toggleSecure,
                ),
              ],
            ),
          ),
          Positioned(
            left: 16,
            right: 16,
            bottom: 16,
            child: _GlassBottomNav(
              currentIndex: _currentTab,
              onChanged: (i) => setState(() => _currentTab = i),
            ),
          ),
        ],
      ),
    );
  }
}

class _GlassBottomNav extends StatelessWidget {
  final int currentIndex;
  final ValueChanged<int> onChanged;

  const _GlassBottomNav({
    required this.currentIndex,
    required this.onChanged,
  });

  static const _items = [
    (Icons.photo_library_outlined, Icons.photo_library, 'Все'),
    (Icons.folder_outlined, Icons.folder, 'Альбомы'),
    (Icons.favorite_border, Icons.favorite, 'Избранное'),
    (Icons.delete_outline, Icons.delete, 'Корзина'),
  ];

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(24),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
        child: Container(
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(24),
            border: Border.all(
              color: Colors.white.withValues(alpha: 0.15),
            ),
          ),
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: List.generate(_items.length, (i) {
              final sel = currentIndex == i;
              final item = _items[i];
              return Expanded(
                child: InkWell(
                  onTap: () => onChanged(i),
                  borderRadius: BorderRadius.circular(16),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          sel ? item.$2 : item.$1,
                          color: sel ? Colors.tealAccent : Colors.white70,
                          size: 22,
                        ),
                        const SizedBox(height: 3),
                        Text(
                          item.$3,
                          style: TextStyle(
                            fontSize: 10,
                            color:
                                sel ? Colors.tealAccent : Colors.white70,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            }),
          ),
        ),
      ),
    );
  }
}

class _AllMediaTab extends StatefulWidget {
  final DatabaseService db;
  const _AllMediaTab({required this.db});

  @override
  State<_AllMediaTab> createState() => _AllMediaTabState();
}

class _AllMediaTabState extends State<_AllMediaTab> {
  List<Map<String, dynamic>> _items = [];
  List<Map<String, dynamic>> _albums = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final items = await widget.db.getAllMediaItems();
    final albums = await widget.db.getAllAlbums();
    if (mounted) {
      setState(() {
        _items = items;
        _albums = albums;
        _loading = false;
      });
    }
  }

  Future<void> _import() async {
    setState(() => _loading = true);
    await MediaImporter.importMedia(context, widget.db);
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
            ListTile(
              leading:
                  const Icon(Icons.folder_open, color: Colors.tealAccent),
              title: const Text('Переместить в альбом',
                  style: TextStyle(color: Colors.white)),
              onTap: () => Navigator.pop(context, 'album'),
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

    if (action == 'fav') {
      await widget.db.toggleFavorite(item['id'], !isFav);
      _load();
    } else if (action == 'album') {
      await _pickAlbum(item['id']);
    } else if (action == 'delete') {
      await widget.db.softDeleteMediaItem(item['id']);
      _load();
    }
  }

  Future<void> _pickAlbum(int mediaId) async {
    final albums = await widget.db.getAllAlbums();
    if (!mounted) return;
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
                leading:
                    const Icon(Icons.folder_off, color: Colors.white54),
                title: const Text('Без альбома',
                    style: TextStyle(color: Colors.white)),
                onTap: () => Navigator.pop(context, {'id': null}),
              ),
              ...albums.map((a) => ListTile(
                    leading: const Icon(Icons.folder,
                        color: Colors.tealAccent),
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
      _load();
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(
          child: CircularProgressIndicator(color: Colors.tealAccent));
    }
    return Stack(
      children: [
        MediaGridWidget(
          items: _items,
          emptyMessage:
              'Хранилище пусто\nНажмите + чтобы добавить файл',
          onItemTap: _openViewer,
          onItemLongPress: _showItemMenu,
        ),
        Positioned(
          right: 16,
          bottom: 16,
          child: GlassButton(
            icon: const Icon(Icons.add, color: Colors.white),
            onTap: _import,
          ),
        ),
      ],
    );
  }
}

class _FavoritesTab extends StatefulWidget {
  final DatabaseService db;
  const _FavoritesTab({required this.db});

  @override
  State<_FavoritesTab> createState() => _FavoritesTabState();
}

class _FavoritesTabState extends State<_FavoritesTab> {
  List<Map<String, dynamic>> _items = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final items = await widget.db.getFavoriteMediaItems();
    if (mounted) {
      setState(() {
        _items = items;
        _loading = false;
      });
    }
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
              leading:
                  const Icon(Icons.favorite_border, color: Colors.pinkAccent),
              title: const Text('Убрать из избранного',
                  style: TextStyle(color: Colors.white)),
              onTap: () => Navigator.pop(context, 'fav'),
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

    if (action == 'fav') {
      await widget.db.toggleFavorite(item['id'], false);
      _load();
    } else if (action == 'delete') {
      await widget.db.softDeleteMediaItem(item['id']);
      _load();
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(
          child: CircularProgressIndicator(color: Colors.tealAccent));
    }
    return MediaGridWidget(
      items: _items,
      emptyMessage:
          'Нет избранных файлов\nОтметьте сердечком в просмотрщике',
      onItemTap: _openViewer,
      onItemLongPress: _showItemMenu,
    );
  }
}
