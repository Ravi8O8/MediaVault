// lib/main.dart
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';

import 'core/app_settings_keys.dart';
import 'core/app_theme_service.dart';
import 'core/database_service.dart';
import 'core/export_service.dart';
import 'core/glass_service.dart';
import 'core/log_service.dart';
import 'core/performance_monitor.dart';
import 'core/trash_cleanup_service.dart';
import 'features/lock/lock_screen.dart';

void main() {
  runZonedGuarded(() async {
    WidgetsFlutterBinding.ensureInitialized();

    await LogService.instance.init();
    LogService.instance.log('App starting...', tag: 'LIFECYCLE');

    PerformanceMonitor.instance.init();

    final db = DatabaseService();

    // Запускаем всё параллельно, чтобы ускорить старт.
    // LiquidGlass / Theme / Glass — не критичны (ловим ошибки внутри),
    // db.init() — критичен, при падении покажем экран ошибки.
    try {
      await Future.wait([
        LiquidGlassWidgets.initialize()
            .timeout(const Duration(seconds: 8))
            .catchError((Object e, StackTrace st) {
          LogService.instance.logError(e, st, context: 'LiquidGlass init');
        }),
        AppThemeService.instance
            .load()
            .timeout(const Duration(seconds: 5))
            .catchError((Object e, StackTrace st) {
          LogService.instance.logError(e, st, context: 'Theme load');
        }),
        GlassService.instance
            .load()
            .timeout(const Duration(seconds: 5))
            .catchError((Object e, StackTrace st) {
          LogService.instance.logError(e, st, context: 'Glass load');
        }),
        db.init().timeout(const Duration(seconds: 15)),
      ]);
    } catch (e, st) {
      LogService.instance.logError(e, st, context: 'DB init');
      runApp(const _FatalErrorApp(
        message: 'Не удалось открыть зашифрованную базу данных.\n'
            'Файл может быть повреждён или нет доступа к secure storage.\n\n'
            'Детали сохранены в логе.',
      ));
      return;
    }

    Future.microtask(() async {
      try {
        await ExportService.cleanupTempFiles();
      } catch (_) {}

      try {
        const storage = FlutterSecureStorage();
        final rawDays =
            await storage.read(key: AppSettingsKeys.trashAutoCleanupDays);
        final days =
            int.tryParse(rawDays ?? '') ?? TrashCleanupService.defaultDaysOld;

        if (days > 0) {
          final result = await TrashCleanupService.purgeOldTrash(
            db,
            daysOld: days,
            onDeleted: (path) {},
          );
          if (result.removedCount > 0) {
            LogService.instance.log(
                'Auto-purged ${result.removedCount} items (older than $days days)');
          }
        }
      } catch (e, st) {
        LogService.instance
            .logError(e, st, context: 'Auto trash cleanup failed');
      }
    });

    runApp(
      LiquidGlassWidgets.wrap(
        brightnessResolver: Theme.maybeBrightnessOf,
        child: MediaVaultApp(db: db),
      ),
    );
  }, (error, stack) {
    LogService.instance.logError(error, stack, context: 'Uncaught Zone Error');
  });
}

class MediaVaultApp extends StatelessWidget {
  final DatabaseService db;
  const MediaVaultApp({super.key, required this.db});

  @override
  Widget build(BuildContext context) {
    final themeService = AppThemeService.instance;
    return AnimatedBuilder(
      animation: themeService,
      builder: (context, _) {
        return MaterialApp(
          title: 'MediaVault',
          debugShowCheckedModeBanner: false,
          theme: themeService.buildTheme(Brightness.light),
          darkTheme: themeService.buildTheme(Brightness.dark),
          themeMode: themeService.mode,
          home: LockScreen(db: db),
        );
      },
    );
  }
}

class _FatalErrorApp extends StatelessWidget {
  final String message;
  const _FatalErrorApp({required this.message});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      home: Scaffold(
        backgroundColor: const Color(0xFF0F171E),
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.error_outline,
                    color: Colors.redAccent, size: 72),
                const SizedBox(height: 24),
                const Text(
                  'Ошибка инициализации',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  message,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Colors.white70,
                    fontSize: 14,
                    height: 1.5,
                  ),
                ),
                const SizedBox(height: 32),
                const Text(
                  'Отправьте файл лога разработчику',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.white38, fontSize: 12),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
