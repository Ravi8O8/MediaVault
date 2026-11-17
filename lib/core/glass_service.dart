import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'app_settings_keys.dart';

/// Глобальный флаг «стеклянные эффекты».
/// Читают все виджеты, где может быть блюр (AppBar, поиск, меню снизу).
class GlassService extends ChangeNotifier {
  GlassService._();
  static final GlassService instance = GlassService._();

  static const _storage = FlutterSecureStorage();

  bool _enabled = false;
  bool get enabled => _enabled;

  Future<void> load() async {
    try {
      final raw = await _storage.read(key: AppSettingsKeys.useGlassEffects);
      _enabled = raw == 'true';
    } catch (_) {}
    notifyListeners();
  }

  Future<void> setEnabled(bool value) async {
    if (_enabled == value) return;
    _enabled = value;
    notifyListeners();
    try {
      await _storage.write(
        key: AppSettingsKeys.useGlassEffects,
        value: value ? 'true' : 'false',
      );
    } catch (_) {}
  }
}
