import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_windowmanager_plus/flutter_windowmanager_plus.dart';

import '../../core/app_info.dart';
import '../../core/app_settings_keys.dart';
import '../../core/database_service.dart';
import '../../core/storage_stats_service.dart';
import '../../core/thumbnail_cache.dart';
import '../../core/trash_cleanup_service.dart';

class SettingsScreen extends StatefulWidget {
  final DatabaseService db;

  const SettingsScreen({super.key, required this.db});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  static const _storage = FlutterSecureStorage();

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
    String? raw;
    try {
      raw = await _storage.read(key: AppSettingsKeys.secureScreenshots);
    } catch (_) {}
    final secure = raw == 'true';

    final stats = await StorageStatsService.computeStats(widget.db);

    if (!mounted) return;
    setState(() {
      _secureOn = secure;
      _stats = stats;
      _statsLoading = false;
    });
    _applySecure(secure);
  }

  Future<void> _applySecure(bool value) async {
    try {
      await FlutterWindowManagerPlus.setSecure(value);
    } catch (_) {}
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
    try {
      await _storage.write(
        key: AppSettingsKeys.secureScreenshots,
        value: value ? 'true' : 'false',
      );
    } catch (_) {}
    await _applySecure(value);
    if (!mounted) return;
    setState(() => _secureOn = value);
  }

  Future<void> _purgeTrash() async {
    final confirm = await _showConfirm(
      'Очистить корзину?',
      'Файлы старше ${TrashCleanupService.defaultDaysOld} дней будут '
          'удалены безвозвратно.',
    );
    if (confirm != true || !mounted) return;

    setState(() => _cleaning = true);
    final result = await TrashCleanupService.purgeOldTrash(
      widget.db,
      onDeleted: ThumbnailCache.evict,
    );
    if (!mounted) return;
    setState(() => _cleaning = false);

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          result.removedCount == 0
              ? 'Нечего удалять'
              : 'Удалено: ${result.removedCount} '
                  '(${StorageStats.formatBytes(result.removedBytes)})',
        ),
      ),
    );

    await _refreshStats();
  }

  Future<bool?> _showConfirm(String title, String message) {
    return showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF15151A),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
        ),
        title: Text(title, style: const TextStyle(color: Colors.white)),
        content:
            Text(message, style: const TextStyle(color: Colors.white70)),
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
              title: 'ХРАНИЛИЩЕ',
              children: [
                if (_statsLoading)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 16),
                    child: Center(child: CircularProgressIndicator()),
                  )
                else if (_stats != null) ...[
                  _row('Занято файлами',
                      StorageStats.formatBytes(_stats!.totalBytes)),
                  _row('Всего файлов', '${_stats!.totalFiles}'),
                  _row('В хранилище', '${_stats!.activeFiles}'),
                  _row('В корзине', '${_stats!.trashedFiles}'),
                  _row(
                      'Размер БД', StorageStats.formatBytes(_stats!.dbBytes)),
                  const SizedBox(height: 6),
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
              title: 'ПРИВАТНОСТЬ',
              children: [
                SwitchListTile.adaptive(
                  contentPadding: EdgeInsets.zero,
                  title: const Text(
                    'Блокировка скриншотов',
                    style: TextStyle(color: Colors.white),
                  ),
                  subtitle: const Text(
                    'Запрет снятия экрана и записи',
                    style: TextStyle(color: Colors.white54),
                  ),
                  value: _secureOn,
                  onChanged: _toggleSecure,
                ),
              ],
            ),
            const SizedBox(height: 16),
            _GlassCard(
              title: 'КОРЗИНА',
              children: [
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text(
                    'Удалить файлы старше 30 дней',
                    style: TextStyle(color: Colors.white),
                  ),
                  subtitle: Text(
                    _cleaning
                        ? 'Удаление…'
                        : 'Также запускается автоматически при старте',
                    style: const TextStyle(color: Colors.white54),
                  ),
                  trailing: _cleaning
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(
                          Icons.delete_sweep_outlined,
                          color: Colors.white70,
                        ),
                  onTap: _cleaning ? null : _purgeTrash,
                ),
              ],
            ),
            const SizedBox(height: 16),
            _GlassCard(
              title: 'О ПРИЛОЖЕНИИ',
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
          Flexible(
            child: Text(
              value,
              textAlign: TextAlign.right,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
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
                Colors.white.withValues(alpha: 0.10),
                Colors.white.withValues(alpha: 0.03),
              ],
            ),
            border: Border.all(color: Colors.white.withValues(alpha: 0.10)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                title,
                style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.8,
                  color: Colors.white70,
                ),
              ),
              const SizedBox(height: 10),
              ...children,
            ],
          ),
        ),
      ),
    );
  }
}
