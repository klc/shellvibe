import '../../../shared/storage/secure_storage_service.dart';
import '../domain/account_session.dart';

/// Durable home of the account session.
///
/// The bearer token never leaves this class except through [readToken], which
/// the API client calls per request. Nothing else in the app holds it.
final class AccountSessionStore {
  final SecureStorageService storage;

  const AccountSessionStore({required this.storage});

  /// The bearer token, or null when signed out.
  Future<String?> readToken() async {
    final token = await storage.read(key: SecureStorageKeys.accountToken);

    return (token == null || token.isEmpty) ? null : token;
  }

  /// The device ULID this install is known by, or null if it has never
  /// registered.
  ///
  /// Survives sign-out on purpose: signing back in should reuse the same
  /// device record rather than open a second one for the same machine.
  Future<String?> readDeviceId() async {
    final id = await storage.read(key: SecureStorageKeys.accountDeviceId);

    return (id == null || id.isEmpty) ? null : id;
  }

  /// The last email that signed in here, for prefilling the form.
  Future<String?> readEmail() =>
      storage.read(key: SecureStorageKeys.accountEmail);

  /// Reads the stored session, or null when any required part is missing.
  Future<AccountSession?> read() async {
    final token = await readToken();
    if (token == null) return null;

    final userId = await storage.read(key: SecureStorageKeys.accountUserId);
    final deviceId = await readDeviceId();

    if (userId == null || userId.isEmpty || deviceId == null) return null;

    return AccountSession(
      userId: userId,
      deviceId: deviceId,
      email: await readEmail() ?? '',
      name: '',
    );
  }

  /// Persists a freshly authenticated session.
  Future<void> write({
    required String token,
    required AccountSession session,
  }) async {
    await storage.write(key: SecureStorageKeys.accountToken, value: token);
    await storage.write(
      key: SecureStorageKeys.accountUserId,
      value: session.userId,
    );
    await storage.write(
      key: SecureStorageKeys.accountDeviceId,
      value: session.deviceId,
    );
    await storage.write(
      key: SecureStorageKeys.accountEmail,
      value: session.email,
    );
  }

  /// Drops the token and user identity, keeping the device id.
  ///
  /// Called both on an explicit sign-out and when the server answers `401`.
  /// The device id stays so the next sign-in reuses this device record.
  Future<void> clearSession() async {
    await storage.delete(key: SecureStorageKeys.accountToken);
    await storage.delete(key: SecureStorageKeys.accountUserId);
  }

  /// Forgets everything, including the device identity.
  ///
  /// For "forget this device" and for account deletion, where keeping the id
  /// of a record the server no longer has would make the next sign-in send a
  /// `device_id` that resolves to nothing.
  Future<void> clearAll() async {
    await clearSession();
    await storage.delete(key: SecureStorageKeys.accountDeviceId);
    await storage.delete(key: SecureStorageKeys.accountEmail);
  }
}
