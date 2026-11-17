import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_windowmanager_plus/flutter_windowmanager_plus.dart';

import '../../core/app_settings_keys.dart';
import '../../core/app_theme_service.dart';
import '../../core/database_service.dart';
import '../../core/export_service.dart';
import '../../core/ui_helpers.dart';
import '../settings/settings_screen.dart';
import 'albums_screen.dart';
import 'folders_screen.dart';
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
  int _dataVersion = 0;
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

  void _bumpDataVersion() {
    if (mounted) setState(() => _dataVersion++);
  }

  void _changeTab(int i) {
    if (i == _currentTab) return;
    setState(() => _currentTab = i);
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
    } catch (e) {
      if (mounted) {
        showAppSnackBar(context, 'Не удалось изменить настройку', isError: true);
      }
    }
  }

  Future<void> _openSettings() async {
    bool dataChanged = false;
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => SettingsScreen(
          db: widget.db,
          onDataChanged: () => dataChanged = true,
        ),
      ),
    );
    if (!mounted) return;
    await _loadSecureSetting();
    if (!mounted) return;
    if (dataChanged) _bumpDataVersion();
  }

  String get _title {
    switch (_currentTab) {
      case 0: return 'Хранилище';
      case 1: return 'Папки';
      case 2: return 'Альбомы';
      case 3: return 'Избранное';
      case 4: return 'Корзина';
      default: return 'MediaVault';
    }
  }

  @override
  Widget build(BuildContext context) {
    final themeService = AppThemeService.instance;
    final brightness = Theme.of(context).brightness;
    final onSurface = Theme.of(context).colorScheme.onSurface;
    final isDark = brightness == Brightness.dark;
    final barColor =
        isDark ? const Color(0xF0101315) : const Color(0xF5FFFFFF);

    return AnimatedBuilder(
      animation: themeService,
      builder: (context, _) {
        return Scaffold(
          backgroundColor: Colors.transparent,
          body: Stack(
            children: [
              AnimatedContainer(
                duration: const Duration(milliseconds: 500),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: themeService.gradientFor(brightness),
                  ),
                ),
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
                    AllMediaTab(
                      db: widget.db,
                      dataVersion: _dataVersion,
                      onDataChanged: _bumpDataVersion,
                    ),
                    FoldersTab(
                      db: widget.db,
                      dataVersion: _dataVersion,
                      onDataChanged: _bumpDataVersion,
                    ),
                    AlbumsTab(
                      db: widget.db,
                      dataVersion: _dataVersion,
                      onDataChanged: _bumpDataVersion,
                    ),
                    FavoritesTab(
                      db: widget.db,
                      dataVersion: _dataVersion,
                      onDataChanged: _bumpDataVersion,
                    ),
                    TrashScreen(
                      db: widget.db,
                      dataVersion: _dataVersion,
                      onDataChanged: _bumpDataVersion,
                    ),
                  ],
                ),
              ),
              Positioned(
                top: 0,
                left: 0,
                right: 0,
                child: Container(
                  color: barColor,
                  child: AppBar(
                    backgroundColor: Colors.transparent,
                    elevation: 0,
                    title: Text(
                      _title,
                      style: TextStyle(
                          color: onSurface,
                          fontSize: 20,
                          fontWeight: FontWeight.w600),
                    ),
                    actions: [
                      Tooltip(
                        message: _secure
                            ? 'Разрешить скриншоты'
                            : 'Запретить скриншоты',
                        child: IconButton(
                          icon: Icon(
                            _secure
                                ? Icons.visibility_off
                                : Icons.visibility,
                            color: onSurface,
                          ),
                          onPressed: _toggleSecure,
                        ),
                      ),
                      Tooltip(
                        message: 'Настройки',
                        child: IconButton(
                          icon: Icon(Icons.settings_outlined,
                              color: onSurface),
                          onPressed: _openSettings,
                        ),
                      ),
                    ],
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
      },
    );
  }
}

class _GlassBottomNav extends StatelessWidget {
  final int currentIndex;
  final ValueChanged<int> onChanged;

  const _GlassBottomNav({required this.currentIndex, required this.onChanged});

  static const _items = [
    (Icons.photo_library_outlined, Icons.photo_library, 'Все'),
    (Icons.folder_outlined, Icons.folder, 'Папки'),
    (Icons.collections_bookmark_outlined, Icons.collections_bookmark, 'Альбомы'),
    (Icons.favorite_border, Icons.favorite, 'Избранное'),
    (Icons.delete_outline, Icons.delete, 'Корзина'),
  ];

  @override
  Widget build(BuildContext context) {
    final theme = AppThemeService.instance;
    final brightness = Theme.of(context).brightness;
    final isDark = brightness == Brightness.dark;
    final selected = theme.primaryColor;
    final unselected = Theme.of(context).colorScheme.onSurfaceVariant;
    final barColor =
        isDark ? const Color(0xF0101315) : const Color(0xF5FFFFFF);

    return Container(
      decoration: BoxDecoration(
        color: barColor,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: theme.glassBorderColor(brightness)),
      ),
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: List.generate(_items.length, (i) {
          final sel = currentIndex == i;
          final item = _items[i];
          return Expanded(
            child: Tooltip(
              message: item.$3,
              child: InkWell(
                onTap: () => onChanged(i),
                borderRadius: BorderRadius.circular(16),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(sel ? item.$2 : item.$1,
                          color: sel ? selected : unselected, size: 20),
                      const SizedBox(height: 3),
                      Text(
                        item.$3,
                        style: TextStyle(
                            fontSize: 9,
                            color: sel ? selected : unselected),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
        }),
      ),
    );
  }
}

Future<Map<String, dynamic>?> showAlbumPicker(
    BuildContext context, DatabaseService db) async {
  final albums = await db.getAllAlbums();
  if (!context.mounted) return null;
  return showDialog<Map<String, dynamic>?>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Выберите альбом'),
      content: SizedBox(
        width: double.maxFinite,
        child: ListView(
          shrinkWrap: true,
          children: [
            ListTile(
              leading: const Icon(Icons.folder_off),
              title: const Text('Без альбома'),
              onTap: () => Navigator.pop(ctx, {'id': null}),
            ),
            ...albums.map((a) => ListTile(
                  leading: const Icon(Icons.folder, color: Colors.tealAccent),
                  title: Text(a['name'] as String),
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
  final bool allSelected;
  final VoidCallback onClose;
  final VoidCallback onSelectAll;
  final VoidCallback? onFavorite;
  final String favoriteTooltip;
  final VoidCallback? onMove;
  final VoidCallback onExport;
  final VoidCallback onDelete;

  const _SelectionActionBar({
    required this.count,
    required this.allSelected,
    required this.onClose,
    required this.onSelectAll,
    required this.onExport,
    required this.onDelete,
    this.onFavorite,
    this.favoriteTooltip = 'В избранное',
    this.onMove,
  });

  @override
  Widget build(BuildContext context) {
    final brightness = Theme.of(context).brightness;
    final isDark = brightness == Brightness.dark;
    final onSurface = Theme.of(context).colorScheme.onSurface;
    final theme = AppThemeService.instance;
    final barColor =
        isDark ? const Color(0xF0101315) : const Color(0xF5FFFFFF);

    return Positioned(
      top: 8,
      left: 12,
      right: 12,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
        decoration: BoxDecoration(
          color: barColor,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: theme.glassBorderColor(brightness)),
        ),
        child: Row(
          children: [
            IconButton(
              visualDensity: VisualDensity.compact,
              icon: Icon(Icons.close, color: onSurface, size: 20),
              onPressed: onClose,
            ),
            Text(
              '$count',
              style: TextStyle(
                  color: onSurface,
                  fontWeight: FontWeight.w700,
                  fontSize: 15),
            ),
            const Spacer(),
            IconButton(
              visualDensity: VisualDensity.compact,
              tooltip: allSelected ? 'Снять выделение' : 'Выбрать всё',
              icon: Icon(
                  allSelected ? Icons.deselect : Icons.select_all,
                  color: onSurface,
                  size: 20),
              onPressed: onSelectAll,
            ),
            if (onFavorite != null)
              IconButton(
                visualDensity: VisualDensity.compact,
                tooltip: favoriteTooltip,
                icon: const Icon(Icons.favorite,
                    color: Colors.pinkAccent, size: 20),
                onPressed: onFavorite,
              ),
            if (onMove != null)
              IconButton(
                visualDensity: VisualDensity.compact,
                tooltip: 'В альбом',
                icon: const Icon(Icons.drive_file_move_outline,
                    color: Colors.tealAccent, size: 20),
                onPressed: onMove,
              ),
            IconButton(
              visualDensity: VisualDensity.compact,
              tooltip: 'Экспортировать',
              icon: Icon(Icons.ios_share, color: onSurface, size: 20),
              onPressed: onExport,
            ),
            IconButton(
              visualDensity: VisualDensity.compact,
              tooltip: 'В корзину',
              icon: const Icon(Icons.delete_outline,
                  color: Colors.redAccent, size: 20),
              onPressed: onDelete,
            ),
          ],
        ),
      ),
    );
  }
}

Future<bool> confirmDelete(BuildContext context, int count) async {
  final r = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title:
          Text('Удалить $count ${_plural(count, 'файл', 'файла', 'файлов')}?'),
      content: const Text('Файлы попадут в корзину.'),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: const Text('Отмена'),
        ),
        TextButton(
          onPressed: () => Navigator.pop(ctx, true),
          child:
              const Text('Удалить', style: TextStyle(color: Colors.redAccent)),
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

Future<void> _runExport(
    BuildContext context, DatabaseService db, List<int> ids) async {
  if (ids.isEmpty) return;
  final progress = ValueNotifier<(int, int)>((0, ids.length));

  showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (ctx) => AlertDialog(
      title: const Text('Экспорт'),
      content: ValueListenableBuilder<(int, int)>(
        valueListenable: progress,
        builder: (ctx, value, _) {
          final (p, t) = value;
          return Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              LinearProgressIndicator(
                value: t > 0 ? p / t : null,
                minHeight: 4,
                backgroundColor: Colors.white12,
                valueColor: const AlwaysStoppedAnimation(Colors.tealAccent),
              ),
              const SizedBox(height: 12),
              Text('$p / $t'),
            ],
          );
        },
      ),
    ),
  );

  try {
    await ExportService.exportAndShare(
      db,
      ids,
      onProgress: (p, t) => progress.value = (p, t),
    );
  } catch (e) {
    if (context.mounted) {
      showAppSnackBar(context, 'Экспорт не удался: $e', isError: true);
    }
  } finally {
    progress.dispose();
    if (context.mounted) Navigator.of(context, rootNavigator: true).pop();
  }
}

class AllMediaTab extends StatefulWidget {
  final DatabaseService db;
  final int dataVersion;
  final VoidCallback? onDataChanged;

  const AllMediaTab({
    super.key,
    required this.db,
    required this.dataVersion,
    this.onDataChanged,
  });

  @override
  State<AllMediaTab> createState() => _AllMediaTabState();
}

class _AllMediaTabState extends State<AllMediaTab> {
  final TextEditingController _searchCtrl = TextEditingController();
  Timer? _searchDebounce;

  List<Map<String, dynamic>> _items = [];
  bool _loading = true;
  String _searchQuery = '';

  bool _selectionMode = false;
  final Set<int> _selectedIds = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant AllMediaTab old) {
    super.didUpdateWidget(old);
    if (old.dataVersion != widget.dataVersion) {
      _load();
    }
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final items = _searchQuery.isEmpty
        ? await widget.db.getAllMediaItems()
        : await widget.db.searchMediaItems(_searchQuery);
    if (!mounted) return;
    setState(() {
      _items = items;
      _loading = false;
      final validIds = items.map((e) => e['id'] as int).toSet();
      _selectedIds.removeWhere((id) => !validIds.contains(id));
      if (_selectedIds.isEmpty) _selectionMode = false;
    });
  }

  void _onSearchChanged(String q) {
    _searchDebounce?.cancel();
    _searchDebounce = Timer(const Duration(milliseconds: 250), () {
      if (!mounted) return;
      final trimmed = q.trim();
      if (trimmed == _searchQuery) return;
      _searchQuery = trimmed;
      _selectionMode = false;
      _selectedIds.clear();
      _load();
    });
  }

  Future<void> _showImportMenu() async {
    final action = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: Theme.of(context).bottomSheetTheme.backgroundColor,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 16),
            ListTile(
              leading: const Icon(Icons.photo_library_outlined,
                  color: Colors.tealAccent),
              title: Text('Выбрать файлы',
                  style: TextStyle(
                      color: Theme.of(ctx).colorScheme.onSurface)),
              onTap: () => Navigator.pop(ctx, 'files'),
            ),
            ListTile(
              leading:
                  const Icon(Icons.folder_open, color: Colors.tealAccent),
              title: Text('Импорт папки',
                  style: TextStyle(
                      color: Theme.of(ctx).colorScheme.onSurface)),
              subtitle: Text('С сохранением структуры',
                  style: TextStyle(
                      color: Theme.of(ctx)
                          .colorScheme
                          .onSurfaceVariant)),
              onTap: () => Navigator.pop(ctx, 'folder'),
            ),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
    if (!mounted) return;

    int count = 0;
    if (action == 'files') {
      count = await MediaImporter.importFiles(context, widget.db);
    } else if (action == 'folder') {
      count = await MediaImporter.importFolder(context, widget.db);
    }
    if (!mounted || count == 0) return;
    widget.onDataChanged?.call();
  }

  Future<void> _openViewer(int index) async {
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
    if (!mounted) return;
    if (changed == true) widget.onDataChanged?.call();
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
      if (!_selectedIds.remove(id)) _selectedIds.add(id);
      if (_selectedIds.isEmpty) _selectionMode = false;
    });
  }

  void _exitSelection() {
    setState(() {
      _selectionMode = false;
      _selectedIds.clear();
    });
  }

  void _toggleSelectAll() {
    setState(() {
      final allIds = _items.map((e) => e['id'] as int).toSet();
      if (_selectedIds.length == allIds.length) {
        _selectedIds.clear();
        _selectionMode = false;
      } else {
        _selectedIds
          ..clear()
          ..addAll(allIds);
      }
    });
  }

  Future<void> _massFavorite() async {
    for (final id in _selectedIds.toList()) {
      await widget.db.toggleFavorite(id, true);
    }
    _exitSelection();
    widget.onDataChanged?.call();
  }

  Future<void> _massMove() async {
    final result = await showAlbumPicker(context, widget.db);
    if (result == null) return;
    final albumId = result['id'] as int?;
    for (final id in _selectedIds.toList()) {
      await widget.db.moveMediaToAlbum(id, albumId);
    }
    _exitSelection();
    widget.onDataChanged?.call();
  }

  Future<void> _massDelete() async {
    if (!await confirmDelete(context, _selectedIds.length)) return;
    for (final id in _selectedIds.toList()) {
      await widget.db.softDeleteMediaItem(id);
    }
    _exitSelection();
    widget.onDataChanged?.call();
  }

  Future<void> _massExport() async {
    await _runExport(context, widget.db, _selectedIds.toList());
  }

  Widget _buildSearchBar() {
    final brightness = Theme.of(context).brightness;
    final isDark = brightness == Brightness.dark;
    final onSurface = Theme.of(context).colorScheme.onSurface;
    final hint = onSurface.withValues(alpha: 0.5);
    final barColor =
        isDark ? const Color(0xF0101315) : const Color(0xF5FFFFFF);

    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 0, 4, 8),
      child: TextField(
        controller: _searchCtrl,
        onChanged: _onSearchChanged,
        style: TextStyle(color: onSurface, fontSize: 13),
        decoration: InputDecoration(
          hintText: 'Поиск по файлам',
          hintStyle: TextStyle(color: hint, fontSize: 13),
          prefixIcon: Icon(Icons.search, color: hint, size: 20),
          suffixIcon: _searchQuery.isNotEmpty
              ? IconButton(
                  icon: Icon(Icons.clear, color: hint, size: 18),
                  onPressed: () {
                    _searchCtrl.clear();
                    _onSearchChanged('');
                  },
                )
              : null,
          filled: true,
          fillColor: barColor,
          contentPadding:
              const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
          isDense: true,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: BorderSide.none,
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(
          child: CircularProgressIndicator(color: Colors.tealAccent));
    }

    final allSelected =
        _items.isNotEmpty && _selectedIds.length == _items.length;

    return Column(
      children: [
        if (!_selectionMode) _buildSearchBar(),
        Expanded(
          child: Stack(
            children: [
              MediaGridWidget(
                items: _items,
                emptyMessage: _searchQuery.isEmpty
                    ? 'Хранилище пусто\nНажмите + чтобы добавить файлы'
                    : 'Ничего не найдено по «$_searchQuery»',
                onItemTap: _openViewer,
                onItemLongPress: _startSelection,
                selectedIds: _selectionMode ? _selectedIds : null,
                onSelectionToggle: _toggleSelection,
              ),
              if (_selectionMode)
                _SelectionActionBar(
                  count: _selectedIds.length,
                  allSelected: allSelected,
                  onClose: _exitSelection,
                  onSelectAll: _toggleSelectAll,
                  onFavorite: _massFavorite,
                  onMove: _massMove,
                  onExport: _massExport,
                  onDelete: _massDelete,
                ),
              if (!_selectionMode)
                Positioned(
                  right: 16,
                  bottom: 16,
                  child: FloatingActionButton(
                    backgroundColor: Colors.teal,
                    foregroundColor: Colors.white,
                    onPressed: _showImportMenu,
                    child: const Icon(Icons.add),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class FavoritesTab extends StatefulWidget {
  final DatabaseService db;
  final int dataVersion;
  final VoidCallback? onDataChanged;

  const FavoritesTab({
    super.key,
    required this.db,
    required this.dataVersion,
    this.onDataChanged,
  });

  @override
  State<FavoritesTab> createState() => _FavoritesTabState();
}

class _FavoritesTabState extends State<FavoritesTab> {
  List<Map<String, dynamic>> _items = [];
  bool _loading = true;
  bool _selectionMode = false;
  final Set<int> _selectedIds = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant FavoritesTab old) {
    super.didUpdateWidget(old);
    if (old.dataVersion != widget.dataVersion) {
      _load();
    }
  }

  Future<void> _load() async {
    final items = await widget.db.getFavoriteMediaItems();
    if (!mounted) return;
    setState(() {
      _items = items;
      _loading = false;
      final validIds = items.map((e) => e['id'] as int).toSet();
      _selectedIds.removeWhere((id) => !validIds.contains(id));
      if (_selectedIds.isEmpty) _selectionMode = false;
    });
  }

  Future<void> _openViewer(int index) async {
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
    if (!mounted) return;
    if (changed == true) widget.onDataChanged?.call();
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
      if (!_selectedIds.remove(id)) _selectedIds.add(id);
      if (_selectedIds.isEmpty) _selectionMode = false;
    });
  }

  void _exitSelection() {
    setState(() {
      _selectionMode = false;
      _selectedIds.clear();
    });
  }

  void _toggleSelectAll() {
    setState(() {
      final allIds = _items.map((e) => e['id'] as int).toSet();
      if (_selectedIds.length == allIds.length) {
        _selectedIds.clear();
        _selectionMode = false;
      } else {
        _selectedIds
          ..clear()
          ..addAll(allIds);
      }
    });
  }

  Future<void> _massUnfavorite() async {
    for (final id in _selectedIds.toList()) {
      await widget.db.toggleFavorite(id, false);
    }
    _exitSelection();
    widget.onDataChanged?.call();
  }

  Future<void> _massDelete() async {
    if (!await confirmDelete(context, _selectedIds.length)) return;
    for (final id in _selectedIds.toList()) {
      await widget.db.softDeleteMediaItem(id);
    }
    _exitSelection();
    widget.onDataChanged?.call();
  }

  Future<void> _massExport() async {
    await _runExport(context, widget.db, _selectedIds.toList());
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(
          child: CircularProgressIndicator(color: Colors.tealAccent));
    }

    final allSelected =
        _items.isNotEmpty && _selectedIds.length == _items.length;

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
            allSelected: allSelected,
            onClose: _exitSelection,
            onSelectAll: _toggleSelectAll,
            onFavorite: _massUnfavorite,
            favoriteTooltip: 'Убрать из избранного',
            onExport: _massExport,
            onDelete: _massDelete,
          ),
      ],
    );
  }
}
