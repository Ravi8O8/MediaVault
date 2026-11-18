import 'package:flutter/material.dart';

import '../../core/crypto_service.dart';
import '../../core/database_service.dart';
import '../../core/export_to_gallery_service.dart';
import '../../core/ui_helpers.dart';

Future<void> showExportToGalleryDialog(
  BuildContext context,
  DatabaseService db,
  List<int> ids,
) async {
  if (ids.isEmpty) return;

  final options = await showDialog<ExportOptions>(
    context: context,
    builder: (_) => _ExportOptionsDialog(count: ids.length),
  );
  if (options == null || !context.mounted) return;

  final result = await showDialog<ExportResult>(
    context: context,
    barrierDismissible: false,
    builder: (_) => _ExportProgressDialog(
      db: db,
      ids: ids,
      options: options,
    ),
  );

  if (result == null || !context.mounted) return;
  if (result.error != null) {
    showAppSnackBar(context, result.error!, isError: true);
    return;
  }
  if (result.ok == 0) {
    showAppSnackBar(context, 'Не удалось сохранить файлы', isError: true);
    return;
  }

  final suffix = result.failed > 0 ? ' (ошибок: ${result.failed})' : '';
  if (options.toZip) {
    final filename = result.outputPath?.split('/').last ?? 'архив';
    showAppSnackBar(context, 'Сохранено: $filename$suffix');
  } else {
    showAppSnackBar(context, 'Сохранено в галерею: ${result.ok}$suffix');
  }
}

class _ExportOptionsDialog extends StatefulWidget {
  final int count;
  const _ExportOptionsDialog({required this.count});

  @override
  State<_ExportOptionsDialog> createState() => _ExportOptionsDialogState();
}

class _ExportOptionsDialogState extends State<_ExportOptionsDialog> {
  bool _compress = true;
  bool _zip = false;
  bool _encryptZip = false;
  VaultEncryptionType _encType = VaultEncryptionType.aesCtr;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: const Color(0xFF1B2A38),
      title: const Text('Экспорт', style: TextStyle(color: Colors.white)),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Файлов: ${widget.count}',
              style: const TextStyle(color: Colors.white70),
            ),
            const SizedBox(height: 16),
            SwitchListTile.adaptive(
              contentPadding: EdgeInsets.zero,
              activeThumbColor: Colors.tealAccent,
              title: const Text(
                'Собрать в ZIP-архив',
                style: TextStyle(color: Colors.white),
              ),
              subtitle: const Text(
                'Удобно для переноса на ПК',
                style: TextStyle(color: Colors.white54, fontSize: 12),
              ),
              value: _zip,
              onChanged: (v) => setState(() => _zip = v),
            ),
            if (_zip) ...[
              SwitchListTile.adaptive(
                contentPadding: EdgeInsets.zero,
                activeThumbColor: Colors.tealAccent,
                title: const Text(
                  'Зашифровать архив (.mvault)',
                  style: TextStyle(color: Colors.white),
                ),
                subtitle: const Text(
                  'Для безопасного бэкапа',
                  style: TextStyle(color: Colors.white54, fontSize: 12),
                ),
                value: _encryptZip,
                onChanged: (v) => setState(() => _encryptZip = v),
              ),
              if (_encryptZip)
                Padding(
                  padding: const EdgeInsets.only(left: 16, top: 8),
                  child: DropdownButton<VaultEncryptionType>(
                    value: _encType,
                    dropdownColor: const Color(0xFF1B2A38),
                    style: const TextStyle(color: Colors.white),
                    items: [
                      VaultEncryptionType.aesCtr,
                    ].map((t) => DropdownMenuItem(
                      value: t,
                      child: Text(t.label),
                    )).toList(),
                    onChanged: (v) {
                      if (v != null) setState(() => _encType = v);
                    },
                  ),
                ),
            ] else
              SwitchListTile.adaptive(
                contentPadding: EdgeInsets.zero,
                activeThumbColor: Colors.tealAccent,
                title: const Text(
                  'Сжать фото (WebP)',
                  style: TextStyle(color: Colors.white),
                ),
                subtitle: const Text(
                  'Меньше размер, без видимой потери качества',
                  style: TextStyle(color: Colors.white54, fontSize: 12),
                ),
                value: _compress,
                onChanged: (v) => setState(() => _compress = v),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Отмена', style: TextStyle(color: Colors.white70)),
        ),
        ElevatedButton(
          onPressed: () => Navigator.pop(
            context,
            ExportOptions(
              compressImages: _compress,
              toZip: _zip,
              encryptZip: _encryptZip,
              encType: _encType,
            ),
          ),
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.teal,
            foregroundColor: Colors.white,
          ),
          child: const Text('Начать'),
        ),
      ],
    );
  }
}

