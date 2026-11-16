import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_windowmanager_plus/flutter_windowmanager_plus.dart';
import 'package:sqflite_sqlcipher/sqflite.dart';

import '../../core/app_info.dart';
import '../../core/storage_stats_service.dart';
import '../../core/trash_cleanup_service.dart';
import '../../core/thumbnail_cache.dart';

class SettingsScreen extends StatefulWidget {
  final Database db;
  const SettingsScreen({super.key, required this.db});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  static const _storage = FlutterSecureStorage();
  static const _kSecureKey = 'secure_screenshots';

  StorageStats? _stats;
  bool _statsLoading = true;
  bool _secureOn = false;
  bool _cleaning = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final secure = await _storage.read(key: _kSecureKey);
    final stats = await StorageStatsService.computeStats(widget.db);
    if (!mounted) return;
    setState(() {
      _secureOn = secure == 'true';
      _stats = stats;
      _statsLoading = false;
    });
  }

  Future<void> _refreshStats() async {
    setState(() => _statsLoading = true);
    final stats = await StorageStatsService.computeStats(widget.db);
    if (!mounted) return;
    setState(() {
      _stats = stats;
      _statsLoading = false;
    });
  }

  Future<void> _toggleSecure(bool value) async {
    await _storage.write(key: _kSecureKey, value: value ? 'true' : 'false');
    try {
      if (value) {
        await FlutterWindowManagerPlus.addFlags(
          FlutterWindowManagerPlus.FLAG_SECURE,
        );
      } else {
        await FlutterWindowManagerPlus.clearFlags(
          FlutterWindowManagerPlus.FLAG_SECURE,
        );
      }
    } catch (_) {}
    if (!mounted) return;
    setState(() => _secureOn = value);
  }

  Future<void> _purgeTrash() async {
    final confirm = await _showConfirm(
      'Очистить корзину?',
      'Файлы старше 30 дней будут удалены безвозвратно.',
    );
    if (confirm != true || !mounted) return;
    setState(() => _cleaning = true);
    final removed = await TrashCleanupService.purgeOldTrash(
      widget.db,
      cache: ThumbnailCache.instance,
    );
    if (!mounted) return;
    setState(() => _cleaning = false);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Удалено из корзины: $removed')),
    );
    await _refreshStats();
  }

  Future<bool?> _showConfirm(String title, String message) {
    return showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF15151A),
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Отмена'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Удалить',
                style: TextStyle(color: Colors.redAccent)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: const Text('Настройки'),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 80, 16, 32),
          children: [
            _GlassCard(
              title: 'Хранилище',
              children: [
                if (_statsLoading)
                  const Padding(
                    padding: EdgeInsets.all(16),
                    child: Center(child: CircularProgressIndicator()),
                  )
                else if (_stats != null) ...[
                  _row('Занято', StorageStats.formatBytes(_stats!.totalBytes)),
                  _row('Всего файлов', '${_stats!.totalFiles}'),
                  _row('В хранилище', '${_stats!.activeFiles}'),
                  _row('В корзине', '${_stats!.trashedFiles}'),
                  _row('Размер БД', StorageStats.formatBytes(_stats!.dbBytes)),
                  const SizedBox(height: 8),
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton.icon(
                      onPressed: _refreshStats,
                      icon: const Icon(Icons.refresh, size: 18),
                      label: const Text('Обновить'),
                    ),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 16),
            _GlassCard(
              title: 'Приватность',
              children: [
                SwitchListTile.adaptive(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Блокировка скриншотов'),
                  subtitle: const Text('Запрет снятия экрана и записи'),
                  value: _secureOn,
                  onChanged: _toggleSecure,
                ),
              ],
            ),
            const SizedBox(height: 16),
            _GlassCard(
              title: 'Корзина',
              children: [
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Удалить файлы старше 30 дней'),
                  subtitle: Text(
                    _cleaning ? 'Удаление…' : 'Автоочистка при запуске + вручную',
                  ),
                  trailing: _cleaning
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.delete_sweep_outlined),
                  onTap: _cleaning ? null : _purgeTrash,
                ),
              ],
            ),
            const SizedBox(height: 16),
            _GlassCard(
              title: 'О приложении',
              children: [
                _row('Название', AppInfo.appName),
                _row('Версия', AppInfo.versionLabel),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _row(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(color: Colors.white70)),
          Text(value,
              style: const TextStyle(
                  color: Colors.white, fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}

class _GlassCard extends StatelessWidget {
  final String title;
  final List<Widget> children;
  const _GlassCard({required this.title, required this.children});

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(22),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
        child: Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(22),
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                Colors.white.withOpacity(0.10),
                Colors.white.withOpacity(0.03),
              ],
            ),
            border: Border.all(color: Colors.white.withOpacity(0.10)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(title,
                  style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.6,
                      color: Colors.white70)),
              const SizedBox(height: 10),
              ...children,
            ],
          ),
        ),
      ),
    );
  }
}
