import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class AppThemeService extends ChangeNotifier {
  AppThemeService._();
  static final AppThemeService instance = AppThemeService._();

  static const _storage = FlutterSecureStorage();
  static const _kMode = 'theme_mode';
  static const _kPreset = 'theme_preset';
  static const _kGridCols = 'grid_columns';

  ThemeMode _mode = ThemeMode.dark;
  String _presetKey = 'midnight';
  int _gridColumns = 3;
  bool _loaded = false;

  ThemeMode get mode => _mode;
  String get presetKey => _presetKey;
  int get gridColumns => _gridColumns;
  bool get loaded => _loaded;

  static const Map<String, String> presetNames = {
    'midnight': 'Midnight Teal',
    'ocean': 'Ocean Blue',
    'purple': 'Cyber Purple',
    'rose': 'Rose Quartz',
    'sunset': 'Sunset Amber',
    'peach': 'Warm Peach',
    'mint': 'Fresh Mint',
    'forest': 'Forest Green',
    'lavender': 'Soft Lavender',
    'graphite': 'Graphite',
  };

  static const Map<ThemeMode, String> modeOptions = {
    ThemeMode.system: 'Системная',
    ThemeMode.light: 'Светлая',
    ThemeMode.dark: 'Тёмная',
  };

  static const Map<String, Color> _primaryColors = {
    'midnight': Color(0xFF00E5FF),
    'ocean': Color(0xFF448AFF),
    'purple': Color(0xFFD500F9),
    'rose': Color(0xFFFF4D94),
    'sunset': Color(0xFFFF6D00),
    'peach': Color(0xFFFF8A65),
    'mint': Color(0xFF00D9A3),
    'forest': Color(0xFF34C759),
    'lavender': Color(0xFFB794F6),
    'graphite': Color(0xFF90A4AE),
  };

  static const Map<String, List<Color>> _bgGradients = {
    'midnight': [Color(0xFF0F171E), Color(0xFF162A35)],
    'ocean': [Color(0xFF09111F), Color(0xFF1B2A41)],
    'purple': [Color(0xFF140C1F), Color(0xFF2D1B36)],
    'rose': [Color(0xFF1F0A14), Color(0xFF2D0F1E)],
    'sunset': [Color(0xFF1C100B), Color(0xFF3A1C1A)],
    'peach': [Color(0xFF1F140C), Color(0xFF2D1C12)],
    'mint': [Color(0xFF0A1F1B), Color(0xFF0F302A)],
    'forest': [Color(0xFF0B1F0F), Color(0xFF12321C)],
    'lavender': [Color(0xFF1A1428), Color(0xFF28203F)],
    'graphite': [Color(0xFF141618), Color(0xFF1E2226)],
  };

  static const Map<String, List<Color>> _lightBgGradients = {
    'midnight': [Color(0xFFE0F7FA), Color(0xFFB2EBF2)],
    'ocean': [Color(0xFFE3F2FD), Color(0xFF90CAF9)],
    'purple': [Color(0xFFF3E5F5), Color(0xFFE1BEE7)],
    'rose': [Color(0xFFFFE4EC), Color(0xFFFFCAD8)],
    'sunset': [Color(0xFFFFF8E1), Color(0xFFFFCC80)],
    'peach': [Color(0xFFFFF0E6), Color(0xFFFFD9BE)],
    'mint': [Color(0xFFDFF7F0), Color(0xFFC0EDE0)],
    'forest': [Color(0xFFE0F7E8), Color(0xFFC2ECD2)],
    'lavender': [Color(0xFFF0EAF8), Color(0xFFE0D5F0)],
    'graphite': [Color(0xFFECEFF1), Color(0xFFCFD8DC)],
  };

  Color get primaryColor =>
      _primaryColors[_presetKey] ?? _primaryColors['midnight']!;

  List<Color> gradientFor(Brightness brightness) {
    if (brightness == Brightness.light) {
      return _lightBgGradients[_presetKey] ?? _lightBgGradients['midnight']!;
    }
    return _bgGradients[_presetKey] ?? _bgGradients['midnight']!;
  }

  /// Пара цветов для превью в настройках (тёмный/светлый угол).
  List<Color> previewGradientFor(String key) {
    return _bgGradients[key] ?? _bgGradients['midnight']!;
  }

  Color previewColorFor(String key) {
    return _primaryColors[key] ?? _primaryColors['midnight']!;
  }

  Color glassCardColor(Brightness b) => b == Brightness.dark
      ? Colors.white.withValues(alpha: 0.06)
      : Colors.black.withValues(alpha: 0.04);

  Color glassBorderColor(Brightness b) => b == Brightness.dark
      ? Colors.white.withValues(alpha: 0.12)
      : Colors.black.withValues(alpha: 0.08);

  Color glassCardTop(Brightness b) => b == Brightness.dark
      ? Colors.white.withValues(alpha: 0.10)
      : Colors.white.withValues(alpha: 0.60);

  Color glassCardBottom(Brightness b) => b == Brightness.dark
      ? Colors.white.withValues(alpha: 0.02)
      : Colors.white.withValues(alpha: 0.20);

  Future<void> load() async {
    try {
      final m = await _storage.read(key: _kMode);
      final s = await _storage.read(key: _kPreset);
      final g = await _storage.read(key: _kGridCols);

      _mode = switch (m) {
        'light' => ThemeMode.light,
        'dark' => ThemeMode.dark,
        'system' => ThemeMode.system,
        _ => ThemeMode.dark,
      };
      _presetKey = (s != null && presetNames.containsKey(s)) ? s : 'midnight';
      _gridColumns = int.tryParse(g ?? '') ?? 3;
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

  Future<void> setGridColumns(int cols) async {
    if (_gridColumns == cols) return;
    _gridColumns = cols;
    try {
      await _storage.write(key: _kGridCols, value: cols.toString());
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
        ),
        iconTheme: IconThemeData(color: onSurface),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: isDark ? const Color(0xFF1E1E1E) : Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
        titleTextStyle: TextStyle(
            color: onSurface, fontSize: 20, fontWeight: FontWeight.w700),
        contentTextStyle:
            TextStyle(color: onSurfaceVariant, fontSize: 15, height: 1.4),
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
        contentTextStyle: const TextStyle(
            color: Colors.white, fontWeight: FontWeight.w500),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
      textTheme: TextTheme(
        bodyLarge: TextStyle(color: onSurface, height: 1.4),
        bodyMedium: TextStyle(color: onSurface, height: 1.4),
        bodySmall: TextStyle(color: onSurfaceVariant),
        titleLarge: TextStyle(color: onSurface, fontWeight: FontWeight.bold),
        titleMedium:
            TextStyle(color: onSurface, fontWeight: FontWeight.w600),
      ),
      iconTheme: IconThemeData(color: onSurfaceVariant),
      dividerColor: isDark ? Colors.white12 : Colors.black12,
    );
  }
}
