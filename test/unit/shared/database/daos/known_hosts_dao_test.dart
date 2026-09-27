import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shellvibe/shared/database/app_database.dart';
import 'package:shellvibe/shared/database/daos/known_hosts_dao.dart';

void main() {
  group('KnownHostsDao Unit Tests', () {
    late AppDatabase db;
    late KnownHostsDao knownHostsDao;

    setUp(() {
      db = AppDatabase(NativeDatabase.memory());
      knownHostsDao = db.knownHostsDao;
    });

    tearDown(() async {
      await db.close();
    });

    // Deciding whether a presented key matches is SSHSessionManager's job and
    // is tested there; this only covers what the DAO stores and replaces.
    test(
      'Fingerprint insertion, retrieval, replacement and deletion',
      () async {
      const hostname = 'ssh.example.com';
      const port = 22;
        const initialFingerprint =
            'SHA256:abc123def456ghi789jkl012mno345pqr678stu901v';

      final initialEntry = KnownHostsCompanion.insert(
        id: 'kh-1',
        hostname: hostname,
        port: port,
        keyType: 'ssh-ed25519',
        fingerprintSha256: initialFingerprint,
        firstSeenAt: DateTime.now(),
      );

      await knownHostsDao.insertOrUpdateKnownHost(initialEntry);

      // 1. Retrieval
      final foundHost = await knownHostsDao.findKnownHost(hostname, port);
      expect(foundHost, isNotNull);
      expect(foundHost!.hostname, equals(hostname));
      expect(foundHost.port, equals(port));
      expect(foundHost.fingerprintSha256, equals(initialFingerprint));
      expect(foundHost.keyType, equals('ssh-ed25519'));

        // A lookup on another port is a different trust entry.
        expect(await knownHostsDao.findKnownHost(hostname, 2222), isNull);

        // 2. Replacing the host key after the user trusts a new fingerprint
        const incomingFingerprint =
            'SHA256:DIFFERENT_FINGERPRINT_SUSPECTED_MITM_ATTACK';
      final updatedEntry = KnownHostsCompanion.insert(
        id: 'kh-1',
        hostname: hostname,
        port: port,
        keyType: 'ssh-ed25519',
        fingerprintSha256: incomingFingerprint,
        firstSeenAt: DateTime.now(),
      );
      await knownHostsDao.insertOrUpdateKnownHost(updatedEntry);

      final reFetchedHost = await knownHostsDao.findKnownHost(hostname, port);
      expect(reFetchedHost, isNotNull);
      expect(reFetchedHost!.fingerprintSha256, equals(incomingFingerprint));

        // 3. Deletion
      await knownHostsDao.deleteKnownHost('kh-1');
      expect(await knownHostsDao.findKnownHost(hostname, port), isNull);
      },
    );
  });
}
