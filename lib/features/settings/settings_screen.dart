import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_windowmanager_plus/flutter_windowmanager_plus.dart';

import '../../core/app_info.dart';
import '../../core/app_settings_keys.dart';
import '../../core/app_theme_service.dart';
import '../../core/crypto_service.dart';
import '../../core/database_service.dart';
import '../../core/glass_service.dart';
import '../../core/log_service.dart';
import '../../core/storage_stats_service.dart';
import '../../core/thumbnail_cache.dart';
import '../../core/trash_cleanup_service.dart';
import '../../core/ui_helpers.dart';
import 'diagnostics_screen.dart';
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
  VaultEncryptionType _encType = VaultEncryptionType.aesCbc;

  static const List<int> _trashDaysOptions = [0, 7, 14, 30];

  String _trashLabel(int d) {
    if (d == 0) return 'Выкл';
    return '$d дней';
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    String? rawSecure;
    String? rawDays;
    String? rawEnc;
    try {
      rawSecure = await _storage.read(key: AppSettingsKeys.secureScreenshots);
      rawDays = await _storage.read(key: AppSettingsKeys.trashAutoCleanupDays);
      rawEnc = await _storage.read(key: AppSettingsKeys.encryptionType);
    } catch (e) {
      LogService.instance.log('Settings storage read error: $e', tag: 'SETTINGS');
    }

    final secure = rawSecure == 'true';
    final parsed = int.tryParse(rawDays ?? '');
    final days = parsed ?? TrashCleanupService.defaultDaysOld;
    final enc = encryptionTypeFromKey(rawEnc);

    final stats = await StorageStatsService.computeStats(widget.db);

    if (!mounted) return;
    setState(() {
      _secureOn = secure;
      _trashDays = days;
      _stats = stats;
      _statsLoading = false;
      _encType = enc;
    });
    await _applySecure(secure);
  }

  Future<void> _applySecure(bool value) async {
    try {
      await FlutterWindowManagerPlus.setSecure(value);
    } catch (e) {
      LogService.instance.log('setSecure($value) failed: $e', tag: 'SETTINGS');
    }
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
      await _applySecure(value);
      if (!mounted) return;
      setState(() => _secureOn = value);
    } catch (e) {
      if (!mounted) return;
      showAppSnackBar(context, 'Не удалось сохранить: $e', isError: true);
    }
  }

  Future<void> _toggleGlass(bool value) async {
    await GlassService.instance.setEnabled(value);
    if (!mounted) return;
    showAppSnackBar(context, value ? 'Стекло включено' : 'Стекло выключено');
  }

  Future<void> _setEncryption(VaultEncryptionType t) async {
    if (_encType == t) return;
    if (t == VaultEncryptionType.none) {
      final confirm = await _showConfirm(
        'Отключить шифрование?',
        'Новые файлы будут храниться в открытом виде. Старые файлы останутся зашифрованными.',
      );
      if (confirm != true) return;
    }
    setState(() => _encType = t);
    try {
      await _storage.write(key: AppSettingsKeys.encryptionType, value: t.key);
      if (mounted) showAppSnackBar(context, 'Применено к новым файлам');
    } catch (_) {}
  }

  Future<void> _setTrashDays(int days) async {
    setState(() => _trashDays = days);
    try {
      await _storage.write(key: AppSettingsKeys.trashAutoCleanupDays, value: days.toString());
    } catch (e) {
      if (mounted) showAppSnackBar(context, 'Ошибка сохранения: $e', isError: true);
      return;
    }

    if (days > 0) {
      try {
        final result = await TrashCleanupService.purgeOldTrash(
          widget.db,
          daysOld: days,
          onDeleted: ThumbnailCache.evict,
        );
        if (result.removedCount > 0) {
          widget.onDataChanged?.call();
          if (!mounted) return;
          showAppSnackBar(context, 'Автоочистка: удалено ${result.removedCount}');
          await _refreshStats();
        }
      } catch (_) {}
    }
  }

  Future<void> _purgeTrashNow() async {
    final confirm = await _showConfirm(
      'Очистить корзину сейчас?',
      'Все файлы в корзине будут удалены безвозвратно.',
    );
    if (confirm != true || !mounted) return;

    setState(() => _cleaning = true);
    final result = await TrashCleanupService.purgeAll(widget.db, onDeleted: (p){});
    if (!mounted) return;
    setState(() => _cleaning = false);

    if (result.removedCount > 0) widget.onDataChanged?.call();
    showAppSnackBar(context, result.removedCount == 0 ? 'Корзина пуста' : 'Удалено: ${result.removedCount}');
    await _refreshStats();
  }

  Future<bool?> _showConfirm(String title, String message) {
    return showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Отмена')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Да', style: TextStyle(color: Colors.redAccent))),
        ],
      ),
    );
  }

  void _openDuplicates() {
    Navigator.push(context, MaterialPageRoute(builder: (_) => DuplicatesScreen(db: widget.db))).then((_) {
      if (mounted) {
        widget.onDataChanged?.call();
        _refreshStats();
      }
    });
  }

  void _openDiagnostics() {
    Navigator.push(context, MaterialPageRoute(builder: (_) => const DiagnosticsScreen()));
  }

  Future<void> _shareLogs() async {
    try {
      await LogService.instance.shareLogs();
    } catch (e) {
      if (!mounted) return;
      showAppSnackBar(context, 'Ошибка: $e', isError: true);
    }
  }

  Future<void> _clearLogs() async {
    try {
      await LogService.instance.clearLogs();
      if (!mounted) return;
      showAppSnackBar(context, 'Логи очищены');
    } catch (e) {
      if (!mounted) return;
      showAppSnackBar(context, 'Ошибка: $e', isError: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = AppThemeService.instance;
    final colorScheme = Theme.of(context).colorScheme;

    return AnimatedBuilder(
      animation: Listenable.merge([theme, GlassService.instance]),
      builder: (context, _) {
        return Scaffold(
          extendBodyBehindAppBar: true,
          backgroundColor: Colors.transparent,
          appBar: AppBar(
            backgroundColor: Colors.transparent,
            elevation: 0,
            title: const Text('Настройки'),
            iconTheme: IconThemeData(color: colorScheme.onSurface),
            titleTextStyle: TextStyle(color: colorScheme.onSurface, fontSize: 22, fontWeight: FontWeight.w700),
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
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 80, 16, 32),
                children: [
                  _SettingsCard(
                    icon: Icons.folder_outlined,
                    title: 'ХРАНИЛИЩЕ',
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

                  _SettingsCard(
                    icon: Icons.palette_outlined,
                    title: 'ОТОБРАЖЕНИЕ',
                    children: [
                      const _SubLabel('Цветовая схема'),
                      const SizedBox(height: 12),
                      _buildColorGrid(theme, colorScheme),
                      const SizedBox(height: 24),
                      const _SubLabel('Размер сетки'),
                      const SizedBox(height: 12),
                      Wrap(
                        spacing: 8,
                        children: [2, 3, 4, 5].map((cols) {
                          final sel = theme.gridColumns == cols;
                          return ChoiceChip(
                            label: Text('$cols'),
                            selected: sel,
                            onSelected: (_) => theme.setGridColumns(cols),
                            selectedColor: theme.primaryColor.withValues(alpha: 0.2),
                            checkmarkColor: theme.primaryColor,
                            labelStyle: TextStyle(color: sel ? theme.primaryColor : colorScheme.onSurface, fontWeight: sel ? FontWeight.bold : FontWeight.normal),
                          );
                        }).toList(),
                      ),
                      const SizedBox(height: 16),
                      SwitchListTile.adaptive(
                        contentPadding: EdgeInsets.zero,
                        title: const Text('Стеклянные эффекты'),
                        subtitle: const Text('Красиво, но может тормозить'),
                        value: GlassService.instance.enabled,
                        onChanged: _toggleGlass,
                        activeThumbColor: theme.primaryColor,
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),

                  _SettingsCard(
                    icon: Icons.security,
                    title: 'БЕЗОПАСНОСТЬ',
                    children: [
                      SwitchListTile.adaptive(
                        contentPadding: EdgeInsets.zero,
                        title: const Text('Блокировка скриншотов'),
                        subtitle: const Text('Запрет снятия экрана'),
                        value: _secureOn,
                        onChanged: _toggleSecure,
                        activeThumbColor: theme.primaryColor,
                      ),
                      const Divider(),
                      const SizedBox(height: 8),
                      const _SubLabel('Шифрование новых файлов'),
                      const SizedBox(height: 8),
                      ...VaultEncryptionType.values.map((t) {
                        return RadioListTile<VaultEncryptionType>(
                          contentPadding: EdgeInsets.zero,
                          dense: true,
                          title: Text(t.label),
                          subtitle: Text(t.description, style: const TextStyle(fontSize: 11)),
                          value: t,
                          groupValue: _encType,
                          activeColor: theme.primaryColor,
                          onChanged: (v) {
                            if (v != null) _setEncryption(v);
                          },
                        );
                      }),
                    ],
                  ),
                  const SizedBox(height: 20),

                  _SettingsCard(
                    icon: Icons.auto_delete_outlined,
                    title: 'КОРЗИНА',
                    children: [
                      const _SubLabel('Автоочистка'),
                      const SizedBox(height: 12),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: _trashDaysOptions.map((days) {
                          final sel = _trashDays == days;
                          return ChoiceChip(
                            label: Text(_trashLabel(days)),
                            selected: sel,
                            onSelected: (_) => _setTrashDays(days),
                            selectedColor: theme.primaryColor.withValues(alpha: 0.2),
                            checkmarkColor: theme.primaryColor,
                            labelStyle: TextStyle(color: sel ? theme.primaryColor : colorScheme.onSurface, fontWeight: sel ? FontWeight.bold : FontWeight.normal),
                          );
                        }).toList(),
                      ),
                      const SizedBox(height: 16),
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        title: const Text('Очистить корзину сейчас'),
                        trailing: _cleaning
                            ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                            : const Icon(Icons.delete_forever, color: Colors.redAccent),
                        onTap: _cleaning ? null : _purgeTrashNow,
                      ),
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        title: const Text('Поиск дубликатов'),
                        trailing: const Icon(Icons.content_copy),
                        onTap: _openDuplicates,
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),

                  _SettingsCard(
                    icon: Icons.bug_report_outlined,
                    title: 'ДИАГНОСТИКА',
                    children: [
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: const Icon(Icons.article_outlined, color: Colors.tealAccent),
                        title: const Text('Открыть диагностику'),
                        subtitle: const Text('Логи, фризы, копирование'),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: _openDiagnostics,
                      ),
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        title: const Text('Поделиться логом'),
                        trailing: const Icon(Icons.ios_share),
                        onTap: _shareLogs,
                      ),
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        title: const Text('Очистить логи'),
                        trailing: const Icon(Icons.delete_outline, color: Colors.redAccent),
                        onTap: _clearLogs,
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),

                  _SettingsCard(
                    icon: Icons.info_outline,
                    title: 'О ПРИЛОЖЕНИИ',
                    children: [
                      _buildStatRow('Версия', AppInfo.versionLabel, null),
                    ],
                  ),
                  const SizedBox(height: 40),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildColorGrid(AppThemeService theme, ColorScheme colorScheme) {
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 5,
        crossAxisSpacing: 10,
        mainAxisSpacing: 10,
        childAspectRatio: 0.75,
      ),
      itemCount: AppThemeService.presetNames.length,
      itemBuilder: (context, i) {
        final entry = AppThemeService.presetNames.entries.elementAt(i);
        final sel = theme.presetKey == entry.key;
        final gradient = theme.previewGradientFor(entry.key);
        final accent = theme.previewColorFor(entry.key);

        return GestureDetector(
          onTap: () => theme.setPreset(entry.key),
          child: Column(
            children: [
              Expanded(
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(14),
                    gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: gradient),
                    border: Border.all(color: sel ? accent : Colors.transparent, width: 2.5),
                    boxShadow: sel ? [BoxShadow(color: accent.withValues(alpha: 0.45), blurRadius: 12, spreadRadius: 1)] : [],
                  ),
                  child: Stack(
                    children: [
                      Center(
                        child: Container(
                          width: 18,
                          height: 18,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: accent,
                            boxShadow: [BoxShadow(color: accent.withValues(alpha: 0.6), blurRadius: 8)],
                          ),
                        ),
                      ),
                      if (sel)
                        Positioned(top: 4, right: 4, child: Icon(Icons.check_circle, color: accent, size: 16)),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 4),
              Text(
                entry.value.split(' ').last,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 9, color: sel ? accent : colorScheme.onSurfaceVariant, fontWeight: sel ? FontWeight.w700 : FontWeight.normal),
              ),
            ],
          ),
        );
      },
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
          Text(value, style: TextStyle(fontWeight: FontWeight.w700, color: Theme.of(context).colorScheme.onSurface)),
        ],
      ),
    );
  }
}

class _SubLabel extends StatelessWidget {
  final String text;
  const _SubLabel(this.text);

  @override
  Widget build(BuildContext context) {
    return Text(text, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14));
  }
}

class _SettingsCard extends StatelessWidget {
  final String title;
  final IconData icon;
  final List<Widget> children;

  const _SettingsCard({required this.title, required this.icon, required this.children});

  @override
  Widget build(BuildContext context) {
    final brightness = Theme.of(context).brightness;
    final isDark = brightness == Brightness.dark;
    final theme = AppThemeService.instance;
    final onSurface = Theme.of(context).colorScheme.onSurface;
    final primary = theme.primaryColor;

    return Container(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 20),
      decoration: BoxDecoration(
        gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [theme.glassCardTop(brightness), theme.glassCardBottom(brightness)]),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: theme.glassBorderColor(brightness), width: 1.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [primary.withValues(alpha: 0.35), primary.withValues(alpha: 0.10)]),
                ),
                child: Icon(icon, size: 20, color: primary),
              ),
              const SizedBox(width: 12),
              Text(title, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800, letterSpacing: 1.2, color: onSurface.withValues(alpha: isDark ? 0.8 : 0.6))),
            ],
          ),
          const SizedBox(height: 16),
          ...children,
        ],
      ),
    );
  }
}
