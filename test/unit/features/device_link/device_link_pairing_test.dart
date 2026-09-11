import 'dart:async';

import 'package:cryptography/cryptography.dart';
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:shellvibe/core/crypto/encryption_engine.dart';
import 'package:shellvibe/core/network/device_link/device_link_client.dart';
import 'package:shellvibe/core/network/device_link/device_link_identity.dart';
import 'package:shellvibe/core/network/device_link/device_link_protocol.dart';
import 'package:shellvibe/core/network/device_link/device_link_server.dart';
import 'package:shellvibe/features/device_link/data/repositories/device_link_pairing_repository.dart';
import 'package:shellvibe/features/device_link/data/repositories/device_link_pairing_storage.dart';
import 'package:shellvibe/features/device_link/data/services/device_link_auto_reconnect_service.dart';
import 'package:shellvibe/features/device_link/domain/models/device_link_pairing_profile.dart';
import 'package:shellvibe/features/vault/presentation/notifiers/vault_notifier.dart';
import 'package:shellvibe/shared/database/app_database.dart';
import 'package:shellvibe/shared/providers/database_providers.dart';
import 'package:shellvibe/shared/storage/secure_storage_service.dart';

void main() {
  test('Argon2id pairing records authorize and can be revoked', () async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    final repository = DeviceLinkPairingRepository(
      dao: db.pairedDevicesDao,
      encryption: EncryptionEngine(
        kdf: Argon2id(
          parallelism: 1,
          memory: 1024,
          iterations: 1,
          hashLength: 32,
        ),
      ),
      isVaultLocked: () => false,
      runWhileVaultUnlocked: _runWithoutVaultPermit,
    );

    await repository.savePairedDevice(
      id: 'phone-1',
      name: 'iPhone 15',
      platform: 'ios',
      secret: 'pairing-secret',
      publicKey: 'ephemeral-public-key',
    );

    final row = await db.pairedDevicesDao.findById('phone-1');
    expect(row, isNotNull);
    expect(row!.secretHash, isNot(contains('pairing-secret')));
    expect(await repository.authenticate('phone-1', 'pairing-secret'), isTrue);
    expect(await repository.authenticate('phone-1', 'wrong-secret'), isFalse);

    await repository.remove('phone-1');
    expect(await repository.authenticate('phone-1', 'pairing-secret'), isFalse);
  });

  test(
    'pairing authentication is rejected while the vault is locked',
    () async {
      final db = AppDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      var vaultLocked = false;
      final repository = DeviceLinkPairingRepository(
        dao: db.pairedDevicesDao,
        encryption: EncryptionEngine(
          kdf: Argon2id(
            parallelism: 1,
            memory: 1024,
            iterations: 1,
            hashLength: 32,
          ),
        ),
        isVaultLocked: () => vaultLocked,
        runWhileVaultUnlocked: _runWithoutVaultPermit,
      );

      await repository.savePairedDevice(
        id: 'locked-phone',
        name: 'Locked phone',
        platform: 'ios',
        secret: 'pairing-secret',
        publicKey: 'ephemeral-public-key',
      );

      vaultLocked = true;
      expect(
        await repository.authenticate('locked-phone', 'pairing-secret'),
        isFalse,
      );

      vaultLocked = false;
      expect(
        await repository.authenticate('locked-phone', 'pairing-secret'),
        isTrue,
      );
    },
  );

  test(
    'pairing authentication rechecks the vault after Argon2 verification',
    () async {
      final db = AppDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      var vaultChecks = 0;
      var authenticating = false;
      final repository = DeviceLinkPairingRepository(
        dao: db.pairedDevicesDao,
        encryption: _testEncryption(),
        // The first read admits the verification. The second one models a
        // lock request landing while Argon2id work is in progress.
        isVaultLocked: () => authenticating && ++vaultChecks >= 2,
        runWhileVaultUnlocked: _runWithoutVaultPermit,
      );
      await _savePairing(repository, id: 'argon2-race-phone');
      authenticating = true;
      vaultChecks = 0;

      expect(
        await repository.authenticate('argon2-race-phone', 'pairing-secret'),
        isFalse,
      );
    },
  );

  test(
    'provider rejects pairing authentication while the vault is loading',
    () async {
      final db = AppDatabase(NativeDatabase.memory());
      final container = _containerWithVault(db, _LoadingVaultNotifier.new);
      addTearDown(() async {
        container.dispose();
        await db.close();
      });
      final repository = container.read(deviceLinkPairingRepositoryProvider);
      await _seedPairing(db, id: 'loading-phone');

      expect(
        await repository.authenticate('loading-phone', 'pairing-secret'),
        isFalse,
      );
    },
  );

  test(
    'provider rejects pairing authentication when the vault has no value',
    () async {
      final db = AppDatabase(NativeDatabase.memory());
      final container = _containerWithVault(db, _FailedVaultNotifier.new);
      addTearDown(() async {
        container.dispose();
        await db.close();
      });
      await expectLater(
        container.read(vaultProvider.future),
        throwsA(isA<StateError>()),
      );
      final repository = container.read(deviceLinkPairingRepositoryProvider);
      await _seedPairing(db, id: 'unavailable-phone');

      expect(
        await repository.authenticate('unavailable-phone', 'pairing-secret'),
        isFalse,
      );
    },
  );

  test(
    'provider rejects pairing authentication while loading stale vault data',
    () async {
      final db = AppDatabase(NativeDatabase.memory());
      final container = _containerWithVault(db, _StaleLoadingVaultNotifier.new);
      addTearDown(() async {
        container.dispose();
        await db.close();
      });
      await container.read(vaultProvider.future);
      container.invalidate(vaultProvider);
      await Future<void>.delayed(Duration.zero);
      final vault = container.read(vaultProvider);
      expect(vault.isLoading, isTrue);
      expect(vault.hasValue, isTrue);

      final repository = container.read(deviceLinkPairingRepositoryProvider);
      await _seedPairing(db, id: 'stale-loading-phone');

      expect(
        await repository.authenticate('stale-loading-phone', 'pairing-secret'),
        isFalse,
      );
    },
  );

  test(
    'provider allows pairing authentication when the vault is unlocked',
    () async {
      final db = AppDatabase(NativeDatabase.memory());
      final container = _containerWithVault(db, _UnlockedVaultNotifier.new);
      addTearDown(() async {
        container.dispose();
        await db.close();
      });
      await container.read(vaultProvider.future);
      final repository = container.read(deviceLinkPairingRepositoryProvider);
      await _seedPairing(db, id: 'unlocked-phone');

      expect(
        await repository.authenticate('unlocked-phone', 'pairing-secret'),
        isTrue,
      );
    },
  );

  test(
    'provider permits pairing writes while the vault is unconfigured or unlocked',
    () async {
      for (final vaultFactory in <VaultNotifier Function()>[
        _UnconfiguredVaultNotifier.new,
        _UnlockedVaultNotifier.new,
      ]) {
        final db = AppDatabase(NativeDatabase.memory());
        final container = _containerWithVault(db, vaultFactory);
        addTearDown(() async {
          container.dispose();
          await db.close();
        });
        await container.read(vaultProvider.future);

        await _savePairing(
          container.read(deviceLinkPairingRepositoryProvider),
          id: 'write-${vaultFactory.runtimeType}',
        );

        expect(
          await db.pairedDevicesDao.findById(
            'write-${vaultFactory.runtimeType}',
          ),
          isNotNull,
        );
      }
    },
  );

  test(
    'pairing commit completes before its unlocked-vault permit is released',
    () async {
      final db = AppDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      var commitObservedInsidePermit = false;
      final repository = DeviceLinkPairingRepository(
        dao: db.pairedDevicesDao,
        encryption: _testEncryption(),
        isVaultLocked: () => false,
        runWhileVaultUnlocked: <T>(operation) async {
          final result = await operation();
          commitObservedInsidePermit =
              await db.pairedDevicesDao.findById('race-phone') != null;
          return result;
        },
      );

      await _savePairing(repository, id: 'race-phone');

      expect(commitObservedInsidePermit, isTrue);
    },
  );

  test(
    'pairing is rejected when its unlocked-vault permit is unavailable',
    () async {
      final db = AppDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      final repository = DeviceLinkPairingRepository(
        dao: db.pairedDevicesDao,
        encryption: _testEncryption(),
        isVaultLocked: () => false,
        runWhileVaultUnlocked: <T>(operation) {
          return Future<T>.error(
            StateError('Vault is not available for a protected write'),
          );
        },
      );

      await expectLater(
        _savePairing(repository, id: 'race-phone'),
        throwsA(isA<StateError>()),
      );
      expect(await db.pairedDevicesDao.findById('race-phone'), isNull);
    },
  );

  test('secure pairing profiles support list and removal', () async {
    final storage = _MemorySecureStorage();
    final pairingStorage = DeviceLinkPairingStorage(storage);
    final profile = DeviceLinkPairingProfile(
      id: 'desktop-spki-pin',
      deviceId: 'phone-1',
      name: 'Studio Mac',
      platform: 'desktop',
      secret: 'secret',
      host: 'shellvibe-desktop',
      addresses: const ['192.168.1.10'],
      mdns: 'shellvibe-desktop._shellvibe._tcp.local',
      port: 47823,
      spki: 'spki-pin',
      sessionId: 'local-1',
      pairedAt: DateTime.utc(2026, 8, 9),
    );

    await pairingStorage.save(profile);
    final loaded = await pairingStorage.getAll();
    expect(loaded.single.toJson(), profile.toJson());
    await pairingStorage.remove(profile.id);
    expect(await pairingStorage.getAll(), isEmpty);
  });

  test('the client device id is created once and then reused', () async {
    final storage = _MemorySecureStorage();
    final pairingStorage = DeviceLinkPairingStorage(storage);
    var generated = 0;
    String generate() => 'device-${generated++}';

    final first = await pairingStorage.deviceId(generate: generate);
    final second = await pairingStorage.deviceId(generate: generate);

    // A phone that invents an id per scan is a new device to the desktop every
    // time, and cannot be given back the session its last identity holds.
    expect(first, 'device-0');
    expect(second, first);
    expect(generated, 1);

    // It outlives the object that created it — this is what makes it survive
    // an app restart.
    expect(await DeviceLinkPairingStorage(storage).deviceId(), first);
  });

  test('one phone can hold a pairing per desktop', () async {
    final storage = _MemorySecureStorage();
    final pairingStorage = DeviceLinkPairingStorage(storage);
    final deviceId = await pairingStorage.deviceId();
    DeviceLinkQrPayload payloadFor(String spki, String host) =>
        DeviceLinkQrPayload(
          version: deviceLinkProtocolVersion,
          host: host,
          addresses: const ['192.168.1.10'],
          mdns: '$host._shellvibe._tcp.local',
          port: 47823,
          spki: spki,
          token: 'token',
          expiresAt: DateTime.now().toUtc().add(const Duration(minutes: 1)),
        );

    // The phone announces one lasting identity, but a saved pairing describes a
    // desktop — keying the record by the phone would let a second desktop
    // overwrite the first.
    await pairingStorage.save(
      DeviceLinkPairingProfile.fromQr(
        deviceId: deviceId,
        name: 'Studio Mac',
        platform: 'desktop',
        secret: 'secret-a',
        payload: payloadFor('spki-a', 'studio-mac'),
      ),
    );
    await pairingStorage.save(
      DeviceLinkPairingProfile.fromQr(
        deviceId: deviceId,
        name: 'Office PC',
        platform: 'desktop',
        secret: 'secret-b',
        payload: payloadFor('spki-b', 'office-pc'),
      ),
    );

    final saved = await pairingStorage.getAll();
    expect(saved.map((p) => p.name).toSet(), {'Studio Mac', 'Office PC'});
    expect(saved.map((p) => p.deviceId).toSet(), {deviceId});

    // Pairing the same desktop again replaces its record rather than adding a
    // second one.
    await pairingStorage.save(
      DeviceLinkPairingProfile.fromQr(
        deviceId: deviceId,
        name: 'Studio Mac',
        platform: 'desktop',
        secret: 'secret-a2',
        payload: payloadFor('spki-a', 'studio-mac'),
      ),
    );
    expect(await pairingStorage.getAll(), hasLength(2));
  });

  test('a profile saved before the split still authenticates', () async {
    final storage = _MemorySecureStorage();
    // Written when id and device id were the same value.
    await storage.saveToken(
      'device_link_profile_legacy-uuid',
      '{"id":"legacy-uuid","name":"android device","platform":"android",'
          '"secret":"secret","host":"shellvibe-desktop",'
          '"addresses":["192.168.1.10"],'
          '"mdns":"shellvibe-desktop._shellvibe._tcp.local","port":47823,'
          '"spki":"spki-pin","sessionId":"local-1",'
          '"pairedAt":"2026-08-09T00:00:00.000Z"}',
    );
    await storage.saveToken('device_link_profiles_index', '["legacy-uuid"]');

    final profile = (await DeviceLinkPairingStorage(storage).getAll()).single;

    // The desktop knows this phone by the id it paired under, so that is the
    // one it has to keep announcing.
    expect(profile.deviceId, 'legacy-uuid');
    expect(profile.id, 'legacy-uuid');
  });

  test('a corrupt profile index does not throw', () async {
    final storage = _MemorySecureStorage();
    await storage.saveToken('device_link_profiles_index', 'not json at all');

    // Auto-reconnect calls this unawaited, so anything thrown here escapes the
    // zone and stops every pairing from reconnecting.
    expect(await DeviceLinkPairingStorage(storage).getAll(), isEmpty);
  });

  test('pairing again drops the profiles left by earlier client ids', () async {
    final storage = _MemorySecureStorage();
    final pairingStorage = DeviceLinkPairingStorage(storage);
    DeviceLinkPairingProfile profileFor(String id, String spki) =>
        DeviceLinkPairingProfile(
          id: id,
          deviceId: 'phone-1',
          name: 'Studio Mac',
          platform: 'desktop',
          secret: 'secret',
          host: 'shellvibe-desktop',
          addresses: const ['192.168.1.10'],
          mdns: 'shellvibe-desktop._shellvibe._tcp.local',
          port: 47823,
          spki: spki,
          sessionId: 'local-1',
          pairedAt: DateTime.utc(2026, 8, 9),
        );

    await pairingStorage.save(profileFor('old-scan-1', 'desktop-a'));
    await pairingStorage.save(profileFor('old-scan-2', 'desktop-a'));
    await pairingStorage.save(profileFor('other-desktop', 'desktop-b'));
    await pairingStorage.save(profileFor('stable-id', 'desktop-a'));

    await pairingStorage.pruneSupersededProfiles(
      keepId: 'stable-id',
      spki: 'desktop-a',
    );

    // Auto-reconnect dials every stored profile, so a ghost pairing with the
    // same desktop competes for the session this phone is attaching to. A
    // pairing with a *different* desktop is untouched.
    expect((await pairingStorage.getAll()).map((p) => p.id).toSet(), {
      'stable-id',
      'other-desktop',
    });
  });

  test('superseded claims cover only earlier ids for that desktop', () async {
    final storage = _MemorySecureStorage();
    final pairingStorage = DeviceLinkPairingStorage(storage);
    DeviceLinkPairingProfile profileFor(
      String id,
      String deviceId,
      String spki,
      DateTime pairedAt,
    ) => DeviceLinkPairingProfile(
      id: id,
      deviceId: deviceId,
      name: 'Studio Mac',
      platform: 'desktop',
      secret: 'secret-of-$deviceId',
      host: 'shellvibe-desktop',
      addresses: const ['192.168.1.10'],
      mdns: 'shellvibe-desktop._shellvibe._tcp.local',
      port: 47823,
      spki: spki,
      sessionId: 'local-1',
      pairedAt: pairedAt,
    );

    await pairingStorage.save(
      profileFor('old-scan-1', 'phone-old-1', 'desktop-a', DateTime.utc(2026)),
    );
    await pairingStorage.save(
      profileFor(
        'old-scan-2',
        'phone-old-2',
        'desktop-a',
        DateTime.utc(2026, 2),
      ),
    );
    // The current id is not something to retire, and another desktop's secret
    // proves nothing here — sending it would only leak it.
    await pairingStorage.save(
      profileFor('current', 'phone-stable', 'desktop-a', DateTime.utc(2026, 3)),
    );
    await pairingStorage.save(
      profileFor(
        'other-desktop',
        'phone-elsewhere',
        'desktop-b',
        DateTime.utc(2026, 4),
      ),
    );

    final claims = await pairingStorage.supersededDeviceClaims(
      spki: 'desktop-a',
      deviceId: 'phone-stable',
    );

    expect(claims.map((claim) => claim.deviceId), [
      'phone-old-2',
      'phone-old-1',
    ]);
    expect(claims.first.secret, 'secret-of-phone-old-2');
  });

  test('superseded claims stay within the pair frame budget', () async {
    final storage = _MemorySecureStorage();
    final pairingStorage = DeviceLinkPairingStorage(storage);
    for (var index = 0; index < deviceLinkMaxSupersededDevices + 4; index++) {
      await pairingStorage.save(
        DeviceLinkPairingProfile(
          id: 'scan-$index',
          deviceId: 'phone-$index',
          name: 'Studio Mac',
          platform: 'desktop',
          secret: 'secret-$index',
          host: 'shellvibe-desktop',
          addresses: const ['192.168.1.10'],
          mdns: 'shellvibe-desktop._shellvibe._tcp.local',
          port: 47823,
          spki: 'desktop-a',
          sessionId: 'local-1',
          pairedAt: DateTime.utc(2026, 1, index + 1),
        ),
      );
    }

    final claims = await pairingStorage.supersededDeviceClaims(
      spki: 'desktop-a',
      deviceId: 'phone-stable',
    );

    // A pair frame the desktop would reject outright helps nobody: the cap
    // keeps the newest ids, the ones most likely to still hold a row there.
    expect(claims, hasLength(deviceLinkMaxSupersededDevices));
    expect(
      claims.first.deviceId,
      'phone-${deviceLinkMaxSupersededDevices + 3}',
    );
  });

  test(
    'persistent server callbacks allow reconnect and revocation',
    () async {
      final db = AppDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      final repository = DeviceLinkPairingRepository(
        dao: db.pairedDevicesDao,
        encryption: EncryptionEngine(
          kdf: Argon2id(
            parallelism: 1,
            memory: 1024,
            iterations: 1,
            hashLength: 32,
          ),
        ),
        isVaultLocked: () => false,
        runWhileVaultUnlocked: _runWithoutVaultPermit,
      );
      final identity = DeviceLinkIdentity.generate();
      var pairingCompleted = 0;
      final server = DeviceLinkServer(
        identity: identity,
        hostName: 'test-host',
        appVersion: 'test',
        sessionsProvider: () async => const [
          DeviceLinkSessionInfo(id: 'session-1', title: 'zsh', type: 'local'),
        ],
        pairedDeviceAuthenticator: repository.authenticate,
        pairedDevicePersister: (record) => repository.savePairedDevice(
          id: record.id,
          name: record.name,
          platform: record.platform,
          secret: record.secret,
          publicKey: record.publicKey,
          pairedAt: record.pairedAt,
        ),
        onPairingCompleted: () => pairingCompleted++,
      );
      await server.start();
      addTearDown(server.close);

      final payload = await server.createPairingPayload(
        addresses: const ['127.0.0.1'],
        mdnsName: '127.0.0.1',
      );
      final first = await _connect(identity, server.port);
      await first.sendHello(
        const DeviceLinkHello(deviceId: 'phone-1', deviceName: 'iPhone 15'),
      );
      await first.nextControl();
      await first.sendPair(
        DeviceLinkPair(
          token: payload.token,
          deviceName: 'iPhone 15',
          devicePublicKey: 'phone-public-key',
          platform: 'ios',
        ),
      );
      final paired = await first.nextControl();
      expect(paired, isA<DeviceLinkPaired>());
      expect(pairingCompleted, 1);
      final authenticatedHello = await first.nextControl();
      expect(authenticatedHello, isA<DeviceLinkHelloAck>());
      expect(
        (authenticatedHello as DeviceLinkHelloAck).sessions.single.id,
        'session-1',
      );
      final secret = (paired as DeviceLinkPaired).secret;
      await first.close();

      final profile = DeviceLinkPairingProfile.fromQr(
        deviceId: 'phone-1',
        name: 'Studio Mac',
        platform: 'desktop',
        secret: secret,
        payload: payload,
        sessionId: 'session-1',
      );
      final reconnect = await DeviceLinkAutoReconnectService(
        client: DeviceLinkClient(connectionTimeout: const Duration(seconds: 5)),
      ).connect(profile);
      addTearDown(reconnect.connection.close);
      expect(reconnect.session.id, 'session-1');
      expect(reconnect.helloAck.sessions.single.id, 'session-1');

      await repository.remove('phone-1');
      await expectLater(
        DeviceLinkAutoReconnectService(
          client: DeviceLinkClient(
            connectionTimeout: const Duration(seconds: 5),
          ),
        ).connect(profile),
        throwsA(
          predicate<DeviceLinkTransportException>(
            (error) => error.code == 'unauthorized',
          ),
        ),
      );
    },
    timeout: const Timeout(Duration(seconds: 20)),
  );
}

