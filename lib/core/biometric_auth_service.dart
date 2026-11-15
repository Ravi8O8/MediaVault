import 'package:flutter/services.dart';
import 'package:local_auth/local_auth.dart';
import 'package:local_auth/error_codes.dart' as auth_error; // Для обработки ошибок

class BiometricAuthService {
  static final LocalAuthentication _auth = LocalAuthentication();

  static Future<bool> authenticate() async {
    try {
      final canCheck = await _auth.canCheckBiometrics;
      final isSupported = await _auth.isDeviceSupported();
      if (!canCheck || !isSupported) return false;

      // Используем новый API local_auth 3.x:
      // biometricOnly и persistAcrossBackgrounding теперь прямые параметры
      return await _auth.authenticate(
        localizedReason: 'Приложите палец для входа в MediaVault',
        biometricOnly: true,
        persistAcrossBackgrounding: true,
      );
    } on PlatformException catch (e) {
      // В 3.x большинство ошибок приходят как PlatformException с кодами
      if (e.code == auth_error.notAvailable ||
          e.code == auth_error.notEnrolled ||
          e.code == auth_error.lockedOut ||
          e.code == auth_error.permanentlyLockedOut) {
        return false;
      }
      return false;
    }
  }
}
