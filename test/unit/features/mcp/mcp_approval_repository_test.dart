import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:shellvibe/features/mcp/data/repositories/mcp_approval_repository.dart';
import 'package:shellvibe/features/mcp/domain/models/mcp_enums.dart';
import 'package:shellvibe/shared/database/app_database.dart';
import 'package:shellvibe/shared/database/daos/mcp_dao.dart';

/// Unit tests for [McpApprovalRepository].
///
/// See `docs/mcp_plan.md`, "Onay hatırlama semantiği": a remembered approval
/// is keyed to the exact `(clientId, hostId, cwd, normalize(command))` tuple
/// and is NEVER generalized into a pattern.
void main() {
  late AppDatabase db;
  late McpDao dao;
  late McpApprovalRepository repo;

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    dao = db.mcpDao;
    repo = McpApprovalRepository(dao);

    await db.hostsDao.insertHost(
      HostsCompanion.insert(
        id: 'host-1',
        workspaceId: 'default',
        label: 'Host 1',
        hostname: '10.0.0.1',
        createdAt: DateTime.now(),
      ),
    );
    await db.hostsDao.insertHost(
      HostsCompanion.insert(
        id: 'host-2',
        workspaceId: 'default',
        label: 'Host 2',
        hostname: '10.0.0.2',
        createdAt: DateTime.now(),
      ),
    );
    await dao.insertClient(
      McpClientsCompanion.insert(
        id: 'client-1',
        workspaceId: 'default',
        name: 'Claude Desktop',
        tokenHash: 'hash-1',
        createdAt: DateTime.now(),
      ),
    );
    await dao.insertClient(
      McpClientsCompanion.insert(
        id: 'client-2',
        workspaceId: 'default',
        name: 'Other Client',
        tokenHash: 'hash-2',
        createdAt: DateTime.now(),
      ),
    );
  });

  tearDown(() => db.close());

  group('normalizeCommand', () {
    test('only touches whitespace', () {
      expect(
        repo.normalizeCommand('  rm   -rf ./x  '),
        repo.normalizeCommand('rm -rf ./x'),
      );
      expect(repo.normalizeCommand('rm -rf ./x'), 'rm -rf ./x');
      // Different commands must not collapse onto the same normalized form.
      expect(
        repo.normalizeCommand('rm -rf ./x'),
        isNot(repo.normalizeCommand('rm -rf ./y')),
      );
    });
  });

  test(
    'ANTI-GENERALIZATION GUARANTEE: an approval for `rm -rf ./nginx/*.gz` in '
    '/var/log does NOT satisfy `rm -rf *` — in the same cwd, on the same '
    'host, for the same client. This is the single most important test in '
    'the feature: a remembered approval must never be read as a pattern.',
    () async {
      await repo.remember(
        clientId: 'client-1',
        hostId: 'host-1',
        cwd: '/var/log',
        command: 'rm -rf ./nginx/*.gz',
        scope: ApprovalScope.always,
      );

      final broaderPatternMatches = await repo.hasApproval(
        clientId: 'client-1',
        hostId: 'host-1',
        cwd: '/var/log',
        command: 'rm -rf *',
      );
      expect(
        broaderPatternMatches,
        isFalse,
        reason:
            'An approval for one exact command text must never authorize a '
            'broader glob in the same cwd/host/client.',
      );

      // The exact command that was actually approved still matches.
      final exactMatches = await repo.hasApproval(
        clientId: 'client-1',
        hostId: 'host-1',
        cwd: '/var/log',
        command: 'rm -rf ./nginx/*.gz',
      );
      expect(exactMatches, isTrue);
    },
  );

  test(
    'the match key is the full (clientId, hostId, cwd, command) tuple — '
    'changing any one field alone makes a stored approval not match',
    () async {
      await repo.remember(
        clientId: 'client-1',
        hostId: 'host-1',
        cwd: '/var/log',
        command: 'ls -la',
        scope: ApprovalScope.always,
      );

      expect(
        await repo.hasApproval(
          clientId: 'client-1',
          hostId: 'host-1',
          cwd: '/var/log',
          command: 'ls -la',
        ),
        isTrue,
        reason: 'the exact tuple must match',
      );
      expect(
        await repo.hasApproval(
          clientId: 'client-2',
          hostId: 'host-1',
          cwd: '/var/log',
          command: 'ls -la',
        ),
        isFalse,
        reason: 'different clientId',
      );
      expect(
        await repo.hasApproval(
          clientId: 'client-1',
          hostId: 'host-2',
          cwd: '/var/log',
          command: 'ls -la',
        ),
        isFalse,
        reason: 'different hostId',
      );
      expect(
        await repo.hasApproval(
          clientId: 'client-1',
          hostId: 'host-1',
          cwd: '/tmp',
          command: 'ls -la',
        ),
        isFalse,
        reason: 'different cwd',
      );
      expect(
        await repo.hasApproval(
          clientId: 'client-1',
          hostId: 'host-1',
          cwd: '/var/log',
          command: 'ls -la extra',
        ),
        isFalse,
        reason: 'different command',
      );
    },
  );

  test('ApprovalScope.once stores nothing at all, so it never matches later', () async {
    await repo.remember(
      clientId: 'client-1',
      hostId: 'host-1',
      cwd: '/tmp',
      command: 'ls -la',
      scope: ApprovalScope.once,
    );

    expect(
      await repo.hasApproval(
        clientId: 'client-1',
        hostId: 'host-1',
        cwd: '/tmp',
        command: 'ls -la',
      ),
      isFalse,
    );
    expect(await repo.listActive('client-1'), isEmpty);
  });

  test('fifteenMinutes matches before its expiry and not after', () async {
    await repo.remember(
      clientId: 'client-1',
      hostId: 'host-1',
      cwd: '/tmp',
      command: 'ls -la',
      scope: ApprovalScope.fifteenMinutes,
    );
    final stored = (await repo.listActive('client-1')).single;
    final expiresAt = stored.expiresAt;
    expect(expiresAt, isNotNull);

    final beforeExpiry = expiresAt!.subtract(const Duration(seconds: 1));
    expect(
      await repo.hasApproval(
        clientId: 'client-1',
        hostId: 'host-1',
        cwd: '/tmp',
        command: 'ls -la',
        now: beforeExpiry,
      ),
      isTrue,
    );

    final afterExpiry = expiresAt.add(const Duration(seconds: 1));
    expect(
      await repo.hasApproval(
        clientId: 'client-1',
        hostId: 'host-1',
        cwd: '/tmp',
        command: 'ls -la',
        now: afterExpiry,
      ),
      isFalse,
    );
  });

  test(
    'session-scoped rows are removed once their MCP connection drops; '
    'always-scoped rows survive that cleanup.\n'
    'NOTE: McpApprovalRepository itself exposes no revokeByConnectionScope '
    'wrapper (unlike McpGrantRepository, which has one) — this test drives '
    "the DAO's deleteApprovalsByConnectionScope directly. See the "
    'discrepancy note in the final report.',
    () async {
      await repo.remember(
        clientId: 'client-1',
        hostId: 'host-1',
        cwd: '/tmp',
        command: 'session-cmd',
        scope: ApprovalScope.session,
        connectionScopeId: 'conn-1',
      );
      await repo.remember(
        clientId: 'client-1',
        hostId: 'host-1',
        cwd: '/tmp',
        command: 'always-cmd',
        scope: ApprovalScope.always,
      );

      await dao.deleteApprovalsByConnectionScope('conn-1');

      expect(
        await repo.hasApproval(
          clientId: 'client-1',
          hostId: 'host-1',
          cwd: '/tmp',
          command: 'session-cmd',
        ),
        isFalse,
      );
      expect(
        await repo.hasApproval(
          clientId: 'client-1',
          hostId: 'host-1',
          cwd: '/tmp',
          command: 'always-cmd',
        ),
        isTrue,
      );
    },
  );

  test('revokeAll clears everything', () async {
    await repo.remember(
      clientId: 'client-1',
      hostId: 'host-1',
      cwd: '/tmp',
      command: 'a',
      scope: ApprovalScope.always,
    );
    await repo.remember(
      clientId: 'client-1',
      hostId: 'host-2',
      cwd: '/tmp',
      command: 'b',
      scope: ApprovalScope.always,
    );

    await repo.revokeAll();

    expect(
      await repo.hasApproval(
        clientId: 'client-1',
        hostId: 'host-1',
        cwd: '/tmp',
        command: 'a',
      ),
      isFalse,
    );
    expect(
      await repo.hasApproval(
        clientId: 'client-1',
        hostId: 'host-2',
        cwd: '/tmp',
        command: 'b',
      ),
      isFalse,
    );
    expect(await repo.listActive('client-1'), isEmpty);
  });
}
