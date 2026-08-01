import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:terly2/core/network/ssh_session_manager.dart';
import 'package:terly2/shared/database/app_database.dart';

/// Prompt callback that trusts whatever key it is shown. Unknown hosts are
/// denied without a prompt, so tests that need a key on record must supply one.
bool _approvePrompt(
  String host,
  int port,
  String type,
  String fingerprint,
  HostKeyVerificationStatus status,
) => true;

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

    test(
      'First time host connection (TOFU) saves host key fingerprint to KnownHostsDao',
      () async {
        const hostname = '192.168.1.100';
        const port = 22;
        const keyType = 'ssh-ed25519';
        const fingerprint = 'SHA256:abcd1234efgh5678ijkl';

        final verified = await sessionManager.verifyHostKey(
          hostname: hostname,
          port: port,
          keyType: keyType,
          fingerprint: fingerprint,
          promptCallback: _approvePrompt,
        );

        expect(verified, isTrue);

        final savedHost = await db.knownHostsDao.findKnownHost(hostname, port);
        expect(savedHost, isNotNull);
        expect(savedHost!.hostname, equals(hostname));
        expect(savedHost.port, equals(port));
        expect(savedHost.keyType, equals(keyType));
        expect(savedHost.fingerprintSha256, equals(fingerprint));
      },
    );

    test(
      'Subsequent connection with matching host key automatically succeeds',
      () async {
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
          promptCallback: _approvePrompt,
        );

        // 2. Second connection
        final verified = await sessionManager.verifyHostKey(
          hostname: hostname,
          port: port,
          keyType: keyType,
          fingerprint: fingerprint,
        );

        expect(verified, isTrue);
      },
    );

    test(
      'Unknown host is denied when no prompt callback can confirm the key',
      () async {
        final verified = await sessionManager.verifyHostKey(
          hostname: 'unconfirmed.example.com',
          port: 22,
          keyType: 'ssh-ed25519',
          fingerprint: 'SHA256:noOneAskedTheUser',
        );

        expect(verified, isFalse);
        expect(
          await db.knownHostsDao.findKnownHost('unconfirmed.example.com', 22),
          isNull,
        );
      },
    );

    test(
      'Host key is denied when neither a store nor a prompt is available',
      () async {
        final daolessManager = SSHSessionManager();
        final verified = await daolessManager.verifyHostKey(
          hostname: 'nowhere.example.com',
          port: 22,
          keyType: 'ssh-ed25519',
          fingerprint: 'SHA256:unverifiable',
        );

        expect(verified, isFalse);
        await daolessManager.close();
      },
    );

    test(
      'Host key mismatch invokes prompt callback with mismatch status and denies connection',
      () async {
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
          promptCallback: _approvePrompt,
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
      },
    );

    test(
      'Host key mismatch invokes prompt callback with mismatch status and never updates database',
      () async {
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
          promptCallback: _approvePrompt,
        );

        HostKeyVerificationStatus? capturedStatus;

        // Connect again with altered key — a prompt approval cannot override a
        // changed known_hosts entry.
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
        expect(verified, isFalse);

        // The original trusted key remains unchanged.
        final savedHost = await db.knownHostsDao.findKnownHost(hostname, port);
        expect(savedHost, isNotNull);
        expect(savedHost!.fingerprintSha256, equals(originalFingerprint));
      },
    );

    test(
      'Invalid private key format throws FormatException on connect attempt',
      () {
        const config = SSHConnectConfig(
          hostname: '127.0.0.1',
          username: 'root',
          privateKeyPem: '--- INVALID KEY CONTENT ---',
        );

        expect(
          () => sessionManager.connect(config),
          throwsA(isA<FormatException>()),
        );
      },
    );
  });
}
