import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import 'log_service.dart';

/// Показывает/обновляет одно системное уведомление с прогрессом импорта.
/// Работает пока приложение в памяти — даже если свёрнуто в фон.
class ImportNotificationService {
  ImportNotificationService._();

  static final _plugin = FlutterLocalNotificationsPlugin();
  static const _channelId = 'import_channel_v1';
  static const _channelName = 'Импорт файлов';
  static const _notificationId = 7071;

  static Future<bool>? _initFuture;
  static bool _permissionGranted = false;
  static bool _permissionAsked = false;

  /// Инициализация + запрос разрешения. Идемпотентно и потокобезопасно.
  static Future<bool> init() {
    return _initFuture ??= _doInit();
  }

  static Future<bool> _doInit() async {
    try {
      const androidInit =
          AndroidInitializationSettings('@drawable/ic_stat_notify');
      const initSettings = InitializationSettings(android: androidInit);

      await _plugin.initialize(initSettings);

      final androidImpl = _plugin.resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>();

      // 1) Сначала разрешение (Android 13+)
      if (!_permissionAsked) {
        _permissionAsked = true;
        try {
          final granted = await androidImpl?.requestNotificationsPermission();
          _permissionGranted = granted ?? true;
        } catch (e) {
          LogService.instance.log('Notification permission error: $e',
              tag: 'NOTIF');
          _permissionAsked = false; // дать шанс при следующем запуске
          _permissionGranted = false;
        }
      } else {
        try {
          final enabled =
              await androidImpl?.areNotificationsEnabled() ?? true;
          _permissionGranted = enabled;
        } catch (_) {
          _permissionGranted = false;
        }
      }

      // 2) Канал
      try {
        await androidImpl?.createNotificationChannel(
          const AndroidNotificationChannel(
            _channelId,
            _channelName,
            description: 'Прогресс импорта файлов',
            importance: Importance.defaultImportance,
            playSound: false,
            showBadge: false,
            enableVibration: false,
          ),
        );
      } catch (e) {
        LogService.instance.log('Channel create error: $e', tag: 'NOTIF');
      }

      LogService.instance.log(
          'Notifications init: granted=$_permissionGranted', tag: 'NOTIF');
      return _permissionGranted;
    } catch (e, st) {
      LogService.instance.logError(e, st, context: 'Notif init');
      _initFuture = null; // можно повторить
      return false;
    }
  }

  static AndroidNotificationDetails _progressDetails(int percent) {
    return AndroidNotificationDetails(
      _channelId,
      _channelName,
      channelDescription: 'Прогресс импорта файлов',
      importance: Importance.defaultImportance,
      priority: Priority.defaultPriority,
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

  static AndroidNotificationDetails _completeDetails() {
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
      playSound: false,
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
    final ok = await init();
    if (!ok) return;
    try {
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
      LogService.instance.log('showProgress error: $e', tag: 'NOTIF');
    }
  }

  static Future<void> showComplete({
    required int success,
    required int failed,
  }) async {
    final ok = await init();
    if (!ok) return;
    try {
      final body = failed > 0
          ? 'Импортировано: $success • ошибок: $failed'
          : 'Импортировано файлов: $success';
      await _plugin.show(
        _notificationId,
        'Импорт завершён',
        body,
        NotificationDetails(android: _completeDetails()),
      );
    } catch (e) {
      LogService.instance.log('showComplete error: $e', tag: 'NOTIF');
    }
  }

  static Future<void> showCancelled() async {
    final ok = await init();
    if (!ok) return;
    try {
      await _plugin.show(
        _notificationId,
        'Импорт отменён',
        'Пользователь прервал импорт',
        NotificationDetails(android: _completeDetails()),
      );
    } catch (e) {
      LogService.instance.log('showCancelled error: $e', tag: 'NOTIF');
    }
  }

  static Future<void> cancel() async {
    try {
      await _plugin.cancel(_notificationId);
    } catch (_) {}
  }

  /// Для UI — показать подсказку, если уведомления запрещены.
  static Future<bool> ensurePermission() async {
    return await init();
  }
}