Future<DeviceLinkClientConnection> _connect(
  DeviceLinkIdentity identity,
  int port,
) {
  return DeviceLinkClient(
    connectionTimeout: const Duration(seconds: 5),
  ).connect([
    DeviceLinkEndpoint(
      host: '127.0.0.1',
      port: port,
      spkiSha256Base64: identity.spkiSha256Base64,
    ),
  ]);
}

final class _MemorySecureStorage extends SecureStorageService {
  final Map<String, String> values = {};

  _MemorySecureStorage() : super(storage: const FlutterSecureStorage());

  @override
  Future<void> saveToken(String key, String token) async {
    values[key] = token;
  }

  @override
  Future<String?> getToken(String key) async => values[key];

  @override
  Future<void> deleteToken(String key) async {
    values.remove(key);
  }
}

ProviderContainer _containerWithVault(
  AppDatabase database,
  VaultNotifier Function() createVault,
) {
  return ProviderContainer(
    overrides: [
      appDatabaseProvider.overrideWithValue(database),
      encryptionEngineProvider.overrideWithValue(
        EncryptionEngine(
          kdf: Argon2id(
            parallelism: 1,
            memory: 1024,
            iterations: 1,
            hashLength: 32,
          ),
        ),
      ),
      vaultProvider.overrideWith(createVault),
    ],
  );
}

