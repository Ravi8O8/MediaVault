import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';

import 'core/app_settings_keys.dart';
import 'core/app_theme_service.dart';
import 'core/database_service.dart';
import 'core/log_service.dart';
import 'core/thumbnail_cache.dart';
import 'core/trash_cleanup_service.dart';
import 'features/lock/lock_screen.dart';

void main() {
  runZonedGuarded(() async {
    WidgetsFlutterBinding.ensureInitialized();

    await LogService.instance.init();
    LogService.instance.log('App starting...', tag: 'LIFECYCLE');

    try {
      await LiquidGlassWidgets.initialize().timeout(const Duration(seconds: 8));
    } catch (e, st) {
      await LogService.instance.logError(e, st, context: 'LiquidGlass init');
    }

    try {
      await AppThemeService.instance.load().timeout(const Duration(seconds: 5));
    } catch (e, st) {
      await LogService.instance.logError(e, st, context: 'Theme load');
    }

    final db = DatabaseService();
    try {
      await db.init().timeout(const Duration(seconds: 15));
    } catch (e, st) {
      await LogService.instance.logError(e, st, context: 'DB init');
      rethrow;
    }

    // Читаем настройки для автоочистки
    Future.microtask(() async {
      try {
        const storage = FlutterSecureStorage();
        final rawDays = await storage.read(key: AppSettingsKeys.trashAutoCleanupDays);
        final days = int.tryParse(rawDays ?? '') ?? TrashCleanupService.defaultDaysOld;

        if (days > 0) {
          final result = await TrashCleanupService.purgeOldTrash(
            db,
            daysOld: days,
            onDeleted: ThumbnailCache.evict,
          );
          if (result.removedCount > 0) {
            LogService.instance.log('Auto-purged ${result.removedCount} items from trash (older than $days days)');
          }
        }
      } catch (e, st) {
        LogService.instance.logError(e, st, context: 'Auto trash cleanup failed');
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
