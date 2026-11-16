import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_windowmanager_plus/flutter_windowmanager_plus.dart';

import '../../core/app_info.dart';
import '../../core/app_settings_keys.dart';
import '../../core/app_theme_service.dart';
import '../../core/database_service.dart';
import '../../core/log_service.dart';
import '../../core/storage_stats_service.dart';
import '../../core/thumbnail_cache.dart';
import '../../core/trash_cleanup_service.dart';
import 'duplicates_screen.dart';

class SettingsScreen extends StatefulWidget {
  final DatabaseService db;
  final VoidCallback? onDataChanged;

  const SettingsScreen({
    super.key,
    required this.db,
    this.onDataChanged,
  });

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  // ИСПРАВЛЕНО: убран устаревший aOptions
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

    if (result.removedCount > 0) widget.onDataChanged?.call();

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

  void _openDuplicates() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => DuplicatesScreen(db: widget.db),
      ),
    ).then((_) {
      if (mounted) {
        widget.onDataChanged?.call();
        _refreshStats();
      }
    });
  }

  Future<void> _shareLogs() async {
    try {
      await LogService.instance.shareLogs();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Ошибка: $e')));
    }
  }

  Future<void> _copyLogs() async {
    await LogService.instance.copyLogsToClipboard();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Лог скопирован в буфер')),
    );
  }

  Future<void> _clearLogs() async {
    await LogService.instance.clearLogs();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Логи очищены')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = AppThemeService.instance;
    final colorScheme = Theme.of(context).colorScheme;
    // ИСПРАВЛЕНО: удалена неиспользуемая переменная isDark

    return Scaffold(
      extendBodyBehindAppBar: true,
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: const Text('Настройки'),
        iconTheme: IconThemeData(color: colorScheme.onSurface),
        titleTextStyle: TextStyle(
          color: colorScheme.onSurface,
          fontSize: 20,
          fontWeight: FontWeight.w600,
        ),
      ),
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: theme.gradientFor(
              Theme.of(context).brightness,
            ),
          ),
        ),
        child: SafeArea(
          child: AnimatedBuilder(
            animation: theme,
            builder: (context, _) {
              return ListView(
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
                        _row(context, 'Занято файлами',
                            StorageStats.formatBytes(_stats!.totalBytes)),
                        _row(context, 'Всего файлов', '${_stats!.totalFiles}'),
                        _row(context, 'В хранилище', '${_stats!.activeFiles}'),
                        _row(context, 'В корзине', '${_stats!.trashedFiles}'),
                        _row(context, 'Размер БД',
                            StorageStats.formatBytes(_stats!.dbBytes)),
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
                        title: const Text('Блокировка скриншотов'),
                        subtitle: const Text('Запрет снятия экрана и записи'),
                        value: _secureOn,
                        onChanged: _toggleSecure,
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  _GlassCard(
                    title: 'ТЕМА ОФОРМЛЕНИЯ',
                    children: [
                      const Text('Режим'),
                      const SizedBox(height: 6),
                      Wrap(
                        spacing: 8,
                        children:
                            AppThemeService.modeOptions.entries.map((e) {
                          final sel = theme.mode == e.key;
                          return ChoiceChip(
                            label: Text(e.value),
                            selected: sel,
                            onSelected: (_) => theme.setMode(e.key),
                          );
                        }).toList(),
                      ),
                      const SizedBox(height: 14),
                      const Text('Цветовая схема'),
                      const SizedBox(height: 6),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children:
                            AppThemeService.presetNames.entries.map((e) {
                          final sel = theme.presetKey == e.key;
                          return ChoiceChip(
                            label: Text(e.value),
                            selected: sel,
                            onSelected: (_) => theme.setPreset(e.key),
                          );
                        }).toList(),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  _GlassCard(
                    title: 'КОРЗИНА И ОПТИМИЗАЦИЯ',
                    children: [
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        title: const Text('Удалить файлы старше 30 дней'),
                        subtitle: Text(
                          _cleaning
                              ? 'Удаление…'
                              : 'Также запускается автоматически при старте',
                        ),
                        trailing: _cleaning
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                    strokeWidth: 2),
                              )
                            : const Icon(Icons.delete_sweep_outlined),
                        onTap: _cleaning ? null : _purgeTrash,
                      ),
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        title: const Text('Дубликаты'),
                        subtitle:
                            const Text('Найти и удалить лишние копии'),
                        trailing: const Icon(Icons.content_copy),
                        onTap: _openDuplicates,
                      ),
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        title: const Text('Сбросить кэш миниатюр'),
                        subtitle: Text(
                          'Сейчас в кэше: ${ThumbnailCache.debugCount()}',
                        ),
                        trailing:
                            const Icon(Icons.cleaning_services_outlined),
                        onTap: () {
                          ThumbnailCache.clear();
                          setState(() {});
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                                content: Text('Кэш миниатюр очищен')),
                          );
                        },
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  _GlassCard(
                    title: 'ДИАГНОСТИКА',
                    children: [
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        title: const Text('Поделиться логом'),
                        subtitle: const Text('Отправить файл разработчику'),
                        trailing: const Icon(Icons.ios_share),
                        onTap: _shareLogs,
                      ),
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        title: const Text('Скопировать лог в буфер'),
                        subtitle: const Text('Удобно вставить в чат'),
                        trailing: const Icon(Icons.copy),
                        onTap: _copyLogs,
                      ),
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        title: const Text('Очистить логи'),
                        trailing: const Icon(Icons.delete_outline,
                            color: Colors.redAccent),
                        onTap: _clearLogs,
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  _GlassCard(
                    title: 'О ПРИЛОЖЕНИИ',
                    children: [
                      _row(context, 'Название', AppInfo.appName),
                      _row(context, 'Версия', AppInfo.versionLabel),
                    ],
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _row(BuildContext context, String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label),
          Flexible(
            child: Text(
              value,
              textAlign: TextAlign.right,
              style: const TextStyle(fontWeight: FontWeight.w600),
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
    final brightness = Theme.of(context).brightness;
    final isDark = brightness == Brightness.dark;
    final theme = AppThemeService.instance;
    final onSurface = Theme.of(context).colorScheme.onSurface;

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
                theme.glassCardTop(brightness),
                theme.glassCardBottom(brightness),
              ],
            ),
            border: Border.all(color: theme.glassBorderColor(brightness)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                title,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.8,
                  color: onSurface.withValues(alpha: isDark ? 0.7 : 0.6),
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
