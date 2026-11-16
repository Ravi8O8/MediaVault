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
  static const _storage = FlutterSecureStorage();

  StorageStats? _stats;
  bool _statsLoading = true;
  bool _secureOn = false;
  bool _cleaning = false;
  int _trashDays = TrashCleanupService.defaultDaysOld;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    String? rawSecure;
    String? rawDays;
    try {
      rawSecure = await _storage.read(key: AppSettingsKeys.secureScreenshots);
      rawDays = await _storage.read(key: AppSettingsKeys.trashAutoCleanupDays);
    } catch (_) {}

    final secure = rawSecure == 'true';
    final days = int.tryParse(rawDays ?? '') ?? TrashCleanupService.defaultDaysOld;

    final stats = await StorageStatsService.computeStats(widget.db);

    if (!mounted) return;
    setState(() {
      _secureOn = secure;
      _trashDays = days;
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

  Future<void> _setTrashDays(int days) async {
    setState(() => _trashDays = days);
    try {
      await _storage.write(
        key: AppSettingsKeys.trashAutoCleanupDays,
        value: days.toString(),
      );
    } catch (_) {}
  }

  Future<void> _purgeTrashNow() async {
    final confirm = await _showConfirm(
      'Очистить корзину сейчас?',
      'Все файлы в корзине будут удалены безвозвратно.',
    );
    if (confirm != true || !mounted) return;

    setState(() => _cleaning = true);
    final result = await TrashCleanupService.purgeAll(
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
              ? 'Корзина уже пуста'
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
          fontSize: 22,
          fontWeight: FontWeight.w700,
        ),
      ),
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: theme.gradientFor(Theme.of(context).brightness),
          ),
        ),
        child: SafeArea(
          child: AnimatedBuilder(
            animation: theme,
            builder: (context, _) {
              return ListView(
                padding: const EdgeInsets.fromLTRB(16, 80, 16, 32),
                children: [
                  // ─── ХРАНИЛИЩЕ ───
                  _GlassCard(
                    title: 'ХРАНИЛИЩЕ',
                    icon: Icons.folder_outlined,
                    children: [
                      if (_statsLoading)
                        const Padding(
                          padding: EdgeInsets.symmetric(vertical: 24),
                          child: Center(child: CircularProgressIndicator()),
                        )
                      else if (_stats != null) ...[
                        _buildStatRow('Занято файлами', StorageStats.formatBytes(_stats!.totalBytes), Icons.sd_storage),
                        _buildStatRow('Всего файлов', '${_stats!.totalFiles}', Icons.insert_drive_file_outlined),
                        _buildStatRow('В корзине', '${_stats!.trashedFiles}', Icons.delete_outline),
                        _buildStatRow('Размер БД', StorageStats.formatBytes(_stats!.dbBytes), Icons.storage),
                        const SizedBox(height: 8),
                        Align(
                          alignment: Alignment.centerRight,
                          child: TextButton.icon(
                            onPressed: _refreshStats,
                            icon: const Icon(Icons.refresh, size: 18),
                            label: const Text('Обновить данные'),
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 20),

                  // ─── ПРИВАТНОСТЬ ───
                  _GlassCard(
                    title: 'БЕЗОПАСНОСТЬ',
                    icon: Icons.security,
                    children: [
                      SwitchListTile.adaptive(
                        contentPadding: EdgeInsets.zero,
                        title: const Text('Блокировка скриншотов'),
                        subtitle: const Text('Запрет снятия экрана и записи в приложении'),
                        value: _secureOn,
                        onChanged: _toggleSecure,
                        activeColor: theme.primaryColor,
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),

                  // ─── ТЕМА ───
                  _GlassCard(
                    title: 'ТЕМА ОФОРМЛЕНИЯ',
                    icon: Icons.palette_outlined,
                    children: [
                      const Text('Режим', style: TextStyle(fontWeight: FontWeight.w600)),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 10,
                        runSpacing: 10,
                        children: AppThemeService.modeOptions.entries.map((e) {
                          final sel = theme.mode == e.key;
                          return ChoiceChip(
                            label: Text(e.value),
                            selected: sel,
                            onSelected: (_) => theme.setMode(e.key),
                            selectedColor: theme.primaryColor.withValues(alpha: 0.2),
                            checkmarkColor: theme.primaryColor,
                            labelStyle: TextStyle(
                              color: sel ? theme.primaryColor : colorScheme.onSurface,
                              fontWeight: sel ? FontWeight.bold : FontWeight.normal,
                            ),
                          );
                        }).toList(),
                      ),
                      const SizedBox(height: 20),
                      const Text('Цветовая схема', style: TextStyle(fontWeight: FontWeight.w600)),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 12,
                        runSpacing: 12,
                        children: AppThemeService.presetNames.entries.map((e) {
                          final sel = theme.presetKey == e.key;
                          final color = AppThemeService.presetNames.containsKey(e.key) 
                              ? (AppThemeService.instance.primaryColor) // fallback
                              : theme.primaryColor;
                          // Получаем цвет напрямую из карты через рефлексию или хардкод для UI
                          final previewColor = {
                            'midnight': const Color(0xFF00E5FF),
                            'purple': const Color(0xFFD500F9),
                            'ocean': const Color(0xFF2979FF),
                            'sunset': const Color(0xFFFF6D00),
                          }[e.key]!;

                          return GestureDetector(
                            onTap: () => theme.setPreset(e.key),
                            child: Container(
                              width: 60,
                              height: 60,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: previewColor,
                                border: Border.all(
                                  color: sel ? Colors.white : Colors.transparent,
                                  width: 3,
                                ),
                                boxShadow: sel ? [
                                  BoxShadow(
                                    color: previewColor.withValues(alpha: 0.5),
                                    blurRadius: 12,
                                    spreadRadius: 2,
                                  )
                                ] : [],
                              ),
                              child: sel
                                  ? const Icon(Icons.check, color: Colors.white)
                                  : null,
                            ),
                          );
                        }).toList(),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        AppThemeService.presetNames[theme.presetKey] ?? '',
                        style: TextStyle(
                          color: colorScheme.onSurface.withValues(alpha: 0.6),
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),

                  // ─── КОРЗИНА И ОПТИМИЗАЦИЯ ───
                  _GlassCard(
                    title: 'КОРЗИНА И ОПТИМИЗАЦИЯ',
                    icon: Icons.auto_delete_outlined,
                    children: [
                      const Text('Автоочистка корзины', style: TextStyle(fontWeight: FontWeight.w600)),
                      const SizedBox(height: 4),
                      Text(
                        'Файлы старше указанного срока будут удаляться при запуске.',
                        style: TextStyle(fontSize: 12, color: colorScheme.onSurface.withValues(alpha: 0.6)),
                      ),
                      const SizedBox(height: 12),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [7, 14, 30, 0].map((days) {
                          final sel = _trashDays == days;
                          final label = days == 0 ? 'Выкл' : '$days дней';
                          return ChoiceChip(
                            label: Text(label),
                            selected: sel,
                            onSelected: (_) => _setTrashDays(days),
                            selectedColor: theme.primaryColor.withValues(alpha: 0.2),
                            checkmarkColor: theme.primaryColor,
                            labelStyle: TextStyle(
                              color: sel ? theme.primaryColor : colorScheme.onSurface,
                              fontWeight: sel ? FontWeight.bold : FontWeight.normal,
                            ),
                          );
                        }).toList(),
                      ),
                      const Divider(height: 32),
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        title: const Text('Очистить корзину сейчас'),
                        subtitle: const Text('Удалить все файлы из корзины безвозвратно'),
                        trailing: _cleaning
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              )
                            : const Icon(Icons.delete_forever, color: Colors.redAccent),
                        onTap: _cleaning ? null : _purgeTrashNow,
                      ),
                      const Divider(height: 1),
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        title: const Text('Поиск дубликатов'),
                        subtitle: const Text('Найти и удалить одинаковые файлы'),
                        trailing: const Icon(Icons.content_copy),
                        onTap: _openDuplicates,
                      ),
                      const Divider(height: 1),
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        title: const Text('Сбросить кэш миниатюр'),
                        subtitle: Text('Сейчас в кэше: ${ThumbnailCache.debugCount()}'),
                        trailing: const Icon(Icons.cleaning_services_outlined),
                        onTap: () {
                          ThumbnailCache.clear();
                          setState(() {});
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('Кэш миниатюр очищен')),
                          );
                        },
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),

                  // ─── ДИАГНОСТИКА ───
                  _GlassCard(
                    title: 'ДИАГНОСТИКА',
                    icon: Icons.bug_report_outlined,
                    children: [
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        title: const Text('Поделиться логом'),
                        subtitle: const Text('Отправить файл разработчику'),
                        trailing: const Icon(Icons.ios_share),
                        onTap: _shareLogs,
                      ),
                      const Divider(height: 1),
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        title: const Text('Скопировать лог'),
                        subtitle: const Text('Скопировать текст в буфер обмена'),
                        trailing: const Icon(Icons.copy),
                        onTap: _copyLogs,
                      ),
                      const Divider(height: 1),
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        title: const Text('Очистить логи'),
                        trailing: const Icon(Icons.delete_outline, color: Colors.redAccent),
                        onTap: _clearLogs,
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),

                  // ─── О ПРИЛОЖЕНИИ ───
                  _GlassCard(
                    title: 'О ПРИЛОЖЕНИИ',
                    icon: Icons.info_outline,
                    children: [
                      _buildStatRow('Название', AppInfo.appName, null),
                      _buildStatRow('Версия', AppInfo.versionLabel, null),
                    ],
                  ),
                  const SizedBox(height: 40),
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _buildStatRow(String label, String value, IconData? icon) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          if (icon != null) ...[
            Icon(icon, size: 18, color: Theme.of(context).colorScheme.onSurfaceVariant),
            const SizedBox(width: 12),
          ],
          Text(label, style: TextStyle(color: Theme.of(context).colorScheme.onSurface)),
          const Spacer(),
          Text(
            value,
            style: TextStyle(
              fontWeight: FontWeight.w700,
              color: Theme.of(context).colorScheme.onSurface,
            ),
          ),
        ],
      ),
    );
  }
}

class _GlassCard extends StatelessWidget {
  final String title;
  final IconData icon;
  final List<Widget> children;

  const _GlassCard({
    required this.title,
    required this.icon,
    required this.children,
  });

  @override
  Widget build(BuildContext context) {
    final brightness = Theme.of(context).brightness;
    final isDark = brightness == Brightness.dark;
    final theme = AppThemeService.instance;
    final onSurface = Theme.of(context).colorScheme.onSurface;
    final primary = theme.primaryColor;

    return ClipRRect(
      borderRadius: BorderRadius.circular(24),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
        child: Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(24),
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                theme.glassCardTop(brightness),
                theme.glassCardBottom(brightness),
              ],
            ),
            border: Border.all(color: theme.glassBorderColor(brightness), width: 1.5),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Icon(icon, size: 20, color: primary),
                  const SizedBox(width: 10),
                  Text(
                    title,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 1.2,
                      color: onSurface.withValues(alpha: isDark ? 0.8 : 0.6),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              ...children,
            ],
          ),
        ),
      ),
    );
  }
}
