import 'package:cryptography/cryptography.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:drift/native.dart';

import 'package:terly2/core/crypto/encryption_engine.dart';
import 'package:terly2/core/network/device_link/device_link_client.dart';
import 'package:terly2/core/network/device_link/device_link_identity.dart';
import 'package:terly2/core/network/device_link/device_link_protocol.dart';
import 'package:terly2/core/network/device_link/device_link_server.dart';
import 'package:terly2/features/device_link/data/repositories/device_link_pairing_repository.dart';
import 'package:terly2/features/device_link/data/repositories/device_link_pairing_storage.dart';
import 'package:terly2/features/device_link/data/services/device_link_auto_reconnect_service.dart';
import 'package:terly2/features/device_link/domain/models/device_link_pairing_profile.dart';
import 'package:terly2/shared/database/app_database.dart';
import 'package:terly2/shared/storage/secure_storage_service.dart';

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

  test('secure pairing profiles support list and removal', () async {
    final storage = _MemorySecureStorage();
    final pairingStorage = DeviceLinkPairingStorage(storage);
    final profile = DeviceLinkPairingProfile(
      id: 'phone-1',
      name: 'iPhone 15',
      platform: 'ios',
      secret: 'secret',
      host: 'terly-desktop',
      addresses: const ['192.168.1.10'],
      mdns: 'terly-desktop._terly._tcp.local',
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
      final secret = (paired as DeviceLinkPaired).secret;
      await first.close();

      final profile = DeviceLinkPairingProfile.fromQr(
        id: 'phone-1',
        name: 'iPhone 15',
        platform: 'ios',
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
