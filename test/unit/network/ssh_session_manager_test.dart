import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:terly2/core/network/ssh_session_manager.dart';
import 'package:terly2/shared/database/app_database.dart';

void main() {
  group('SSHSessionManager Unit Tests', () {
    late AppDatabase db;
    late SSHSessionManager sessionManager;

    setUp(() {
      db = AppDatabase(NativeDatabase.memory());
      sessionManager = SSHSessionManager(knownHostsDao: db.knownHostsDao);
    });

    tearDown(() async {
      await sessionManager.close();
      await db.close();
    });

    test('First time host connection (TOFU) saves host key fingerprint to KnownHostsDao', () async {
      const hostname = '192.168.1.100';
      const port = 22;
      const keyType = 'ssh-ed25519';
      const fingerprint = 'SHA256:abcd1234efgh5678ijkl';

      final verified = await sessionManager.verifyHostKey(
        hostname: hostname,
        port: port,
        keyType: keyType,
        fingerprint: fingerprint,
      );

      expect(verified, isTrue);

      final savedHost = await db.knownHostsDao.findKnownHost(hostname, port);
      expect(savedHost, isNotNull);
      expect(savedHost!.hostname, equals(hostname));
      expect(savedHost.port, equals(port));
      expect(savedHost.keyType, equals(keyType));
      expect(savedHost.fingerprintSha256, equals(fingerprint));
    });

    test('Subsequent connection with matching host key automatically succeeds', () async {
      const hostname = 'myserver.com';
      const port = 2222;
      const keyType = 'rsa-sha2-512';
      const fingerprint = 'SHA256:matchingFingerprint123';

      // 1. Initial connection
      await sessionManager.verifyHostKey(
        hostname: hostname,
        port: port,
        keyType: keyType,
        fingerprint: fingerprint,
      );

      // 2. Second connection
      final verified = await sessionManager.verifyHostKey(
        hostname: hostname,
        port: port,
        keyType: keyType,
        fingerprint: fingerprint,
      );

      expect(verified, isTrue);
    });

    test('Host key mismatch triggers mismatch status callback and returns false if rejected', () async {
      const hostname = 'secure.example.com';
      const port = 22;
      const keyType = 'ssh-ed25519';
      const originalFingerprint = 'SHA256:originalKey123';
      const alteredFingerprint = 'SHA256:maliciousKey999';

      // Store initial legitimate key
      await sessionManager.verifyHostKey(
        hostname: hostname,
        port: port,
        keyType: keyType,
        fingerprint: originalFingerprint,
      );

      HostKeyVerificationStatus? capturedStatus;

      // Connect again with altered key (simulating MitM attack)
      final verified = await sessionManager.verifyHostKey(
        hostname: hostname,
        port: port,
        keyType: keyType,
        fingerprint: alteredFingerprint,
        promptCallback: (host, p, type, fp, status) {
          capturedStatus = status;
          return false; // Reject MitM attempt
        },
      );

      expect(capturedStatus, equals(HostKeyVerificationStatus.mismatch));
      expect(verified, isFalse);
    });

    test('Host key mismatch updates database and returns true if user approves prompt', () async {
      const hostname = 'secure.example.com';
      const port = 2222;
      const keyType = 'ssh-ed25519';
      const originalFingerprint = 'SHA256:legitimateKey456';
      const alteredFingerprint = 'SHA256:updatedKey789';

      // Store initial key
      await sessionManager.verifyHostKey(
        hostname: hostname,
        port: port,
        keyType: keyType,
        fingerprint: originalFingerprint,
      );

      HostKeyVerificationStatus? capturedStatus;

      // Connect again with altered key — user approves update
      final verified = await sessionManager.verifyHostKey(
        hostname: hostname,
        port: port,
        keyType: keyType,
        fingerprint: alteredFingerprint,
        promptCallback: (host, p, type, fp, status) {
          capturedStatus = status;
          return true; // User approves key update
        },
      );

      expect(capturedStatus, equals(HostKeyVerificationStatus.mismatch));
      expect(verified, isTrue);

      // Verify key is updated in database
      final savedHost = await db.knownHostsDao.findKnownHost(hostname, port);
      expect(savedHost, isNotNull);
      expect(savedHost!.fingerprintSha256, equals(alteredFingerprint));
    });

    test('Invalid private key format throws FormatException on connect attempt', () {
      const config = SSHConnectConfig(
        hostname: '127.0.0.1',
        username: 'root',
        privateKeyPem: '--- INVALID KEY CONTENT ---',
      );

      expect(
        () => sessionManager.connect(config),
        throwsA(isA<FormatException>()),
      );
    });
  });
}