Future<void> _savePairing(
  DeviceLinkPairingRepository repository, {
  required String id,
}) {
  return repository.savePairedDevice(
    id: id,
    name: 'Test phone',
    platform: 'ios',
    secret: 'pairing-secret',
    publicKey: 'ephemeral-public-key',
  );
}

Future<void> _seedPairing(AppDatabase database, {required String id}) {
  return _savePairing(
    DeviceLinkPairingRepository(
      dao: database.pairedDevicesDao,
      encryption: _testEncryption(),
      isVaultLocked: () => false,
      runWhileVaultUnlocked: _runWithoutVaultPermit,
    ),
    id: id,
  );
}

EncryptionEngine _testEncryption() {
  return EncryptionEngine(
    kdf: Argon2id(parallelism: 1, memory: 1024, iterations: 1, hashLength: 32),
  );
}

Future<T> _runWithoutVaultPermit<T>(Future<T> Function() operation) {
  return operation();
}

class _LoadingVaultNotifier extends VaultNotifier {
  @override
  Future<VaultState> build() => Completer<VaultState>().future;
}

class _FailedVaultNotifier extends VaultNotifier {
  @override
  Future<VaultState> build() async {
    throw StateError('vault state unavailable');
  }
}

class _UnlockedVaultNotifier extends VaultNotifier {
  @override
  Future<VaultState> build() async {
    return const VaultState(status: VaultStatus.unlocked);
  }
}

class _UnconfiguredVaultNotifier extends VaultNotifier {
  @override
  Future<VaultState> build() async {
    return const VaultState(status: VaultStatus.unconfigured);
  }
}

class _StaleLoadingVaultNotifier extends VaultNotifier {
  var _buildCount = 0;
  final _secondBuild = Completer<VaultState>();

  @override
  Future<VaultState> build() {
    if (_buildCount++ == 0) {
      return Future.value(const VaultState(status: VaultStatus.unlocked));
    }
    return _secondBuild.future;
  }
}
