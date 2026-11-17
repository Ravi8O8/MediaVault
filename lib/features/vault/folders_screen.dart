import 'package:flutter/material.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';

import '../../core/app_theme_service.dart';
import '../../core/database_service.dart';
import 'media_grid_widget.dart';
import 'media_viewer_screen.dart';

class FoldersTab extends StatefulWidget {
  final DatabaseService db;
  final int dataVersion;
  final VoidCallback? onDataChanged;

  const FoldersTab({
    super.key,
    required this.db,
    required this.dataVersion,
    this.onDataChanged,
  });

  @override
  State<FoldersTab> createState() => _FoldersTabState();
}

class _FoldersTabState extends State<FoldersTab> {
  List<String> _subfolders = [];
  List<Map<String, dynamic>> _files = [];
  bool _loading = true;
  bool _hasAny = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant FoldersTab old) {
    super.didUpdateWidget(old);
    if (old.dataVersion != widget.dataVersion) {
      _load();
    }
  }

  Future<void> _load() async {
    final subs = await widget.db.getSubfolders('');
    final files = await widget.db.getMediaByFolder('');
    final countWithout = await widget.db.countFilesWithoutFolder();
    final allFolders = await widget.db.getAllFolderPaths();

    if (!mounted) return;
    setState(() {
      _subfolders = subs;
      _files = files;
      _loading = false;
      _hasAny = allFolders.isNotEmpty || countWithout > 0;
    });
  }

  Future<int> _countInSubtree(String path) async {
    final allFolders = await widget.db.getAllFolderPaths();
    int total = 0;
    for (final f in allFolders) {
      if (f == path || f.startsWith('$path/')) {
        total += await widget.db.countFilesInFolder(f);
      }
    }
    return total;
  }

  Future<void> _importFiles() async {
    final count = await MediaImporter.importFiles(context, widget.db);
    if (!mounted || count == 0) return;
    widget.onDataChanged?.call();
  }

  Future<void> _importFolder() async {
    final count = await MediaImporter.importFolder(context, widget.db);
    if (!mounted || count == 0) return;
    widget.onDataChanged?.call();
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
              leading: const Icon(Icons.folder_open, color: Colors.tealAccent),
              title: Text('Импорт папки',
                  style: TextStyle(
                      color: Theme.of(ctx).colorScheme.onSurface)),
              subtitle: Text('С сохранением структуры',
                  style: TextStyle(
                      color: Theme.of(ctx).colorScheme.onSurfaceVariant)),
              onTap: () => Navigator.pop(ctx, 'folder'),
            ),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );

    if (action == 'files') {
      await _importFiles();
    } else if (action == 'folder') {
      await _importFolder();
    }
  }

  void _openSubfolder(String name) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => _FolderBrowserScreen(
          db: widget.db,
          initialPath: name,
          onDataChanged: widget.onDataChanged,
        ),
      ),
    ).then((_) => _load());
  }

  void _openRootFiles() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => _FolderBrowserScreen(
          db: widget.db,
          initialPath: '',
          onDataChanged: widget.onDataChanged,
        ),
      ),
    ).then((_) => _load());
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(
          child: CircularProgressIndicator(color: Colors.tealAccent));
    }

    final onSurface = Theme.of(context).colorScheme.onSurface;

    return Stack(
      children: [
        if (!_hasAny)
          Center(
            child: Padding(
              padding: const EdgeInsets.all(32),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.folder_open,
                      size: 56, color: onSurface.withValues(alpha: 0.3)),
                  const SizedBox(height: 16),
                  Text(
                    'Нет папок',
                    style: TextStyle(
                        color: onSurface.withValues(alpha: 0.6),
                        fontSize: 16,
                        fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Импортируйте папку с сохранением структуры',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                        color: onSurface.withValues(alpha: 0.4),
                        fontSize: 13),
                  ),
                ],
              ),
            ),
          )
        else
          ListView(
            padding: const EdgeInsets.fromLTRB(4, 4, 4, 80),
            children: [
              if (_files.isNotEmpty)
                _FolderTile(
                  name: 'Без папки',
                  subtitle: 'Импортированы по одному',
                  count: _files.length,
                  icon: Icons.insert_drive_file_outlined,
                  isFileGroup: true,
                  onTap: _openRootFiles,
                ),
              ..._subfolders.map((name) {
                return FutureBuilder<int>(
                  future: _countInSubtree(name),
                  builder: (ctx, snap) {
                    return _FolderTile(
                      name: name,
                      subtitle: '',
                      count: snap.data ?? 0,
                      icon: Icons.folder,
                      onTap: () => _openSubfolder(name),
                    );
                  },
                );
              }),
            ],
          ),
        Positioned(
          right: 16,
          bottom: 16,
          child: GlassButton(
            icon: const Icon(Icons.add, color: Colors.white),
            onTap: _showImportMenu,
          ),
        ),
      ],
    );
  }
}

