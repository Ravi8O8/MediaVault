import 'package:flutter/services.dart';
import 'package:local_auth/local_auth.dart';

class BiometricAuthService {
  static final LocalAuthentication _auth = LocalAuthentication();

  static Future<bool> authenticate() async {
    try {
      final canCheck = await _auth.canCheckBiometrics;
      final isSupported = await _auth.isDeviceSupported();
      if (!canCheck || !isSupported) return false;

      return await _auth.authenticate(
        localizedReason: 'Приложите палец для входа в MediaVault',
        biometricOnly: true,
        persistAcrossBackgrounding: true,
      );
    } on LocalAuthException catch (e) {
      // В local_auth 3.x ошибки приходят как LocalAuthException
      // с типизированным кодом LocalAuthExceptionCode.
      // Для простоты возвращаем false, но можно обрабатывать разные коды отдельно.
      // Например: e.code == LocalAuthExceptionCode.userCanceled
      return false;
    } on PlatformException {
      // На всякий случай оставляем обработку PlatformException
      // для непредвиденных платформенных ошибок.
      return false;
    }
  }
}
