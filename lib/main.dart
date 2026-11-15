import 'package:flutter/material.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';
import 'core/biometric_auth_service.dart';
import 'core/database_service.dart';
import 'features/lock/lock_screen.dart';
import 'features/vault/vault_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Прогрев шейдеров Liquid Glass (не блокирует запуск)
  await LiquidGlassWidgets.initialize();

  // Инициализация зашифрованной БД
  final db = DatabaseService();
  await db.init();

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
