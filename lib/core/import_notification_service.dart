// lib/core/import_notification_service.dart
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import 'log_service.dart';

/// Показывает/обновляет одно системное уведомление с прогрессом импорта.
/// Работает пока приложение в памяти — даже если свёрнуто в фон.
///
/// Важно: НЕ пропускаем показ даже при сомнительном результате init() —
/// лучше попытаться и залогировать ошибку, чем молчать.
class ImportNotificationService {
  ImportNotificationService._();

  static final _plugin = FlutterLocalNotificationsPlugin();
  static const _channelId = 'import_channel_v1';
  static const _channelName = 'Импорт файлов';
  static const _notificationId = 7071;

  static Future<void>? _initFuture;
  static bool _initialized = false;
  static bool _permissionGranted = false;
  static bool _permissionAsked = false;

  /// Инициализация + запрос разрешения. Идемпотентно.
  /// НЕ кэширует результат, если инициализация упала — даст шанс перезапуститься.
  static Future<void> init() {
    return _initFuture ??= _doInit().catchError((e, st) {
      LogService.instance.logError(e, st, context: 'Notif init outer');
      _initFuture = null; // дать возможность повторить
    });
  }

  static Future<void> _doInit() async {
    try {
      const androidInit =
          AndroidInitializationSettings('@drawable/ic_stat_notify');
      const initSettings = InitializationSettings(android: androidInit);
      await _plugin.initialize(initSettings);
      _initialized = true;
      LogService.instance.log('plugin.initialize OK', tag: 'NOTIF');
    } catch (e, st) {
      LogService.instance.logError(e, st, context: 'plugin.initialize');
      _initialized = false;
      return;
    }

    final androidImpl = _plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();

    // Разрешение (Android 13+)
    if (!_permissionAsked) {
      _permissionAsked = true;
      try {
        final granted = await androidImpl?.requestNotificationsPermission();
        _permissionGranted = granted ?? true;
        LogService.instance.log(
            'requestNotificationsPermission -> $granted', tag: 'NOTIF');
      } catch (e) {
        LogService.instance.log('request permission failed: $e',
            tag: 'NOTIF');
        _permissionGranted = false;
        _permissionAsked = false; // дать шанс в следующий раз
      }
    } else {
      try {
        final enabled = await androidImpl?.areNotificationsEnabled() ?? true;
        _permissionGranted = enabled;
        LogService.instance.log('areNotificationsEnabled -> $enabled',
            tag: 'NOTIF');
      } catch (e) {
        LogService.instance.log('areNotificationsEnabled check failed: $e',
            tag: 'NOTIF');
        _permissionGranted = false;
      }
    }

    // Канал
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
      LogService.instance.log('channel created', tag: 'NOTIF');
    } catch (e) {
      LogService.instance.log('channel create failed: $e', tag: 'NOTIF');
    }

    LogService.instance.log(
      'Notifications ready: initialized=$_initialized granted=$_permissionGranted',
      tag: 'NOTIF',
    );
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

  /// Показ прогресса. Всегда пытаемся показать (best-effort),
  /// потому что даже при формально «нет разрешения» на некоторых OEM
  /// уведомление всё равно проскакивает.
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
      LogService.instance.log('showProgress error: $e', tag: 'NOTIF');
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
        NotificationDetails(android: _completeDetails()),
      );
    } catch (e) {
      LogService.instance.log('showComplete error: $e', tag: 'NOTIF');
    }
  }

  static Future<void> showCancelled() async {
    try {
      await init();
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

  /// Для UI: показать подсказку, если уведомления запрещены.
  static Future<bool> ensurePermission() async {
    await init();
    return _permissionGranted && _initialized;
  }

  /// Для экрана диагностики — вернуть текущее состояние.
  static Map<String, dynamic> debugState() => {
        'initialized': _initialized,
        'permissionGranted': _permissionGranted,
        'permissionAsked': _permissionAsked,
      };
}
