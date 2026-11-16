import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class AppThemeService extends ChangeNotifier {
  AppThemeService._();
  static final AppThemeService instance = AppThemeService._();

  static const _storage = FlutterSecureStorage();
  static const _kMode = 'theme_mode'; // 'system' | 'light' | 'dark'
  static const _kSeed = 'theme_seed'; // 'teal' | 'purple' | 'blue' | ...

  ThemeMode _mode = ThemeMode.dark;
  Color _seed = Colors.teal;
  bool _loaded = false;

  ThemeMode get mode => _mode;
  Color get seed => _seed;
  bool get loaded => _loaded;

  static const Map<String, Color> seedOptions = {
    'teal': Colors.teal,
    'purple': Colors.purple,
    'blue': Colors.blue,
    'green': Colors.green,
    'amber': Colors.amber,
    'pink': Colors.pinkAccent,
  };

  static const Map<ThemeMode, String> modeOptions = {
    ThemeMode.system: 'Системная',
    ThemeMode.light: 'Светлая',
    ThemeMode.dark: 'Тёмная',
  };

  String get seedKey {
    for (final e in seedOptions.entries) {
      if (e.value.toARGB32() == _seed.toARGB32()) return e.key;
    }
    return 'teal';
  }

  Future<void> load() async {
    try {
      final m = await _storage.read(key: _kMode);
      final s = await _storage.read(key: _kSeed);
      _mode = switch (m) {
        'light' => ThemeMode.light,
        'dark' => ThemeMode.dark,
        'system' => ThemeMode.system,
        _ => ThemeMode.dark,
      };
      _seed = seedOptions[s] ?? Colors.teal;
    } catch (_) {}
    _loaded = true;
    notifyListeners();
  }

  Future<void> setMode(ThemeMode m) async {
    if (_mode == m) return;
    _mode = m;
    try {
      await _storage.write(
        key: _kMode,
        value: switch (m) {
          ThemeMode.light => 'light',
          ThemeMode.dark => 'dark',
          ThemeMode.system => 'system',
        },
      );
    } catch (_) {}
    notifyListeners();
  }

  Future<void> setSeed(String key) async {
    final c = seedOptions[key];
    if (c == null || c.toARGB32() == _seed.toARGB32()) return;
    _seed = c;
    try {
      await _storage.write(key: _kSeed, value: key);
    } catch (_) {}
    notifyListeners();
  }

  ThemeData buildTheme(Brightness brightness) {
    return ThemeData(
      brightness: brightness,
      colorSchemeSeed: _seed,
      useMaterial3: true,
    );
  }
}
