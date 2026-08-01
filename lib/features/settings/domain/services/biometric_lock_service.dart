import 'package:local_auth/local_auth.dart';

/// Service providing hardware biometric authentication (FaceID, TouchID, Fingerprint, Windows Hello).
class BiometricLockService {
  final LocalAuthentication _auth;

  BiometricLockService({LocalAuthentication? auth})
      : _auth = auth ?? LocalAuthentication();

  /// Returns true if hardware biometric authentication is available on the device.
  Future<bool> canCheckBiometrics() async {
    try {
      final canAuthenticateWithBiometrics = await _auth.canCheckBiometrics;
      final isDeviceSupported = await _auth.isDeviceSupported();
      return canAuthenticateWithBiometrics || isDeviceSupported;
    } catch (_) {
      return false;
    }
  }

  /// Retrieves list of available biometric types on the device.
  Future<List<BiometricType>> getAvailableBiometrics() async {
    try {
      return await _auth.getAvailableBiometrics();
    } catch (_) {
      return [];
    }
  }

  /// Prompts the user for biometric authentication.
  Future<bool> authenticate({
    String localizedReason = 'Authenticate to access Terly2',
  }) async {
    try {
      return await _auth.authenticate(
        localizedReason: localizedReason,
        biometricOnly: false,
        persistAcrossBackgrounding: true,
      );
    } catch (_) {
      return false;
    }
  }
}
