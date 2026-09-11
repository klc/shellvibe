import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shellvibe/shared/database/app_database.dart';
import 'package:shellvibe/shared/database/daos/snippets_dao.dart';

void main() {
  group('SnippetsDao Unit Tests', () {
    late AppDatabase db;
    late SnippetsDao snippetsDao;

    setUp(() {
      db = AppDatabase(NativeDatabase.memory());
      snippetsDao = db.snippetsDao;
    });

    tearDown(() async {
      await db.close();
    });

    test('Snippet CRUD operations', () async {
      final companion1 = SnippetsCompanion.insert(
        id: 'snip-1',
        workspaceId: 'default',
        title: 'Restart Nginx',
        code: 'sudo systemctl restart nginx',
        tags: const Value('["nginx", "restart"]'),
      );

      final companion2 = SnippetsCompanion.insert(
        id: 'snip-2',
        workspaceId: 'default',
        title: 'Check Disk Space',
        code: 'df -h',
      );

      await snippetsDao.insertSnippet(companion1);
      await snippetsDao.insertSnippet(companion2);

      // Read
      final allSnippets = await snippetsDao.getAllSnippets();
      expect(allSnippets.length, equals(2));

      final workspaceSnippets = await snippetsDao.getSnippetsByWorkspace('default');
      expect(workspaceSnippets.length, equals(2));
      expect(workspaceSnippets.first.code, equals('sudo systemctl restart nginx'));

      // Update
      final updatedCompanion = SnippetsCompanion(
        id: const Value('snip-1'),
        workspaceId: const Value('default'),
        title: const Value('Graceful Nginx Reload'),
        code: const Value('sudo systemctl reload nginx'),
      );
      final updateSuccess = await snippetsDao.updateSnippet(updatedCompanion);
      expect(updateSuccess, isTrue);

      final updatedList = await snippetsDao.getAllSnippets();
      final updatedSnippet = updatedList.firstWhere((s) => s.id == 'snip-1');
      expect(updatedSnippet.title, equals('Graceful Nginx Reload'));
      expect(updatedSnippet.code, equals('sudo systemctl reload nginx'));

      // Delete
      await snippetsDao.deleteSnippet('snip-1');
      final remaining = await snippetsDao.getAllSnippets();
      expect(remaining.length, equals(1));
      expect(remaining.first.id, equals('snip-2'));
    });
  });
}
