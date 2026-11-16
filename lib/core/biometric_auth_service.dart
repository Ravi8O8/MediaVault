import 'package:flutter/services.dart';
import 'package:local_auth/local_auth.dart';

enum BiometricAvailability { available, notEnrolled, notSupported, unknown }

class BiometricAuthService {
  static final LocalAuthentication _auth = LocalAuthentication();

  static Future<BiometricAvailability> checkAvailability() async {
    try {
      final supported = await _auth.isDeviceSupported();
      if (!supported) return BiometricAvailability.notSupported;
      final canCheck = await _auth.canCheckBiometrics;
      if (!canCheck) return BiometricAvailability.notSupported;
      final enrolled = await _auth.getAvailableBiometrics();
      if (enrolled.isEmpty) return BiometricAvailability.notEnrolled;
      return BiometricAvailability.available;
    } catch (_) {
      return BiometricAvailability.unknown;
    }
  }

  static Future<bool> authenticate() async {
    try {
      return await _auth.authenticate(
        localizedReason: 'Приложите палец или используйте PIN для входа',
        biometricOnly: false, // ← разрешаем PIN/паттерн как fallback
        persistAcrossBackgrounding: true,
      );
    } on LocalAuthException {
      return false;
    } on PlatformException {
      return false;
    }
  }
}
