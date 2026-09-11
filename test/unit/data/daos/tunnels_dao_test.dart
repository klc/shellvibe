import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shellvibe/shared/database/app_database.dart';
import 'package:shellvibe/shared/database/daos/hosts_dao.dart';
import 'package:shellvibe/shared/database/daos/tunnels_dao.dart';

void main() {
  group('TunnelsDao Unit Tests', () {
    late AppDatabase db;
    late HostsDao hostsDao;
    late TunnelsDao tunnelsDao;

    setUp(() {
      db = AppDatabase(NativeDatabase.memory());
      hostsDao = db.hostsDao;
      tunnelsDao = db.tunnelsDao;
    });

    tearDown(() async {
      await db.close();
    });

    test('Tunnel rule persistence, queries, updates, and deletion', () async {
      // Create parent host
      await hostsDao.insertHost(
        HostsCompanion.insert(
          id: 'host-tunnel-test',
          workspaceId: 'default',
          label: 'App Server',
          hostname: 'app.example.com',
          createdAt: DateTime.now(),
        ),
      );

      final rule1 = PortForwardRulesCompanion.insert(
        id: 'rule-local-1',
        hostId: 'host-tunnel-test',
        type: 'local',
        localPort: 8080,
        remoteHost: const Value('127.0.0.1'),
        remotePort: const Value(80),
        autoStart: const Value(true),
      );

      final rule2 = PortForwardRulesCompanion.insert(
        id: 'rule-socks5-1',
        hostId: 'host-tunnel-test',
        type: 'dynamic',
        localPort: 1080,
        autoStart: const Value(false),
      );

      await tunnelsDao.insertRule(rule1);
      await tunnelsDao.insertRule(rule2);

      // Fetch rules for host
      final hostRules = await tunnelsDao.getRulesForHost('host-tunnel-test');
      expect(hostRules.length, equals(2));

      // Fetch autostart rules
      final autoStartRules = await tunnelsDao.getAutoStartRules();
      expect(autoStartRules.length, equals(1));
      expect(autoStartRules.first.id, equals('rule-local-1'));
      expect(autoStartRules.first.type, equals('local'));
      expect(autoStartRules.first.localPort, equals(8080));

      // Fetch rule by ID
      final singleRule = await tunnelsDao.getRuleById('rule-socks5-1');
      expect(singleRule, isNotNull);
      expect(singleRule!.type, equals('dynamic'));
      expect(singleRule.localPort, equals(1080));

      // Delete rule
      await tunnelsDao.deleteRule('rule-local-1');
      final remainingRules = await tunnelsDao.getRulesForHost('host-tunnel-test');
      expect(remainingRules.length, equals(1));
      expect(remainingRules.first.id, equals('rule-socks5-1'));
    });
  });
}
