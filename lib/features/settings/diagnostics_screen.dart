// lib/features/settings/diagnostics_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../../core/app_info.dart';
import '../../core/log_service.dart';
import '../../core/performance_monitor.dart';
import '../../core/ui_helpers.dart';

/// Экран диагностики: показывает логи прямо в приложении,
/// плюс сводку по фризам. Можно скопировать всё одной кнопкой.
class DiagnosticsScreen extends StatefulWidget {
  const DiagnosticsScreen({super.key});

  @override
  State<DiagnosticsScreen> createState() => _DiagnosticsScreenState();
}

class _DiagnosticsScreenState extends State<DiagnosticsScreen> {
  static const _storage = FlutterSecureStorage();

  String _logs = '';
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final logs = await LogService.instance.getLogsAsString();
    if (!mounted) return;
    setState(() {
      _logs = logs;
      _loading = false;
    });
  }

  Future<void> _copyAll() async {
    final buf = StringBuffer();
    buf.writeln('=== MediaVault diagnostics ===');
    buf.writeln('App: ${AppInfo.versionLabel}');
    buf.writeln('Time: ${DateTime.now().toIso8601String()}');
    buf.writeln();
    buf.writeln('=== PERFORMANCE ===');
    buf.write(PerformanceMonitor.instance.summaryText());
    buf.writeln();
    buf.writeln('=== STORAGE (masked) ===');
    try {
      final keys = await _storage.readAll();
      for (final k in keys.keys) {
        buf.writeln('$k = <set>');
      }
    } catch (e) {
      buf.writeln('storage read error: $e');
    }
    buf.writeln();
    buf.writeln('=== LOGS ===');
    buf.write(_logs);

    await Clipboard.setData(ClipboardData(text: buf.toString()));
    if (!mounted) return;
    showAppSnackBar(context, 'Диагностика скопирована в буфер');
  }

  Future<void> _clear() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Очистить логи?'),
        content: const Text('Это удалит все сохранённые записи лога.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Отмена'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child:
                const Text('Очистить', style: TextStyle(color: Colors.redAccent)),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await LogService.instance.clearLogs();
    await _load();
    if (!mounted) return;
    showAppSnackBar(context, 'Логи очищены');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Диагностика'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Обновить',
            onPressed: _load,
          ),
          IconButton(
            icon: const Icon(Icons.copy),
            tooltip: 'Скопировать всё',
            onPressed: _copyAll,
          ),
          IconButton(
            icon: const Icon(Icons.delete_outline, color: Colors.redAccent),
            tooltip: 'Очистить',
            onPressed: _clear,
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(12),
              children: [
                _SectionHeader('ПРОИЗВОДИТЕЛЬНОСТЬ'),
                _GlassBox(
                  child: SelectableText(
                    PerformanceMonitor.instance.summaryText(),
                    style: const TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 12,
                      height: 1.4,
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                _SectionHeader('ЛОГИ (${_logs.length} символов)'),
                _GlassBox(
                  child: SelectableText(
                    _logs.isEmpty ? 'Логов нет' : _logs,
                    style: const TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 11,
                      height: 1.35,
                    ),
                  ),
                ),
                const SizedBox(height: 24),
              ],
            ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String text;
  const _SectionHeader(this.text);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w800,
          letterSpacing: 1.2,
          color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6),
        ),
      ),
    );
  }
}

class _GlassBox extends StatelessWidget {
  final Widget child;
  const _GlassBox({required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: child,
    );
  }
}
