import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

class LogService {
  LogService._();
  static final LogService instance = LogService._();

  static const int _maxLines = 2000;
  File? _logFile;
  final List<String> _memoryBuffer = [];
  bool _initialized = false;

  Future<void> init() async {
    if (_initialized) return;
    try {
      final dir = await getApplicationDocumentsDirectory();
      final logDir = Directory(p.join(dir.path, 'logs'));
      if (!await logDir.exists()) await logDir.create(recursive: true);
      _logFile = File(p.join(logDir.path, 'app_logs.txt'));
    } catch (e) {
      debugPrint('Failed to init LogService: $e');
    }
    _initialized = true;

    // Перехват ошибок Flutter (исправлено: добавлен .toString() для details.context)[cite: 1, 2]
    FlutterError.onError = (details) {
      logError(details.exception, details.stack, context: details.context?.toString());
      FlutterError.presentError(details);
    };

    // Перехват асинхронных ошибок
    PlatformDispatcher.instance.onError = (error, stack) {
      logError(error, stack, context: 'Async Error');
      return true;
    };
  }

  // Вспомогательный метод для добавления в буфер с ограничением по _maxLines[cite: 1, 2]
  void _addToBuffer(String text) {
    _memoryBuffer.add(text);
    if (_memoryBuffer.length > _maxLines) {
      _memoryBuffer.removeAt(0);
    }
  }

  void log(String message, {String tag = 'INFO'}) {
    final time = DateTime.now().toIso8601String();
    final line = '[$time] [$tag] $message';
    debugPrint(line);
    _addToBuffer(line);
    _writeToFile(line);
  }

  void logError(dynamic error, StackTrace? stack, {String? context}) {
    final time = DateTime.now().toIso8601String();
    final errorMsg = '[$time] [ERROR] $context\n$error\n$stack';
    debugPrint(errorMsg);
    _addToBuffer(errorMsg);
    _writeToFile(errorMsg);
  }

  Future<void> _writeToFile(String line) async {
    if (_logFile == null) return;
    try {
      // Простая ротация: если файл слишком большой, перезаписываем
      if (await _logFile!.exists() && await _logFile!.length() > 500 * 1024) {
        await _logFile!.writeAsString('--- Log Rotated ---\n', flush: true);
      }
      await _logFile!.writeAsString('$line\n', mode: FileMode.append, flush: true);
    } catch (_) {}
  }

  String getLogsAsString() {
    if (_logFile != null && _logFile!.existsSync()) {
      try {
        return _logFile!.readAsStringSync();
      } catch (_) {}
    }
    return _memoryBuffer.join('\n');
  }

  Future<void> shareLogs() async {
    if (_logFile == null || !await _logFile!.exists()) {
      // Если файла нет, создаем временный
      final tempDir = await getTemporaryDirectory();
      final tempFile = File(p.join(tempDir.path, 'app_logs.txt'));
      await tempFile.writeAsString(_memoryBuffer.join('\n'));
      await Share.shareXFiles([XFile(tempFile.path)]);
      return;
    }
    await Share.shareXFiles([XFile(_logFile!.path)]);
  }

  Future<void> clearLogs() async {
    _memoryBuffer.clear();
    if (_logFile != null && await _logFile!.exists()) {
      try {
        await _logFile!.delete();
      } catch (_) {}
    }
  }
}
