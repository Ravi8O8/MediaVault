import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class AppThemeService extends ChangeNotifier {
  AppThemeService._();
  static final AppThemeService instance = AppThemeService._();

  // ИСПРАВЛЕНО: убран устаревший aOptions
  static const _storage = FlutterSecureStorage();
  static const _kMode = 'theme_mode';
  static const _kPreset = 'theme_preset';

  ThemeMode _mode = ThemeMode.dark;
  String _presetKey = 'midnight';
  bool _loaded = false;

  ThemeMode get mode => _mode;
  String get presetKey => _presetKey;
  bool get loaded => _loaded;

  static const Map<String, String> presetNames = {
    'midnight': 'Midnight Teal',
    'purple': 'Cyber Purple',
    'ocean': 'Ocean Blue',
    'sunset': 'Sunset Amber',
  };

  static const Map<ThemeMode, String> modeOptions = {
    ThemeMode.system: 'Системная',
    ThemeMode.light: 'Светлая',
    ThemeMode.dark: 'Тёмная',
  };

  static const Map<String, Color> _primaryColors = {
    'midnight': Color(0xFF00BFA5),
    'purple': Color(0xFFB388FF),
    'ocean': Color(0xFF448AFF),
    'sunset': Color(0xFFFF8A65),
  };

  static const Map<String, List<Color>> _bgGradients = {
    'midnight': [Color(0xFF121212), Color(0xFF1F2325)],
    'purple': [Color(0xFF120A1F), Color(0xFF2A1B38)],
    'ocean': [Color(0xFF0A1225), Color(0xFF1B2B4C)],
    'sunset': [Color(0xFF1A0F0A), Color(0xFF3B1C1A)],
  };

  static const Map<String, List<Color>> _lightBgGradients = {
    'midnight': [Color(0xFFE0F2F1), Color(0xFFB2DFDB)],
    'purple': [Color(0xFFF3E5F5), Color(0xFFE1BEE7)],
    'ocean': [Color(0xFFE3F2FD), Color(0xFFBBDEFB)],
    'sunset': [Color(0xFFFFF3E0), Color(0xFFFFE0B2)],
  };

  Color get primaryColor =>
      _primaryColors[_presetKey] ?? _primaryColors['midnight']!;

  List<Color> get backgroundGradient =>
      _bgGradients[_presetKey] ?? _bgGradients['midnight']!;

  List<Color> gradientFor(Brightness brightness) {
    if (brightness == Brightness.light) {
      return _lightBgGradients[_presetKey] ?? _lightBgGradients['midnight']!;
    }
    return _bgGradients[_presetKey] ?? _bgGradients['midnight']!;
  }

  Color glassCardColor(Brightness b) => b == Brightness.dark
      ? Colors.white.withValues(alpha: 0.06)
      : Colors.black.withValues(alpha: 0.04);

  Color glassBorderColor(Brightness b) => b == Brightness.dark
      ? Colors.white.withValues(alpha: 0.10)
      : Colors.black.withValues(alpha: 0.10);

  Color glassCardTop(Brightness b) => b == Brightness.dark
      ? Colors.white.withValues(alpha: 0.10)
      : Colors.black.withValues(alpha: 0.05);

  Color glassCardBottom(Brightness b) => b == Brightness.dark
      ? Colors.white.withValues(alpha: 0.03)
      : Colors.black.withValues(alpha: 0.01);

  Future<void> load() async {
    try {
      final m = await _storage.read(key: _kMode);
      final s = await _storage.read(key: _kPreset);
      _mode = switch (m) {
        'light' => ThemeMode.light,
        'dark' => ThemeMode.dark,
        'system' => ThemeMode.system,
        _ => ThemeMode.dark,
      };
      _presetKey = (s != null && presetNames.containsKey(s)) ? s : 'midnight';
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

  Future<void> setPreset(String key) async {
    if (_presetKey == key) return;
    _presetKey = key;
    try {
      await _storage.write(key: _kPreset, value: key);
    } catch (_) {}
    notifyListeners();
  }

  ThemeData buildTheme(Brightness brightness) {
    final isDark = brightness == Brightness.dark;
    final primary = primaryColor;

    final surface = isDark ? const Color(0xFF1A1A1A) : Colors.white;
    final onSurface = isDark ? Colors.white : Colors.black87;
    final onSurfaceVariant = isDark ? Colors.white70 : Colors.black54;

    return ThemeData(
      brightness: brightness,
      useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(
        seedColor: primary,
        brightness: brightness,
        surface: surface,
        onSurface: onSurface,
      ),
      scaffoldBackgroundColor: Colors.transparent,
      appBarTheme: AppBarTheme(
        backgroundColor: Colors.transparent,
        elevation: 0,
        centerTitle: false,
        titleTextStyle: TextStyle(
          color: onSurface,
          fontSize: 20,
          fontWeight: FontWeight.w600,
        ),
        iconTheme: IconThemeData(color: onSurface),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: isDark ? const Color(0xFF232526) : Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        titleTextStyle: TextStyle(
          color: onSurface,
          fontSize: 18,
          fontWeight: FontWeight.w600,
        ),
        contentTextStyle: TextStyle(color: onSurfaceVariant, fontSize: 14),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: isDark ? const Color(0xFF232526) : Colors.white,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: isDark ? const Color(0xFF323232) : Colors.black87,
        contentTextStyle: const TextStyle(color: Colors.white),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
      textTheme: TextTheme(
        bodyLarge: TextStyle(color: onSurface),
        bodyMedium: TextStyle(color: onSurface),
        bodySmall: TextStyle(color: onSurfaceVariant),
        titleLarge: TextStyle(color: onSurface, fontWeight: FontWeight.bold),
        titleMedium: TextStyle(color: onSurface, fontWeight: FontWeight.w600),
      ),
      iconTheme: IconThemeData(color: onSurfaceVariant),
      dividerColor: isDark ? Colors.white12 : Colors.black12,
    );
  }
}
