import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shellvibe/features/billing/data/entitlement_cache.dart';
import 'package:shellvibe/features/billing/domain/entitlement.dart';
import 'package:shellvibe/shared/storage/secure_storage_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late EntitlementCache cache;

  const userId = '01USERULID0000000000000000';
  const otherUserId = '01OTHERUSER000000000000000';

  final pro = Entitlement.fromJson(const {
    'plan': 'pro',
    'status': 'active',
    'capabilities': ['local_device_link', 'cloud_backup'],
    'limits': {'max_backup_size_bytes': 5242880, 'max_backup_revisions': 10},
  });

  setUp(() {
    FlutterSecureStorage.setMockInitialValues({});
    cache = EntitlementCache(storage: SecureStorageService());
  });

  test('reads nothing when empty', () async {
    expect(await cache.read(forUserId: userId), isNull);
  });

  test('round-trips a snapshot', () async {
    await cache.write(entitlement: pro, userId: userId);

    final cached = await cache.read(forUserId: userId);

    expect(cached, isNotNull);
    expect(cached!.entitlement, pro);
    expect(cached.userId, userId);
    expect(cached.entitlement.hasCloudBackup, isTrue);
  });

  test('refuses a snapshot belonging to another account', () async {
    await cache.write(entitlement: pro, userId: userId);

    expect(
      await cache.read(forUserId: otherUserId),
      isNull,
      reason:
          "One account's subscription must not unlock another account's "
          'session on the same device.',
    );
  });

  test('a snapshot inside the window is fresh', () async {
    final now = DateTime.now().toUtc();
    await cache.write(entitlement: pro, userId: userId, now: now);

    final cached = await cache.read(forUserId: userId);

    expect(
      cached!.isFresh(now: now, maxAge: EntitlementCache.maxAge),
      isTrue,
    );
  });

  test('a snapshot past the window is stale', () async {
    final written = DateTime.now().toUtc().subtract(const Duration(days: 4));
    await cache.write(entitlement: pro, userId: userId, now: written);

    final cached = await cache.read(forUserId: userId);

    expect(
      cached!.isFresh(
        now: DateTime.now().toUtc(),
        maxAge: EntitlementCache.maxAge,
      ),
      isFalse,
      reason: 'A stale snapshot is not a licence.',
    );
  });

  test('a snapshot dated in the future is never fresh', () async {
    // Moving the device clock backwards would otherwise stretch a lapsed
    // subscription indefinitely.
    final future = DateTime.now().toUtc().add(const Duration(days: 30));
    await cache.write(entitlement: pro, userId: userId, now: future);

    final cached = await cache.read(forUserId: userId);

    expect(
      cached!.isFresh(
        now: DateTime.now().toUtc(),
        maxAge: EntitlementCache.maxAge,
      ),
      isFalse,
    );
  });

  test('corrupt JSON reads as no cache rather than throwing', () async {
    FlutterSecureStorage.setMockInitialValues({
      'shellvibe_entitlement_snapshot': '{not json',
    });
    cache = EntitlementCache(storage: SecureStorageService());

    expect(await cache.read(forUserId: userId), isNull);
  });

  test('a payload without a timestamp reads as no cache', () async {
    FlutterSecureStorage.setMockInitialValues({
      'shellvibe_entitlement_snapshot':
          '{"user_id":"$userId","entitlement":{"plan":"pro"}}',
    });
    cache = EntitlementCache(storage: SecureStorageService());

    expect(await cache.read(forUserId: userId), isNull);
  });

  test('a payload without an entitlement member reads as no cache', () async {
    FlutterSecureStorage.setMockInitialValues({
      'shellvibe_entitlement_snapshot':
          '{"user_id":"$userId","fetched_at":"2026-09-17T00:00:00.000Z"}',
    });
    cache = EntitlementCache(storage: SecureStorageService());

    expect(await cache.read(forUserId: userId), isNull);
  });

  test('clear removes the snapshot', () async {
    await cache.write(entitlement: pro, userId: userId);
    await cache.clear();

    expect(await cache.read(forUserId: userId), isNull);
  });
}
