import 'package:flutter/material.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';

import 'core/database_service.dart';
import 'core/thumbnail_cache.dart';
import 'core/trash_cleanup_service.dart';
import 'features/lock/lock_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await LiquidGlassWidgets.initialize();

  final db = DatabaseService();
  await db.init();

  // Фоновая автоочистка корзины (30+ дней). Не блокирует запуск.
  Future.microtask(() async {
    try {
      final result = await TrashCleanupService.purgeOldTrash(
        db,
        onDeleted: ThumbnailCache.evict,
      );
      if (result.removedCount > 0) {
        debugPrint(
          'Auto-purged ${result.removedCount} items from trash '
          '(${result.removedBytes} bytes)',
        );
      }
    } catch (e) {
      debugPrint('Auto trash cleanup failed: $e');
    }
  });

  runApp(
    LiquidGlassWidgets.wrap(
      brightnessResolver: Theme.maybeBrightnessOf,
      child: MediaVaultApp(db: db),
    ),
  );
}

class MediaVaultApp extends StatelessWidget {
  final DatabaseService db;
  const MediaVaultApp({super.key, required this.db});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'MediaVault',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        colorSchemeSeed: Colors.teal,
        useMaterial3: true,
      ),
      home: LockScreen(db: db),
    );
  }
}
