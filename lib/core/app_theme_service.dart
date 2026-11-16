import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class AppThemeService extends ChangeNotifier {
  AppThemeService._();
  static final AppThemeService instance = AppThemeService._();

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

  // ─── НОВЫЕ ПАЛИТРЫ ───
  static const Map<String, Color> _primaryColors = {
    'midnight': Color(0xFF00E5FF), // Яркий циан
    'purple': Color(0xFFD500F9),   // Глубокий пурпур
    'ocean': Color(0xFF2979FF),    // Насыщенный синий
    'sunset': Color(0xFFFF6D00),   // Огненный оранжевый
  };

  // Тёмные градиенты (более глубокие, премиальные)
  static const Map<String, List<Color>> _bgGradients = {
    'midnight': [Color(0xFF0F171E), Color(0xFF162A35)],
    'purple': [Color(0xFF140C1F), Color(0xFF2D1B36)],
    'ocean': [Color(0xFF09111F), Color(0xFF1B2A41)],
    'sunset': [Color(0xFF1C100B), Color(0xFF3A1C1A)],
  };

  // Светлые градиенты (мягкие пастельные)
  static const Map<String, List<Color>> _lightBgGradients = {
    'midnight': [Color(0xFFE0F7FA), Color(0xFFB2EBF2)],
    'purple': [Color(0xFFF3E5F5), Color(0xFFE1BEE7)],
    'ocean': [Color(0xFFE3F2FD), Color(0xFF90CAF9)],
    'sunset': [Color(0xFFFFF8E1), Color(0xFFFFCC80)],
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
      ? Colors.white.withValues(alpha: 0.12)
      : Colors.black.withValues(alpha: 0.08);

  Color glassCardTop(Brightness b) => b == Brightness.dark
      ? Colors.white.withValues(alpha: 0.12)
      : Colors.white.withValues(alpha: 0.60);

  Color glassCardBottom(Brightness b) => b == Brightness.dark
      ? Colors.white.withValues(alpha: 0.02)
      : Colors.white.withValues(alpha: 0.20);

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

    final surface = isDark ? const Color(0xFF121212) : Colors.white;
    final onSurface = isDark ? Colors.white : const Color(0xFF1A1A1A);
    final onSurfaceVariant = isDark ? Colors.white70 : Colors.black54;

    return ThemeData(
      brightness: brightness,
      useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(
        seedColor: primary,
        brightness: brightness,
        surface: surface,
        onSurface: onSurface,
        primary: primary,
      ),
      scaffoldBackgroundColor: Colors.transparent,
      appBarTheme: AppBarTheme(
        backgroundColor: Colors.transparent,
        elevation: 0,
        centerTitle: false,
        titleTextStyle: TextStyle(
          color: onSurface,
          fontSize: 22,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.5,
        ),
        iconTheme: IconThemeData(color: onSurface),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: isDark ? const Color(0xFF1E1E1E) : Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
        titleTextStyle: TextStyle(
          color: onSurface,
          fontSize: 20,
          fontWeight: FontWeight.w700,
        ),
        contentTextStyle: TextStyle(color: onSurfaceVariant, fontSize: 15, height: 1.4),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: isDark ? const Color(0xFF1E1E1E) : Colors.white,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: isDark ? const Color(0xFF323232) : Colors.black87,
        contentTextStyle: const TextStyle(color: Colors.white, fontWeight: FontWeight.w500),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
      textTheme: TextTheme(
        bodyLarge: TextStyle(color: onSurface, height: 1.4),
        bodyMedium: TextStyle(color: onSurface, height: 1.4),
        bodySmall: TextStyle(color: onSurfaceVariant),
        titleLarge: TextStyle(color: onSurface, fontWeight: FontWeight.bold),
        titleMedium: TextStyle(color: onSurface, fontWeight: FontWeight.w600),
      ),
      iconTheme: IconThemeData(color: onSurfaceVariant),
      dividerColor: isDark ? Colors.white12 : Colors.black12,
    );
  }
}
