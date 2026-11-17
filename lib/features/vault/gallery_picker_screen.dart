import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:photo_manager/photo_manager.dart';

import '../../core/app_theme_service.dart';

/// Результат, который возвращает пикер.
class GalleryPickerResult {
  final List<AssetEntity> assets;
  final List<String> filePaths;
  final bool deleteOriginals;

  const GalleryPickerResult({
    this.assets = const [],
    this.filePaths = const [],
    this.deleteOriginals = false,
  });
}

enum _PickerFilter { all, photos, videos }

class GalleryPickerScreen extends StatefulWidget {
  const GalleryPickerScreen({super.key});

  @override
  State<GalleryPickerScreen> createState() => _GalleryPickerScreenState();
}

class _GalleryPickerScreenState extends State<GalleryPickerScreen> {
  bool _permissionDenied = false;
  bool _loading = true;
  bool _loadingMore = false;
  bool _hasMore = true;
  int _currentPage = 0;
  AssetPathEntity? _allPath;

  final List<AssetEntity> _allAssets = [];
  final Set<String> _selectedIds = {};
  _PickerFilter _filter = _PickerFilter.all;
  bool _deleteOriginals = false;

  final ScrollController _scrollCtrl = ScrollController();
  final GlobalKey _gridKey = GlobalKey();

  bool _isDragSelecting = false;
  final Set<String> _dragVisitedIds = {};

  static const int _gridCols = 4;
  static const double _gridSpacing = 2.0;

  @override
  void initState() {
    super.initState();
    _scrollCtrl.addListener(_onScroll);
    _init();
  }

  @override
  void dispose() {
    _scrollCtrl.dispose();
    super.dispose();
  }

