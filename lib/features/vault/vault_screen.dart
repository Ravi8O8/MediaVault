import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_windowmanager_plus/flutter_windowmanager_plus.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';

import '../../core/app_settings_keys.dart';
import '../../core/database_service.dart';
import '../settings/settings_screen.dart';
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
  static const _storage = FlutterSecureStorage();

  int _currentTab = 0;
  int _tabReloadKey = 0;
  bool _secure = false;

  @override
  void initState() {
    super.initState();
    _loadSecureSetting();
  }

  Future<void> _loadSecureSetting() async {
    String? raw;
    try {
      raw = await _storage.read(key: AppSettingsKeys.secureScreenshots);
    } catch (_) {}
    final secure = raw == 'true';
    try {
      await FlutterWindowManagerPlus.setSecure(secure);
    } catch (_) {}
    if (mounted) setState(() => _secure = secure);
  }

  void _changeTab(int i) {
    if (i == _currentTab) return;
    setState(() {
      _currentTab = i;
      _tabReloadKey++;
    });
  }

  Future<void> _toggleSecure() async {
    final next = !_secure;
    setState(() => _secure = next);
    try {
      await FlutterWindowManagerPlus.setSecure(next);
      await _storage.write(
        key: AppSettingsKeys.secureScreenshots,
        value: next ? 'true' : 'false',
      );
    } catch (_) {}
  }

  Future<void> _openSettings() async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => SettingsScreen(db: widget.db),
      ),
    );
    if (!mounted) return;
    await _loadSecureSetting();
    if (!mounted) return;
    setState(() => _tabReloadKey++);
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
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Stack(
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
              top: MediaQuery.of(context).padding.top + kToolbarHeight + 8,
              bottom: 96,
              left: 8,
              right: 8,
            ),
            child: IndexedStack(
              index: _currentTab,
              children: [
                _AllMediaTab(
                  key: ValueKey('all_$_tabReloadKey'),
                  db: widget.db,
                ),
                AlbumsTab(
                  key: ValueKey('albums_$_tabReloadKey'),
                  db: widget.db,
                ),
                _FavoritesTab(
                  key: ValueKey('fav_$_tabReloadKey'),
                  db: widget.db,
                ),
                TrashScreen(
                  key: ValueKey('trash_$_tabReloadKey'),
                  db: widget.db,
                ),
              ],
            ),
          ),
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: ClipRect(
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                child: AppBar(
                  backgroundColor: Colors.white.withValues(alpha: 0.05),
                  elevation: 0,
                  title: Text(
                    _title,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 20,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  actions: [
                    IconButton(
                      icon: Icon(
                        _secure ? Icons.visibility_off : Icons.visibility,
                        color: Colors.white,
                      ),
                      onPressed: _toggleSecure,
                    ),
                    IconButton(
                      icon: const Icon(
                        Icons.settings_outlined,
                        color: Colors.white,
                      ),
                      onPressed: _openSettings,
                    ),
                  ],
                ),
              ),
            ),
          ),
          Positioned(
            left: 16,
            right: 16,
            bottom: 16,
            child: _GlassBottomNav(
              currentIndex: _currentTab,
              onChanged: _changeTab,
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

// ---------- Общие хелперы ----------

Future<Map<String, dynamic>?> showAlbumPicker(
  BuildContext context,
  DatabaseService db,
) async {
  final albums = await db.getAllAlbums();
  if (!context.mounted) return null;
  return showDialog<Map<String, dynamic>?>(
    context: context,
    builder: (ctx) => AlertDialog(
      backgroundColor: const Color(0xFF232526),
      title: const Text(
        'Выберите альбом',
        style: TextStyle(color: Colors.white),
      ),
      content: SizedBox(
        width: double.maxFinite,
        child: ListView(
          shrinkWrap: true,
          children: [
            ListTile(
              leading: const Icon(Icons.folder_off, color: Colors.white54),
              title: const Text(
                'Без альбома',
                style: TextStyle(color: Colors.white),
              ),
              onTap: () => Navigator.pop(ctx, {'id': null}),
            ),
            ...albums.map((a) => ListTile(
                  leading: const Icon(Icons.folder, color: Colors.tealAccent),
                  title: Text(
                    a['name'] as String,
                    style: const TextStyle(color: Colors.white),
                  ),
                  onTap: () => Navigator.pop(ctx, a),
                )),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, null),
          child: const Text('Отмена'),
        ),
      ],
    ),
  );
}

class _SelectionActionBar extends StatelessWidget {
  final int count;
  final VoidCallback onClose;
  final VoidCallback onDelete;

  /// Если null — кнопка «в избранное» скрыта.
  final VoidCallback? onFavorite;

  /// Если null — кнопка «в альбом» скрыта.
  final VoidCallback? onMove;

  const _SelectionActionBar({
    required this.count,
    required this.onClose,
    required this.onDelete,
    this.onFavorite,
    this.onMove,
  });

  @override
  Widget build(BuildContext context) {
    return Positioned(
      top: 8,
      left: 12,
      right: 12,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: Colors.white.withValues(alpha: 0.15),
              ),
            ),
            child: Row(
              children: [
                IconButton(
                  icon: const Icon(Icons.close, color: Colors.white),
                  onPressed: onClose,
                ),
                Text(
                  '$count',
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                    fontSize: 16,
                  ),
                ),
                const Spacer(),
                if (onFavorite != null)
                  IconButton(
                    tooltip: 'В избранное',
                    icon: const Icon(
                      Icons.favorite,
                      color: Colors.pinkAccent,
                    ),
                    onPressed: onFavorite,
                  ),
                if (onMove != null)
                  IconButton(
                    tooltip: 'В альбом',
                    icon: const Icon(
                      Icons.drive_file_move_outline,
                      color: Colors.tealAccent,
                    ),
                    onPressed: onMove,
                  ),
                IconButton(
                  tooltip: 'В корзину',
                  icon: const Icon(
                    Icons.delete_outline,
                    color: Colors.redAccent,
                  ),
                  onPressed: onDelete,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

Future<bool> confirmDelete(BuildContext context, int count) async {
  final r = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      backgroundColor: const Color(0xFF232526),
      title: Text(
        'Удалить $count ${_plural(count, 'файл', 'файла', 'файлов')}?',
        style: const TextStyle(color: Colors.white),
      ),
      content: const Text(
        'Файлы попадут в корзину.',
        style: TextStyle(color: Colors.white70),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: const Text('Отмена'),
        ),
        TextButton(
          onPressed: () => Navigator.pop(ctx, true),
          child: const Text(
            'Удалить',
            style: TextStyle(color: Colors.redAccent),
          ),
        ),
      ],
    ),
  );
  return r ?? false;
}

String _plural(int n, String one, String few, String many) {
  final mod10 = n % 10;
  final mod100 = n % 100;
  if (mod10 == 1 && mod100 != 11) return one;
  if (mod10 >= 2 && mod10 <= 4 && (mod100 < 12 || mod100 > 14)) return few;
  return many;
}

// ---------- All Media Tab ----------

class _AllMediaTab extends StatefulWidget {
  final DatabaseService db;
  const _AllMediaTab({super.key, required this.db});

  @override
  State<_AllMediaTab> createState() => _AllMediaTabState();
}

class _AllMediaTabState extends State<_AllMediaTab> {
  List<Map<String, dynamic>> _items = [];
  bool _loading = true;

  bool _selectionMode = false;
  final Set<int> _selectedIds = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final items = await widget.db.getAllMediaItems();
    if (mounted) {
      setState(() {
        _items = items;
        _loading = false;
        final validIds = items.map((e) => e['id'] as int).toSet();
        _selectedIds.removeWhere((id) => !validIds.contains(id));
        if (_selectedIds.isEmpty) _selectionMode = false;
      });
    }
  }

  Future<void> _import() async {
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

  void _startSelection(int index) {
    setState(() {
      _selectionMode = true;
      _selectedIds.add(_items[index]['id'] as int);
    });
  }

  void _toggleSelection(int index) {
    final id = _items[index]['id'] as int;
    setState(() {
      if (!_selectedIds.remove(id)) {
        _selectedIds.add(id);
      }
      if (_selectedIds.isEmpty) _selectionMode = false;
    });
  }

  void _exitSelection() {
    setState(() {
      _selectionMode = false;
      _selectedIds.clear();
    });
  }

  Future<void> _massFavorite() async {
    final ids = _selectedIds.toList();
    for (final id in ids) {
      await widget.db.toggleFavorite(id, true);
    }
    _exitSelection();
    _load();
  }

  Future<void> _massMove() async {
    final result = await showAlbumPicker(context, widget.db);
    if (result == null) return;
    final albumId = result['id'] as int?;
    final ids = _selectedIds.toList();
    for (final id in ids) {
      await widget.db.moveMediaToAlbum(id, albumId);
    }
    _exitSelection();
    _load();
  }

  Future<void> _massDelete() async {
    final ok = await confirmDelete(context, _selectedIds.length);
    if (!ok) return;
    final ids = _selectedIds.toList();
    for (final id in ids) {
      await widget.db.softDeleteMediaItem(id);
    }
    _exitSelection();
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
        MediaGridWidget(
          items: _items,
          emptyMessage:
              'Хранилище пусто\nНажмите + чтобы добавить файлы',
          onItemTap: _openViewer,
          onItemLongPress: _startSelection,
          selectedIds: _selectionMode ? _selectedIds : null,
          onSelectionToggle: _toggleSelection,
        ),
        if (_selectionMode)
          _SelectionActionBar(
            count: _selectedIds.length,
            onClose: _exitSelection,
            onFavorite: _massFavorite,
            onMove: _massMove,
            onDelete: _massDelete,
          ),
        if (!_selectionMode)
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

// ---------- Favorites Tab ----------

class _FavoritesTab extends StatefulWidget {
  final DatabaseService db;
  const _FavoritesTab({super.key, required this.db});

  @override
  State<_FavoritesTab> createState() => _FavoritesTabState();
}

class _FavoritesTabState extends State<_FavoritesTab> {
  List<Map<String, dynamic>> _items = [];
  bool _loading = true;

  bool _selectionMode = false;
  final Set<int> _selectedIds = {};

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
        final validIds = items.map((e) => e['id'] as int).toSet();
        _selectedIds.removeWhere((id) => !validIds.contains(id));
        if (_selectedIds.isEmpty) _selectionMode = false;
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

  void _startSelection(int index) {
    setState(() {
      _selectionMode = true;
      _selectedIds.add(_items[index]['id'] as int);
    });
  }

  void _toggleSelection(int index) {
    final id = _items[index]['id'] as int;
    setState(() {
      if (!_selectedIds.remove(id)) {
        _selectedIds.add(id);
      }
      if (_selectedIds.isEmpty) _selectionMode = false;
    });
  }

  void _exitSelection() {
    setState(() {
      _selectionMode = false;
      _selectedIds.clear();
    });
  }

  Future<void> _massUnfavorite() async {
    final ids = _selectedIds.toList();
    for (final id in ids) {
      await widget.db.toggleFavorite(id, false);
    }
    _exitSelection();
    _load();
  }

  Future<void> _massDelete() async {
    final ok = await confirmDelete(context, _selectedIds.length);
    if (!ok) return;
    final ids = _selectedIds.toList();
    for (final id in ids) {
      await widget.db.softDeleteMediaItem(id);
    }
    _exitSelection();
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
        MediaGridWidget(
          items: _items,
          emptyMessage:
              'Нет избранных файлов\nОтметьте сердечком в просмотрщике',
          onItemTap: _openViewer,
          onItemLongPress: _startSelection,
          selectedIds: _selectionMode ? _selectedIds : null,
          onSelectionToggle: _toggleSelection,
        ),
        if (_selectionMode)
          _SelectionActionBar(
            count: _selectedIds.length,
            onClose: _exitSelection,
            onFavorite: _massUnfavorite,
            // onMove не передаём → иконка «в альбом» скрыта
            onDelete: _massDelete,
          ),
      ],
    );
  }
}
