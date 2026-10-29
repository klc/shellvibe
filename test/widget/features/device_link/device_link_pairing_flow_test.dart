import 'dart:io';

import 'package:cryptography/cryptography.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:shellvibe/core/crypto/encryption_engine.dart';
import 'package:shellvibe/core/network/device_link/device_link_identity.dart';
import 'package:shellvibe/core/network/device_link/device_link_server.dart';
import 'package:shellvibe/core/utils/platform_capabilities.dart';
import 'package:shellvibe/features/device_link/data/repositories/device_link_pairing_repository.dart';
import 'package:shellvibe/features/device_link/data/repositories/device_link_pairing_storage.dart';
import 'package:shellvibe/features/device_link/domain/models/device_link_pairing_profile.dart';
import 'package:shellvibe/features/device_link/presentation/notifiers/device_link_notifier.dart';
import 'package:shellvibe/features/device_link/presentation/screens/scan_pair_screen.dart';
import 'package:shellvibe/features/device_link/presentation/widgets/session_picker_sheet.dart';
import 'package:shellvibe/shared/database/app_database.dart';
import 'package:shellvibe/shared/providers/database_providers.dart';
import 'package:shellvibe/shared/storage/secure_storage_service.dart';

void main() {
  tearDown(() => debugPlatformCapabilitiesOverride = null);

  testWidgets(
    'rescanning a paired desktop and dismissing the picker keeps the saved '
    'pairing authorised',
    (tester) async {
      // The flow talks to a real loopback desktop, not the test binding's
      // canned HTTP client.
      HttpOverrides.global = null;
      // Desktop layout skips the camera view; the flow is driven directly.
      debugPlatformCapabilitiesOverride = TargetPlatform.macOS;
      final storage = _MemorySecureStorage();
      final pairingStorage = DeviceLinkPairingStorage(storage);
      late AppDatabase db;
      late DeviceLinkPairingRepository repository;
      late DeviceLinkServer server;
      late DeviceLinkQrPayload payload;
      await tester.runAsync(() async {
        db = AppDatabase(NativeDatabase.memory());
        repository = DeviceLinkPairingRepository(
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
          runWhileVaultUnlocked: <T>(operation) => operation(),
        );
        server = DeviceLinkServer(
          identity: DeviceLinkIdentity.generate(),
          hostName: 'test-host',
          appVersion: 'test',
          // No live session: dismissing the picker is the only way out.
          sessionsProvider: () async => const [],
          pairedDeviceAuthenticator: repository.authenticate,
          pairedDevicePersister: (record) => repository.savePairedDevice(
            id: record.id,
            name: record.name,
            platform: record.platform,
            secret: record.secret,
            publicKey: record.publicKey,
            pairedAt: record.pairedAt,
          ),
        );
        await server.start();
        payload = await server.createPairingPayload(
          addresses: const ['127.0.0.1'],
          mdnsName: '127.0.0.1',
        );
        // An earlier pairing both sides still agree on.
        final deviceId = await pairingStorage.deviceId();
        await repository.savePairedDevice(
          id: deviceId,
          name: 'phone',
          platform: 'android',
          secret: 'old-secret',
          publicKey: 'ephemeral-$deviceId',
        );
        await pairingStorage.save(
          DeviceLinkPairingProfile.fromQr(
            deviceId: deviceId,
            name: 'test-host',
            platform: 'desktop',
            secret: 'old-secret',
            payload: payload,
            sessionId: 'session-1',
          ),
        );
      });

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            secureStorageServiceProvider.overrideWithValue(storage),
            deviceLinkProvider.overrideWith(_IdleDeviceLinkNotifier.new),
          ],
          child: const MaterialApp(home: DeviceLinkPairingFlowScreen()),
        ),
      );
      final scanner = tester.widget<DeviceLinkScanPairScreen>(
        find.byType(DeviceLinkScanPairScreen),
      );
      late Future<void> pairing;
      await tester.runAsync(() async {
        pairing = Future.sync(() => scanner.onPayload(payload));
      });
      final picker = find.byType(DeviceLinkSessionPickerSheet);
      for (var i = 0; i < 250 && picker.evaluate().isEmpty; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 20)),
        );
        await tester.pump();
      }
      expect(find.text('No live terminal sessions found.'), findsOneWidget);

      Navigator.of(tester.element(picker)).pop();
      await tester.pumpAndSettle();

      DeviceLinkPairingProfile? saved;
      var authorised = false;
      await tester.runAsync(() async {
        await pairing;
        saved = await pairingStorage.getById(payload.spki);
        if (saved != null) {
          authorised = await repository.authenticate(
            saved!.deviceId,
            saved!.secret,
          );
        }
        await server.close();
        await db.close();
      });

      expect(saved?.sessionId, 'session-1');
      expect(
        authorised,
        isTrue,
        reason: 'the desktop replaced the secret, the phone must keep it',
      );
    },
  );
}

final class _IdleDeviceLinkNotifier extends DeviceLinkNotifier {
  @override
  void build() {}
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