class _ExportProgressDialog extends StatefulWidget {
  final DatabaseService db;
  final List<int> ids;
  final ExportOptions options;

  const _ExportProgressDialog({
    required this.db,
    required this.ids,
    required this.options,
  });

  @override
  State<_ExportProgressDialog> createState() => _ExportProgressDialogState();
}

class _ExportProgressDialogState extends State<_ExportProgressDialog> {
  int _done = 0;
  bool _cancelled = false;
  bool _finished = false;
  ExportResult? _result;

  @override
  void initState() {
    super.initState();
    _run();
  }

  Future<void> _run() async {
    final total = widget.ids.length;
    final result = await ExportToGalleryService.export(
      widget.db,
      widget.ids,
      options: widget.options,
      onProgress: (done, t) {
        if (!mounted) return;
        setState(() => _done = done);
      },
      isCancelled: () => _cancelled,
    );
    if (!mounted) return;
    setState(() {
      _result = result;
      _finished = true;
    });

    await Future.delayed(const Duration(milliseconds: 800));
    if (mounted) Navigator.pop(context, result);
    if (total == 0) return;
  }

  void _cancel() {
    if (_cancelled) return;
    setState(() => _cancelled = true);
  }

  @override
  Widget build(BuildContext context) {
    final total = widget.ids.length;
    final progress = total > 0 ? _done / total : 0.0;

    return PopScope(
      canPop: false,
      child: AlertDialog(
        backgroundColor: const Color(0xFF1B2A38),
        title: const Text('Экспорт', style: TextStyle(color: Colors.white)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (_finished && _result != null) ...[
              Icon(
                _result!.error != null ? Icons.error_outline : Icons.check_circle,
                color: _result!.error != null ? Colors.redAccent : Colors.tealAccent,
                size: 48,
              ),
              const SizedBox(height: 12),
              Text(
                _result!.error != null
                    ? _result!.error!
                    : 'Готово: ${_result!.ok}'
                        '${_result!.failed > 0 ? '\nОшибок: ${_result!.failed}' : ''}',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: _result!.error != null ? Colors.redAccent : Colors.white70,
                ),
              ),
            ] else ...[
              LinearProgressIndicator(
                value: progress,
                minHeight: 6,
                backgroundColor: Colors.white12,
                valueColor: const AlwaysStoppedAnimation(Colors.tealAccent),
              ),
              const SizedBox(height: 12),
              Text(
                '$_done / $total',
                style: const TextStyle(color: Colors.white70),
              ),
              if (_cancelled) ...[
                const SizedBox(height: 8),
                const Text('Отменяется…', style: TextStyle(color: Colors.white38, fontSize: 12)),
              ],
            ],
          ],
        ),
        actions: _finished
            ? null
            : [
                TextButton(
                  onPressed: _cancelled ? null : _cancel,
                  child: Text(
                    _cancelled ? 'Отменяется…' : 'Отменить',
                    style: TextStyle(color: _cancelled ? Colors.white38 : Colors.redAccent),
                  ),
                ),
              ],
      ),
    );
  }
}