class _FolderTile extends StatelessWidget {
  final String name;
  final String subtitle;
  final int count;
  final IconData icon;
  final bool isFileGroup;
  final VoidCallback onTap;

  const _FolderTile({
    required this.name,
    required this.subtitle,
    required this.count,
    required this.icon,
    required this.onTap,
    this.isFileGroup = false,
  });

  @override
  Widget build(BuildContext context) {
    final theme = AppThemeService.instance;
    final brightness = Theme.of(context).brightness;
    final onSurface = Theme.of(context).colorScheme.onSurface;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            decoration: BoxDecoration(
              color: theme.glassCardTop(brightness),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: theme.glassBorderColor(brightness)),
            ),
            child: Row(
              children: [
                Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [
                        theme.primaryColor.withValues(alpha: 0.4),
                        theme.primaryColor.withValues(alpha: 0.1),
                      ],
                    ),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(icon, color: theme.primaryColor, size: 22),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: onSurface,
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      if (subtitle.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 2),
                          child: Text(
                            subtitle,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: onSurface.withValues(alpha: 0.5),
                              fontSize: 12,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                Text(
                  '$count',
                  style: TextStyle(
                    color: theme.primaryColor,
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(width: 4),
                Icon(Icons.chevron_right,
                    color: onSurface.withValues(alpha: 0.3), size: 20),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _FolderBrowserScreen extends StatefulWidget {
  final DatabaseService db;
  final String initialPath;
  final VoidCallback? onDataChanged;

  const _FolderBrowserScreen({
    required this.db,
    required this.initialPath,
    this.onDataChanged,
  });

  @override
  State<_FolderBrowserScreen> createState() => _FolderBrowserScreenState();
}

class _FolderBrowserScreenState extends State<_FolderBrowserScreen> {
  late String _currentPath;
  List<String> _subfolders = [];
  List<Map<String, dynamic>> _files = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _currentPath = widget.initialPath;
    _load();
  }

  Future<void> _load() async {
    final subs = await widget.db.getSubfolders(_currentPath);
    final files = await widget.db.getMediaByFolder(_currentPath);
    if (!mounted) return;
    setState(() {
      _subfolders = subs;
      _files = files;
      _loading = false;
    });
  }

  void _enterFolder(String name) {
    setState(() {
      _currentPath =
          _currentPath.isEmpty ? name : '$_currentPath/$name';
      _loading = true;
    });
    _load();
  }

  void _goBack() {
    if (_currentPath.isEmpty) {
      Navigator.pop(context);
      return;
    }
    final parts = _currentPath.split('/');
    parts.removeLast();
    setState(() {
      _currentPath = parts.join('/');
      _loading = true;
    });
    _load();
  }

  void _jumpTo(String path) {
    setState(() {
      _currentPath = path;
      _loading = true;
    });
    _load();
  }

  Future<void> _openViewer(int index) async {
    final changed = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => MediaViewerScreen(
          items: _files,
          initialIndex: index,
          db: widget.db,
        ),
      ),
    );
    if (!mounted) return;
    await _load();
    if (changed == true) widget.onDataChanged?.call();
  }

  Future<void> _showItemMenu(int index) async {
    final item = _files[index];
    final isFav = (item['is_favorite'] as int? ?? 0) == 1;
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
              leading: Icon(
                  isFav ? Icons.favorite : Icons.favorite_border,
                  color: Colors.pinkAccent),
              title: Text(
                  isFav ? 'Убрать из избранного' : 'В избранное',
                  style: TextStyle(
                      color: Theme.of(ctx).colorScheme.onSurface)),
              onTap: () => Navigator.pop(ctx, 'fav'),
            ),
            ListTile(
              leading: const Icon(Icons.delete_outline,
                  color: Colors.redAccent),
              title: Text('В корзину',
                  style: TextStyle(
                      color: Theme.of(ctx).colorScheme.onSurface)),
              onTap: () => Navigator.pop(ctx, 'delete'),
            ),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );

    if (action == 'fav') {
      await widget.db.toggleFavorite(item['id'], !isFav);
      await _load();
      widget.onDataChanged?.call();
    } else if (action == 'delete') {
      await widget.db.softDeleteMediaItem(item['id']);
      widget.onDataChanged?.call();
      if (mounted) Navigator.pop(context);
    }
  }

