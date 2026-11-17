import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

/// Показывает/обновляет одно системное уведомление с прогрессом импорта.
/// Работает пока приложение в памяти — даже если свёрнуто в фон.
class ImportNotificationService {
  ImportNotificationService._();

  static final _plugin = FlutterLocalNotificationsPlugin();
  static const _channelId = 'import_channel_v1';
  static const _channelName = 'Импорт файлов';
  static const _notificationId = 7071;

  static bool _initialized = false;
  static bool _permissionAsked = false;

  static Future<void> init() async {
    if (_initialized) return;
    _initialized = true;

    try {
      const androidInit = AndroidInitializationSettings('@drawable/ic_stat_notify');
      const initSettings = InitializationSettings(android: androidInit);

      await _plugin.initialize(initSettings);

      final androidImpl = _plugin.resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>();

      await androidImpl?.createNotificationChannel(
        const AndroidNotificationChannel(
          _channelId,
          _channelName,
          description: 'Прогресс импорта файлов',
          importance: Importance.low,
          playSound: false,
          showBadge: false,
          enableVibration: false,
        ),
      );

      if (!_permissionAsked) {
        _permissionAsked = true;
        await androidImpl?.requestNotificationsPermission();
      }
    } catch (e) {
      debugPrint('ImportNotificationService init error: $e');
    }
  }

  static AndroidNotificationDetails _progressDetails(int percent) {
    return AndroidNotificationDetails(
      _channelId,
      _channelName,
      channelDescription: 'Прогресс импорта файлов',
      importance: Importance.low,
      priority: Priority.low,
      icon: '@drawable/ic_stat_notify',
      showProgress: true,
      maxProgress: 100,
      progress: percent,
      ongoing: true,
      autoCancel: false,
      onlyAlertOnce: true,
      playSound: false,
      enableVibration: false,
      showWhen: false,
      category: AndroidNotificationCategory.progress,
      visibility: NotificationVisibility.public,
    );
  }

  static AndroidNotificationDetails _completeDetails(int success, int failed) {
    return AndroidNotificationDetails(
      _channelId,
      _channelName,
      channelDescription: 'Прогресс импорта файлов',
      importance: Importance.defaultImportance,
      priority: Priority.defaultPriority,
      icon: '@drawable/ic_stat_notify',
      ongoing: false,
      autoCancel: true,
      onlyAlertOnce: false,
      playSound: true,
      enableVibration: false,
      showWhen: true,
      category: AndroidNotificationCategory.status,
      visibility: NotificationVisibility.public,
    );
  }

  static Future<void> showProgress({
    required int processed,
    required int total,
    String? currentFile,
  }) async {
    try {
      await init();
      final percent = total > 0 ? ((processed / total) * 100).round() : 0;
      final body = currentFile == null || currentFile.isEmpty
          ? '$processed из $total • $percent%'
          : '$processed из $total • $percent%\n$currentFile';

      await _plugin.show(
        _notificationId,
        'Импорт файлов',
        body,
        NotificationDetails(android: _progressDetails(percent)),
      );
    } catch (e) {
      debugPrint('showProgress error: $e');
    }
  }

  static Future<void> showComplete({
    required int success,
    required int failed,
  }) async {
    try {
      await init();
      final body = failed > 0
          ? 'Импортировано: $success • ошибок: $failed'
          : 'Импортировано файлов: $success';
      await _plugin.show(
        _notificationId,
        'Импорт завершён',
        body,
        NotificationDetails(android: _completeDetails(success, failed)),
      );
    } catch (e) {
      debugPrint('showComplete error: $e');
    }
  }

  static Future<void> showCancelled() async {
    try {
      await init();
      await _plugin.show(
        _notificationId,
        'Импорт отменён',
        'Пользователь прервал импорт',
        NotificationDetails(android: _completeDetails(0, 0)),
      );
    } catch (e) {
      debugPrint('showCancelled error: $e');
    }
  }

  static Future<void> cancel() async {
    try {
      await _plugin.cancel(_notificationId);
    } catch (_) {}
  }
}
