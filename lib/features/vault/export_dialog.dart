import 'package:flutter/material.dart';

import '../../core/database_service.dart';
import '../../core/export_to_gallery_service.dart';
import '../../core/ui_helpers.dart';

class _ExportOptions {
  final bool compressImages;
  const _ExportOptions({required this.compressImages});
}

Future<void> showExportToGalleryDialog(
  BuildContext context,
  DatabaseService db,
  List<int> ids,
) async {
  if (ids.isEmpty) return;

  final options = await showDialog<_ExportOptions>(
    context: context,
    builder: (_) => _ExportOptionsDialog(count: ids.length),
  );
  if (options == null) return;
  if (!context.mounted) return;

  final result = await showDialog<ExportResult>(
    context: context,
    barrierDismissible: false,
    builder: (_) => _ExportProgressDialog(
      db: db,
      ids: ids,
      compressImages: options.compressImages,
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
  showAppSnackBar(
    context,
    'Сохранено в галерею: ${result.ok}$suffix',
  );
}

class _ExportOptionsDialog extends StatefulWidget {
  final int count;
  const _ExportOptionsDialog({required this.count});

  @override
  State<_ExportOptionsDialog> createState() => _ExportOptionsDialogState();
}

class _ExportOptionsDialogState extends State<_ExportOptionsDialog> {
  bool _compress = true;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: const Color(0xFF1B2A38),
      title: Text(
        'Экспорт в галерею',
        style: const TextStyle(color: Colors.white),
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Будет сохранено файлов: ${widget.count}',
            style: const TextStyle(color: Colors.white70),
          ),
          const SizedBox(height: 16),
          SwitchListTile.adaptive(
            contentPadding: EdgeInsets.zero,
            activeThumbColor: Colors.tealAccent,
            title: const Text(
              'Сжать фото (WebP)',
              style: TextStyle(color: Colors.white),
            ),
            subtitle: const Text(
              'Меньше размер, без видимой потери качества.\nНа видео не влияет.',
              style: TextStyle(color: Colors.white54, fontSize: 12),
            ),
            value: _compress,
            onChanged: (v) => setState(() => _compress = v),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Отмена',
              style: TextStyle(color: Colors.white70)),
        ),
        ElevatedButton(
          onPressed: () => Navigator.pop(
            context,
            _ExportOptions(compressImages: _compress),
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
  final bool compressImages;

  const _ExportProgressDialog({
    required this.db,
    required this.ids,
    required this.compressImages,
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
      compressImages: widget.compressImages,
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
      if (_cancelled) _done = _done; // keep
    });
    if (result.error == null && result.ok + result.failed == 0) {
      // ничего не сделали — закроем мгновенно
      if (mounted) Navigator.pop(context, result);
      return;
    }
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
        title: const Text('Экспорт в галерею',
            style: TextStyle(color: Colors.white)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (_finished && _result != null) ...[
              const Icon(Icons.check_circle,
                  color: Colors.tealAccent, size: 48),
              const SizedBox(height: 12),
              Text(
                'Готово: ${_result!.ok}'
                '${_result!.failed > 0 ? '\nОшибок: ${_result!.failed}' : ''}',
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white70),
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
                const Text(
                  'Отменяется…',
                  style: TextStyle(color: Colors.white38, fontSize: 12),
                ),
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
                    style: TextStyle(
                      color: _cancelled ? Colors.white38 : Colors.redAccent,
                    ),
                  ),
                ),
              ],
      ),
    );
  }
}
