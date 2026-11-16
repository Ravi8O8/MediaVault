import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

class LogService {
  LogService._();
  static final LogService instance = LogService._();

  static const int _maxLines = 5000;
  static const int _maxFileBytes = 1024 * 1024; // 1 MB
  static const Duration _flushInterval = Duration(seconds: 2);

  File? _logFile;
  final List<String> _memoryBuffer = [];
  final List<String> _pendingWrites = [];
  bool _initialized = false;
  Timer? _flushTimer;
  bool _flushing = false;

  Future<void> init() async {
    if (_initialized) return;
    _initialized = true;

    try {
      final dir = await getApplicationDocumentsDirectory();
      final logDir = Directory(p.join(dir.path, 'logs'));
      if (!await logDir.exists()) await logDir.create(recursive: true);
      _logFile = File(p.join(logDir.path, 'app_logs.txt'));
      await _writeHeader();
    } catch (e) {
      debugPrint('LogService init error: $e');
    }

    FlutterError.onError = (details) {
      logError(details.exception, details.stack,
          context: details.context?.toString());
      FlutterError.presentError(details);
    };

    PlatformDispatcher.instance.onError = (error, stack) {
      logError(error, stack, context: 'Async Error');
      return true;
    };

    _flushTimer = Timer.periodic(_flushInterval, (_) => _flush());
  }

  Future<void> _writeHeader() async {
    if (_logFile == null) return;
    try {
      final buf = StringBuffer()
        ..writeln('========== MediaVault diagnostics ==========')
        ..writeln('Started: ${DateTime.now().toIso8601String()}')
        ..writeln('Platform: ${Platform.operatingSystem} '
            '${Platform.operatingSystemVersion}')
        ..writeln('Dart: ${Platform.version}')
        ..writeln('Locale: ${Platform.localeName}')
        ..writeln('=============================================');
      await _logFile!
          .writeAsString(buf.toString(), mode: FileMode.append, flush: true);
    } catch (_) {}
  }

  void log(String message, {String tag = 'INFO'}) {
    final time = DateTime.now().toIso8601String();
    final line = '[$time] [$tag] $message';
    debugPrint(line);
    _addToBuffer(line);
    _pendingWrites.add(line);
  }

  void logError(dynamic error, StackTrace? stack, {String? context}) {
    final time = DateTime.now().toIso8601String();
    final errorMsg = '[$time] [ERROR] ${context ?? 'unknown'}\n'
        '$error\n${stack ?? 'no stack'}';
    debugPrint(errorMsg);
    _addToBuffer(errorMsg);
    _pendingWrites.add(errorMsg);
    unawaited(_flush());
  }

  void _addToBuffer(String text) {
    _memoryBuffer.add(text);
    while (_memoryBuffer.length > _maxLines) {
      _memoryBuffer.removeAt(0);
    }
  }

  Future<void> _flush() async {
    if (_flushing || _logFile == null || _pendingWrites.isEmpty) return;
    _flushing = true;
    try {
      final toWrite = List<String>.from(_pendingWrites);
      _pendingWrites.clear();

      // Ротация: если файл > 1 MB — перезаписываем заново с шапкой
      if (await _logFile!.exists() &&
          await _logFile!.length() > _maxFileBytes) {
        try {
          await _logFile!.delete();
        } catch (_) {}
        await _writeHeader();
      }

      await _logFile!.writeAsString(
        '${toWrite.join('\n')}\n',
        mode: FileMode.append,
        flush: true,
      );
    } catch (e) {
      debugPrint('LogService flush error: $e');
    } finally {
      _flushing = false;
    }
  }

  Future<String> getLogsAsString() async {
    await _flush();
    if (_logFile != null && await _logFile!.exists()) {
      try {
        return await _logFile!.readAsString();
      } catch (_) {}
    }
    return _memoryBuffer.join('\n');
  }

  Future<void> shareLogs() async {
    await _flush();
    File? fileToShare = _logFile;
    if (fileToShare == null || !await fileToShare.exists()) {
      final tempDir = await getTemporaryDirectory();
      fileToShare = File(p.join(tempDir.path, 'app_logs.txt'));
      await fileToShare.writeAsString(
        '${_memoryBuffer.join('\n')}\n---\n(no log file was available)',
      );
    }
    await Share.shareXFiles([XFile(fileToShare.path)],
        subject: 'MediaVault logs');
  }

  Future<void> copyLogsToClipboard() async {
    final logs = await getLogsAsString();
    await Clipboard.setData(ClipboardData(text: logs));
  }

  Future<void> clearLogs() async {
    _memoryBuffer.clear();
    _pendingWrites.clear();
    if (_logFile != null && await _logFile!.exists()) {
      try {
        await _logFile!.delete();
      } catch (_) {}
    }
    await _writeHeader();
  }

  Future<void> dispose() async {
    _flushTimer?.cancel();
    await _flush();
  }
}