  List<Widget> _buildBreadcrumbs() {
    final parts = _currentPath.isEmpty ? <String>[] : _currentPath.split('/');
    final crumbs = <Widget>[];

    crumbs.add(
      GestureDetector(
        onTap: () => _jumpTo(''),
        child: Text(
          'Корень',
          style: TextStyle(
            color: parts.isEmpty
                ? AppThemeService.instance.primaryColor
                : Colors.white70,
            fontSize: 13,
            fontWeight: parts.isEmpty ? FontWeight.w600 : FontWeight.normal,
          ),
        ),
      ),
    );

    String acc = '';
    for (int i = 0; i < parts.length; i++) {
      acc = acc.isEmpty ? parts[i] : '$acc/${parts[i]}';
      final target = acc;
      final isLast = i == parts.length - 1;
      crumbs.add(const Padding(
        padding: EdgeInsets.symmetric(horizontal: 6),
        child: Icon(Icons.chevron_right, size: 14, color: Colors.white38),
      ));
      crumbs.add(
        GestureDetector(
          onTap: () => _jumpTo(target),
          child: Text(
            parts[i],
            style: TextStyle(
              color: isLast
                  ? AppThemeService.instance.primaryColor
                  : Colors.white70,
              fontSize: 13,
              fontWeight: isLast ? FontWeight.w600 : FontWeight.normal,
            ),
          ),
        ),
      );
    }

    return crumbs;
  }

  @override
  Widget build(BuildContext context) {
    final themeService = AppThemeService.instance;
    final brightness = Theme.of(context).brightness;

    return AnimatedBuilder(
      animation: themeService,
      builder: (context, _) {
        return Scaffold(
          backgroundColor: Colors.transparent,
          extendBodyBehindAppBar: true,
          body: Stack(
            children: [
              // ⬇️ ГРАДИЕНТНЫЙ ФОН — тот же, что в VaultScreen
              AnimatedContainer(
                duration: const Duration(milliseconds: 400),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: themeService.gradientFor(brightness),
                  ),
                ),
              ),
              SafeArea(
                child: Padding(
                  padding: EdgeInsets.fromLTRB(
                    8,
                    MediaQuery.of(context).padding.top + kToolbarHeight + 12,
                    8,
                    8,
                  ),
                  child: _loading
                      ? const Center(
                          child: CircularProgressIndicator(
                              color: Colors.tealAccent))
                      : CustomScrollView(
                          slivers: [
                            if (_subfolders.isNotEmpty)
                              SliverPadding(
                                padding:
                                    const EdgeInsets.fromLTRB(4, 0, 4, 8),
                                sliver: SliverList(
                                  delegate: SliverChildBuilderDelegate(
                                    (ctx, i) {
                                      final name = _subfolders[i];
                                      return Padding(
                                        padding:
                                            const EdgeInsets.only(bottom: 6),
                                        child: _FolderTile(
                                          name: name,
                                          subtitle: '',
                                          count: 0,
                                          icon: Icons.folder,
                                          onTap: () => _enterFolder(name),
                                        ),
                                      );
                                    },
                                    childCount: _subfolders.length,
                                  ),
                                ),
                              ),
                            if (_files.isNotEmpty)
                              SliverFillRemaining(
                                hasScrollBody: false,
                                child: SizedBox(
                                  height: 400,
                                  child: MediaGridWidget(
                                    items: _files,
                                    emptyMessage: 'В папке пусто',
                                    onItemTap: _openViewer,
                                    onItemLongPress: _showItemMenu,
                                  ),
                                ),
                              )
                            else if (_subfolders.isEmpty)
                              const SliverFillRemaining(
                                child: Center(
                                  child: Text(
                                    'Пусто',
                                    style: TextStyle(color: Colors.white54),
                                  ),
                                ),
                              ),
                          ],
                        ),
                ),
              ),
              // AppBar поверх (прозрачный)
              Positioned(
                top: 0,
                left: 0,
                right: 0,
                child: AppBar(
                  backgroundColor: Colors.transparent,
                  elevation: 0,
                  leading: IconButton(
                    icon: Icon(Icons.arrow_back,
                        color: Theme.of(context).colorScheme.onSurface),
                    onPressed: _goBack,
                  ),
                  title: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(children: _buildBreadcrumbs()),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
