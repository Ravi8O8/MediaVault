// lib/core/performance_monitor.dart
import 'package:flutter/scheduler.dart';

import 'log_service.dart';

/// Ловит «фризы» UI через SchedulerBinding timings.
/// Пишет в LogService всё, что дольше порога (2 кадра при 60fps).
class PerformanceMonitor {
  PerformanceMonitor._();
  static final PerformanceMonitor instance = PerformanceMonitor._();

  bool _initialized = false;

  /// Сколько было «медленных» кадров за сессию.
  int _jankCount = 0;
  int get jankCount => _jankCount;

  /// Последние N медленных кадров для быстрого просмотра.
  final List<String> _recent = [];
  static const int _maxRecent = 50;

  /// Порог «фриза» в микросекундах. 32000 us = 32 мс (~2 кадра 60fps).
  static const int _jankThresholdUs = 32000;

  void init() {
    if (_initialized) return;
    _initialized = true;
    SchedulerBinding.instance.addTimingsCallback(_onTimings);
  }

  void _onTimings(List<FrameTiming> timings) {
    for (final t in timings) {
      final buildUs = t.buildDuration.inMicroseconds;
      final rasterUs = t.rasterDuration.inMicroseconds;
      final totalUs = buildUs + rasterUs;
      if (totalUs < _jankThresholdUs) continue;

      _jankCount++;
      final line = 'build=${buildUs}us raster=${rasterUs}us total=${totalUs}us';
      _recent.add(line);
      while (_recent.length > _maxRecent) {
        _recent.removeAt(0);
      }
      LogService.instance.log('JANK $line', tag: 'PERF');
    }
  }

  List<String> recentJankLines() => List.unmodifiable(_recent);

  String summaryText() {
    final buf = StringBuffer();
    buf.writeln('Jank frames (>${_jankThresholdUs ~/ 1000}ms): $_jankCount');
    if (_recent.isEmpty) {
      buf.writeln('(нет недавних фризов)');
    } else {
      buf.writeln('Последние:');
      for (final l in _recent) {
        buf.writeln('  $l');
      }
    }
    return buf.toString();
  }
}