  Future<void> _init() async {
    try {
      final ps = await PhotoManager.requestPermissionExtend();
      if (!ps.isAuth && !ps.hasAccess) {
        if (mounted) {
          setState(() {
            _permissionDenied = true;
            _loading = false;
          });
        }
        return;
      }

      final paths = await PhotoManager.getAssetPathList(
        type: RequestType.common,
        onlyAll: true,
        filterOption: FilterOptionGroup(
          orders: [
            const OrderOption(type: OrderOptionType.createDate, asc: false),
          ],
        ),
      );
      if (paths.isEmpty) {
        if (mounted) setState(() => _loading = false);
        return;
      }
      _allPath = paths.first;
      await _loadNextPage();
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _loadNextPage() async {
    if (_allPath == null || _loadingMore || !_hasMore) return;
    _loadingMore = true;
    try {
      final page = await _allPath!.getAssetListPaged(
        page: _currentPage,
        size: 100,
      );
      if (!mounted) return;
      setState(() {
        _allAssets.addAll(page);
        _currentPage++;
        _hasMore = page.length == 100;
        _loading = false;
        _loadingMore = false;
      });
    } catch (_) {
      if (mounted) {
        setState(() {
          _loading = false;
          _loadingMore = false;
          _hasMore = false;
        });
      }
    }
  }

  void _onScroll() {
    if (!_scrollCtrl.hasClients) return;
    final pos = _scrollCtrl.position;
    if (pos.pixels > pos.maxScrollExtent - 800) {
      _loadNextPage();
    }
  }

  List<AssetEntity> get _visibleAssets {
    switch (_filter) {
      case _PickerFilter.all:
        return _allAssets;
      case _PickerFilter.photos:
        return _allAssets.where((a) => a.type == AssetType.image).toList();
      case _PickerFilter.videos:
        return _allAssets.where((a) => a.type == AssetType.video).toList();
    }
  }

  bool get _allVisibleSelected {
    final v = _visibleAssets;
    if (v.isEmpty) return false;
    return v.every((a) => _selectedIds.contains(a.id));
  }

  void _toggleSelect(AssetEntity a) {
    setState(() {
      if (_selectedIds.contains(a.id)) {
        _selectedIds.remove(a.id);
      } else {
        _selectedIds.add(a.id);
      }
    });
  }

  void _selectAllVisible() {
    final v = _visibleAssets;
    setState(() {
      if (_allVisibleSelected) {
        _selectedIds.removeAll(v.map((a) => a.id));
      } else {
        _selectedIds.addAll(v.map((a) => a.id));
      }
    });
  }

  Future<void> _done() async {
    if (_selectedIds.isEmpty) return;
    final selected =
        _allAssets.where((a) => _selectedIds.contains(a.id)).toList();
    Navigator.pop(
      context,
      GalleryPickerResult(assets: selected, deleteOriginals: _deleteOriginals),
    );
  }

  Future<void> _openFileExplorer() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        allowMultiple: true,
        type: FileType.media,
      );
      if (result == null || result.paths.isEmpty) return;
      if (!mounted) return;
      final paths = result.paths.whereType<String>().toList();
      if (paths.isEmpty) return;
      Navigator.pop(
        context,
        GalleryPickerResult(filePaths: paths),
      );
    } catch (_) {}
  }

  // ─────────── Drag-select ───────────

  int? _indexAtGlobalPosition(Offset globalPosition) {
    final box = _gridKey.currentContext?.findRenderObject() as RenderBox?;
    if (box == null) return null;
    final local = box.globalToLocal(globalPosition);
    if (!box.size.contains(local)) return null;

    final scrollOffset = _scrollCtrl.hasClients ? _scrollCtrl.offset : 0.0;
    final y = local.dy + scrollOffset;

    final viewportWidth = box.size.width;
    final cellWidth =
        (viewportWidth - _gridSpacing * (_gridCols - 1)) / _gridCols;
    final cellHeight = cellWidth;

    final row = (y / (cellHeight + _gridSpacing)).floor();
    final col = (local.dx / (cellWidth + _gridSpacing)).floor();

    if (col < 0 || col >= _gridCols || row < 0) return null;
    final index = row * _gridCols + col;
    if (index < 0 || index >= _visibleAssets.length) return null;
    return index;
  }

  void _onLongPressStart(LongPressStartDetails d) {
    final idx = _indexAtGlobalPosition(d.globalPosition);
    if (idx == null) return;
    final asset = _visibleAssets[idx];
    _isDragSelecting = true;
    _dragVisitedIds
      ..clear()
      ..add(asset.id);
    setState(() {
      _selectedIds.add(asset.id);
    });
  }

  void _onLongPressMoveUpdate(LongPressMoveUpdateDetails d) {
    if (!_isDragSelecting) return;
    final idx = _indexAtGlobalPosition(d.globalPosition);
    if (idx == null) return;
    final asset = _visibleAssets[idx];
    if (_dragVisitedIds.contains(asset.id)) return;
    _dragVisitedIds.add(asset.id);
    setState(() {
      _selectedIds.add(asset.id);
    });
  }

  void _onLongPressEnd(LongPressEndDetails d) {
    _isDragSelecting = false;
    _dragVisitedIds.clear();
  }

  @override
  Widget build(BuildContext context) {
    final themeService = AppThemeService.instance;
    final brightness = Theme.of(context).brightness;
    final onSurface = Theme.of(context).colorScheme.onSurface;
    final primary = themeService.primaryColor;
    final selectedCount = _selectedIds.length;

    return Scaffold(
      backgroundColor: Colors.transparent,
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        foregroundColor: onSurface,
        leading: IconButton(
          icon: Icon(Icons.close, color: onSurface),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          'Галерея телефона',
          style: TextStyle(
            color: onSurface,
            fontSize: 18,
            fontWeight: FontWeight.w600,
          ),
        ),
        actions: [
          IconButton(
            tooltip: 'Выбрать файлы из проводника',
            icon: Icon(Icons.folder_open, color: primary),
            onPressed: _openFileExplorer,
          ),
          if (selectedCount > 0)
            Center(
              child: Padding(
                padding: const EdgeInsets.only(right: 12, left: 4),
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: primary.withValues(alpha: 0.18),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    '$selectedCount',
                    style: TextStyle(
                      color: primary,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: themeService.gradientFor(brightness),
          ),
        ),
        child: SafeArea(
          top: false,
          child: _permissionDenied
              ? _buildPermissionDenied()
              : _loading
                  ? Center(child: CircularProgressIndicator(color: primary))
                  : Column(
                      children: [
                        SizedBox(
                          height: MediaQuery.of(context).padding.top +
                              kToolbarHeight,
                        ),
                        _buildFilters(),
                        Expanded(child: _buildGrid()),
                        _buildBottomBar(),
                      ],
                    ),
        ),
      ),
    );
  }

  Widget _buildPermissionDenied() {
    final onSurface = Theme.of(context).colorScheme.onSurface;
    final primary = AppThemeService.instance.primaryColor;

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.lock_outline,
                size: 64, color: onSurface.withValues(alpha: 0.5)),
            const SizedBox(height: 16),
            Text(
              'Нет доступа к галерее',
              style: TextStyle(color: onSurface, fontSize: 18),
            ),
            const SizedBox(height: 8),
            Text(
              'Разрешите доступ к фото и видео в настройках',
              textAlign: TextAlign.center,
              style: TextStyle(color: onSurface.withValues(alpha: 0.6)),
            ),
            const SizedBox(height: 20),
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: primary,
                foregroundColor: Colors.white,
              ),
              onPressed: () async {
                await PhotoManager.openSetting();
              },
              icon: const Icon(Icons.settings),
              label: const Text('Открыть настройки'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFilters() {
    final primary = AppThemeService.instance.primaryColor;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Row(
        children: [
          _filterChip('Все', _PickerFilter.all),
          const SizedBox(width: 8),
          _filterChip('Фото', _PickerFilter.photos),
          const SizedBox(width: 8),
          _filterChip('Видео', _PickerFilter.videos),
          const Spacer(),
          TextButton(
            onPressed: _selectAllVisible,
            child: Text(
              _allVisibleSelected ? 'Снять' : 'Выбрать всё',
              style: TextStyle(color: primary),
            ),
          ),
        ],
      ),
    );
  }

  Widget _filterChip(String label, _PickerFilter filter) {
    final sel = _filter == filter;
    final primary = AppThemeService.instance.primaryColor;
    final onSurface = Theme.of(context).colorScheme.onSurface;

    return ChoiceChip(
      label: Text(label),
      selected: sel,
      onSelected: (_) => setState(() => _filter = filter),
      selectedColor: primary.withValues(alpha: 0.20),
      labelStyle: TextStyle(
        color: sel ? primary : onSurface.withValues(alpha: 0.7),
        fontWeight: sel ? FontWeight.w700 : FontWeight.normal,
      ),
      backgroundColor: onSurface.withValues(alpha: 0.08),
      side: BorderSide.none,
    );
  }

  Widget _buildGrid() {
    final visible = _visibleAssets;
    if (visible.isEmpty) {
      final onSurface = Theme.of(context).colorScheme.onSurface;
      return Center(
        child: Text(
          'Нет файлов',
          style: TextStyle(color: onSurface.withValues(alpha: 0.5)),
        ),
      );
    }
    return GestureDetector(
      key: _gridKey,
      onLongPressStart: _onLongPressStart,
      onLongPressMoveUpdate: _onLongPressMoveUpdate,
      onLongPressEnd: _onLongPressEnd,
      child: GridView.builder(
        controller: _scrollCtrl,
        padding: const EdgeInsets.all(2),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: _gridCols,
          crossAxisSpacing: _gridSpacing,
          mainAxisSpacing: _gridSpacing,
        ),
        itemCount: visible.length,
        itemBuilder: (context, i) {
          final a = visible[i];
          return _PickerTile(
            asset: a,
            selected: _selectedIds.contains(a.id),
            onTap: () => _toggleSelect(a),
          );
        },
      ),
    );
  }

  Widget _buildBottomBar() {
    final onSurface = Theme.of(context).colorScheme.onSurface;
    final primary = AppThemeService.instance.primaryColor;
    final count = _selectedIds.length;

    return SafeArea(
      top: false,
      child: Container(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
        decoration: BoxDecoration(
          border: Border(
            top: BorderSide(color: onSurface.withValues(alpha: 0.12)),
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Удалить оригиналы из галереи',
                    style: TextStyle(color: onSurface, fontSize: 14),
                  ),
                ),
                Switch.adaptive(
                  value: _deleteOriginals,
                  activeThumbColor: primary,
                  onChanged: (v) => setState(() => _deleteOriginals = v),
                ),
              ],
            ),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: count > 0 ? _done : null,
                style: ElevatedButton.styleFrom(
                  backgroundColor: primary,
                  foregroundColor: Colors.white,
                  disabledBackgroundColor: onSurface.withValues(alpha: 0.1),
                  disabledForegroundColor: onSurface.withValues(alpha: 0.4),
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
                child: Text(
                  count > 0 ? 'Импортировать $count' : 'Выберите фото и видео',
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

String _formatDuration(int seconds) {
  final m = (seconds ~/ 60).toString();
  final s = (seconds % 60).toString().padLeft(2, '0');
  return '$m:$s';
}

class _PickerTile extends StatelessWidget {
  final AssetEntity asset;
  final bool selected;
  final VoidCallback onTap;

  const _PickerTile({
    required this.asset,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final isVideo = asset.type == AssetType.video;
    final primary = AppThemeService.instance.primaryColor;

    return GestureDetector(
      onTap: onTap,
      child: Stack(
        fit: StackFit.expand,
        children: [
          _AssetThumb(asset: asset),
          if (isVideo)
            const Center(
              child: Icon(Icons.play_circle_fill,
                  color: Colors.white70, size: 28),
            ),
          if (isVideo && asset.duration > 0)
            Positioned(
              bottom: 4,
              right: 4,
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.6),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  _formatDuration(asset.duration),
                  style: const TextStyle(color: Colors.white, fontSize: 9),
                ),
              ),
            ),
          Positioned(
            top: 4,
            right: 4,
            child: Container(
              width: 22,
              height: 22,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: selected
                    ? primary
                    : Colors.black.withValues(alpha: 0.4),
                border: Border.all(color: Colors.white, width: 1.8),
              ),
              child: selected
                  ? const Icon(Icons.check, size: 14, color: Colors.white)
                  : null,
            ),
          ),
        ],
      ),
    );
  }
}

class _AssetThumb extends StatefulWidget {
  final AssetEntity asset;
  const _AssetThumb({required this.asset});

  @override
  State<_AssetThumb> createState() => _AssetThumbState();
}

class _AssetThumbState extends State<_AssetThumb> {
  Uint8List? _bytes;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant _AssetThumb oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.asset.id != widget.asset.id) {
      _bytes = null;
      _load();
    }
  }

  Future<void> _load() async {
    try {
      Uint8List? data = await widget.asset.thumbnailDataWithSize(
        const ThumbnailSize.square(200),
        quality: 80,
        format: ThumbnailFormat.jpeg,
      );
      if (data == null) {
        data = await widget.asset.thumbnailData;
      }
      if (mounted) setState(() => _bytes = data);
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    if (_bytes == null) {
      return Container(
        color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.08),
      );
    }
    return Image.memory(
      _bytes!,
      fit: BoxFit.cover,
      gaplessPlayback: true,
    );
  }
}
