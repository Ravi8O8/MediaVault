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
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      title: const Text('Экспорт', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Файлов выбрано: ${widget.count}',
              style: const TextStyle(color: Colors.tealAccent, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 20),
            SwitchListTile.adaptive(
              contentPadding: EdgeInsets.zero,
              activeThumbColor: Colors.tealAccent,
              title: const Text('Собрать в ZIP-архив', style: TextStyle(color: Colors.white)),
              subtitle: const Text('Удобно для переноса на ПК', style: TextStyle(color: Colors.white54, fontSize: 12)),
              value: _zip,
              onChanged: (v) => setState(() => _zip = v),
            ),
            if (_zip) ...[
              SwitchListTile.adaptive(
                contentPadding: EdgeInsets.zero,
                activeThumbColor: Colors.tealAccent,
                title: const Text('Зашифровать архив (.mvault)', style: TextStyle(color: Colors.white)),
                subtitle: const Text('Для безопасного бэкапа', style: TextStyle(color: Colors.white54, fontSize: 12)),
                value: _encryptZip,
                onChanged: (v) => setState(() => _encryptZip = v),
              ),
            ] else
              SwitchListTile.adaptive(
                contentPadding: EdgeInsets.zero,
                activeThumbColor: Colors.tealAccent,
                title: const Text('Сжать фото (WebP)', style: TextStyle(color: Colors.white)),
                subtitle: const Text('Меньше размер, без потери качества', style: TextStyle(color: Colors.white54, fontSize: 12)),
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
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
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
  String _status = 'Подготовка...';
  String _currentFile = '';

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
      onStatus: (status, currentFile) {
        if (!mounted) return;
        setState(() {
          _status = status;
          _currentFile = currentFile;
        });
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
  }

  void _cancel() {
    if (_cancelled) return;
    setState(() => _cancelled = true);
  }

  @override
  Widget build(BuildContext context) {
    final total = widget.ids.length;
    final progress = total > 0 ? _done / total : 0.0;
    final percent = (progress * 100).round();

    return PopScope(
      canPop: false,
      child: Dialog(
        backgroundColor: Colors.transparent,
        elevation: 0,
        insetPadding: const EdgeInsets.symmetric(horizontal: 24),
        child: Container(
          padding: const EdgeInsets.fromLTRB(24, 28, 24, 24),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0xFF1B2A38), Color(0xFF0E161F)],
            ),
            borderRadius: BorderRadius.circular(32),
            border: Border.all(color: Colors.tealAccent.withValues(alpha: 0.3), width: 1.5),
            boxShadow: [
              BoxShadow(color: Colors.tealAccent.withValues(alpha: 0.15), blurRadius: 40, spreadRadius: -5),
              BoxShadow(color: Colors.black.withValues(alpha: 0.5), blurRadius: 30, spreadRadius: 5),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (_finished && _result != null) ...[
                Icon(
                  _result!.error != null ? Icons.error_outline : Icons.check_circle_rounded,
                  color: _result!.error != null ? Colors.redAccent : Colors.tealAccent,
                  size: 64,
                ),
                const SizedBox(height: 16),
                Text(
                  _result!.error != null ? 'Ошибка' : 'Готово',
                  style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 8),
                Text(
                  _result!.error ?? 'Сохранено файлов: ${_result!.ok}',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: _result!.error != null ? Colors.redAccent : Colors.tealAccent,
                    fontSize: 14,
                  ),
                ),
              ] else ...[
                SizedBox(
                  width: 120,
                  height: 120,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      CircularProgressIndicator(
                        value: 1,
                        strokeWidth: 8,
                        valueColor: AlwaysStoppedAnimation(Colors.white.withValues(alpha: 0.05)),
                      ),
                      CircularProgressIndicator(
                        value: progress,
                        strokeWidth: 8,
                        strokeCap: StrokeCap.round,
                        valueColor: const AlwaysStoppedAnimation(Colors.tealAccent),
                      ),
                      Center(
                        child: Text(
                          '$percent%',
                          style: const TextStyle(color: Colors.white, fontSize: 28, fontWeight: FontWeight.w800),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),
                Text(
                  _status,
                  style: const TextStyle(color: Colors.tealAccent, fontSize: 16, fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 8),
                Text(
                  _currentFile,
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: Colors.white70, fontSize: 13),
                ),
                const SizedBox(height: 12),
                Text(
                  '$_done / $total файлов',
                  style: TextStyle(color: Colors.white.withValues(alpha: 0.4), fontSize: 12),
                ),
                const SizedBox(height: 24),
                TextButton(
                  onPressed: _cancelled ? null : _cancel,
                  style: TextButton.styleFrom(
                    foregroundColor: Colors.redAccent,
                    padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 24),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                      side: BorderSide(color: Colors.redAccent.withValues(alpha: 0.4)),
                    ),
                  ),
                  child: Text(_cancelled ? 'Отмена...' : 'Отменить'),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
