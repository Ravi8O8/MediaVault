import 'dart:async';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_windowmanager_plus/flutter_windowmanager_plus.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';

import '../../core/app_settings_keys.dart';
import '../../core/app_theme_service.dart';
import '../../core/database_service.dart';
import '../../core/export_service.dart';
import '../../core/ui_helpers.dart'; // Подключаем
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
    } catch (_) {}
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
    if (dataChanged) setState(() => _tabReloadKey++);
  }

  String get _title {
    switch (_currentTab) {
      case 0: return 'Хранилище';
      case 1: return 'Альбомы';
      case 2: return 'Избранное';
      case 3: return 'Корзина';
      default: return 'MediaVault';
    }
  }

  @override
  Widget build(BuildContext context) {
    final themeService = AppThemeService.instance;
    final brightness = Theme.of(context).brightness;
    final onSurface = Theme.of(context).colorScheme.onSurface;
    final isDark = brightness == Brightness.dark;

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
                    _AllMediaTab(key: ValueKey('all_$_tabReloadKey'), db: widget.db),
                    AlbumsTab(key: ValueKey('albums_$_tabReloadKey'), db: widget.db),
                    _FavoritesTab(key: ValueKey('fav_$_tabReloadKey'), db: widget.db),
                    TrashScreen(key: ValueKey('trash_$_tabReloadKey'), db: widget.db),
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
                      backgroundColor: isDark ? Colors.white.withValues(alpha: 0.03) : Colors.white.withValues(alpha: 0.55),
                      elevation: 0,
                      title: Text(
                        _title,
                        style: TextStyle(color: onSurface, fontSize: 20, fontWeight: FontWeight.w600),
                      ),
                      actions: [
                        Tooltip(
                          message: _secure ? 'Разрешить скриншоты' : 'Запретить скриншоты',
                          child: IconButton(
                            icon: Icon(_secure ? Icons.visibility_off : Icons.visibility, color: onSurface),
                            onPressed: _toggleSecure,
                          ),
                        ),
                        Tooltip(
                          message: 'Настройки',
                          child: IconButton(
                            icon: Icon(Icons.settings_outlined, color: onSurface),
                            onPressed: _openSettings,
                          ),
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
    (Icons.folder_outlined, Icons.folder, 'Альбомы'),
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

    return ClipRRect(
      borderRadius: BorderRadius.circular(24),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
        child: Container(
          decoration: BoxDecoration(
            color: isDark ? Colors.white.withValues(alpha: 0.08) : Colors.white.withValues(alpha: 0.75),
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
                  message: item.$3, // Подсказка при долгом нажатии
                  child: InkWell(
                    onTap: () => onChanged(i),
                    borderRadius: BorderRadius.circular(16),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(sel ? item.$2 : item.$1, color: sel ? selected : unselected, size: 22),
                          const SizedBox(height: 3),
                          Text(
                            item.$3,
                            style: TextStyle(fontSize: 10, color: sel ? selected : unselected),
                          ),
                        ],
                      ),
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
// ... Остальные классы (_AllMediaTab, _FavoritesTab, _SelectionActionBar) оставляем без изменений, 
// только в _AllMediaTab заменяем ScaffoldMessenger на showAppSnackBar, если они там есть.
// (В _AllMediaTab их нет, там только вызовы confirmDelete и т.д.)
