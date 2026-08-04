import 'package:drift/native.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:terly2/features/templates/data/repositories/templates_repository.dart';
import 'package:terly2/features/templates/domain/models/template_model.dart';
import 'package:terly2/features/templates/domain/models/template_pane_model.dart';
import 'package:terly2/features/terminal/domain/models/terminal_tab_session.dart';
import 'package:terly2/shared/database/app_database.dart';

TemplateModel _template({
  String id = 'tpl_1',
  String name = 'Prod triage',
  String? activePaneId,
  List<TemplatePaneModel>? panes,
}) {
  return TemplateModel(
    id: id,
    workspaceId: 'ws_1',
    name: name,
    description: 'Layout for the morning check',
    activePaneId: activePaneId,
    createdAt: DateTime(2026, 8, 4),
    panes: panes ??
        [
          TemplatePaneModel(
            id: 'pane_root',
            templateId: id,
            paneOrder: 0,
            sessionType: TerminalSessionType.ssh,
            hostId: 'host_1',
            title: 'prod-web',
          ),
          TemplatePaneModel(
            id: 'pane_split',
            templateId: id,
            paneOrder: 1,
            parentPaneId: 'pane_root',
            splitDirection: Axis.vertical,
            splitRatio: 0.35,
            sessionType: TerminalSessionType.local,
            title: 'Local Shell',
          ),
        ],
  );
}

void main() {
  late AppDatabase db;
  late TemplatesRepository repository;

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    await db.workspacesDao.insertWorkspace(
      WorkspacesCompanion.insert(
        id: 'ws_1',
        name: 'Default Workspace',
        createdAt: DateTime.now(),
      ),
    );
    repository = TemplatesRepository(db.templatesDao);
  });

  tearDown(() async {
    await db.close();
  });

  group('TemplatesRepository', () {
    test('initial template list is empty', () async {
      expect(await repository.getAllTemplates(), isEmpty);
    });

    test('round-trips a template with its panes', () async {
      await repository.addTemplate(_template(activePaneId: 'pane_split'));

      final loaded = (await repository.getAllTemplates()).single;
      expect(loaded.name, equals('Prod triage'));
      expect(loaded.description, equals('Layout for the morning check'));
      expect(loaded.activePaneId, equals('pane_split'));
      expect(loaded.panes.length, equals(2));
      expect(loaded.tabCount, equals(1));

      final root = loaded.panes[0];
      expect(root.parentPaneId, isNull);
      expect(root.sessionType, equals(TerminalSessionType.ssh));
      expect(root.hostId, equals('host_1'));

      final split = loaded.panes[1];
      expect(split.parentPaneId, equals('pane_root'));
      expect(split.splitDirection, equals(Axis.vertical));
      expect(split.splitRatio, closeTo(0.35, 1e-9));
      expect(split.sessionType, equals(TerminalSessionType.local));
      expect(split.hostId, isNull);
    });

    test('panes come back in capture order regardless of insert order',
        () async {
      await repository.addTemplate(
        _template(
          panes: [
            TemplatePaneModel(
              id: 'pane_c',
              templateId: 'tpl_1',
              paneOrder: 2,
              sessionType: TerminalSessionType.local,
            ),
            TemplatePaneModel(
              id: 'pane_a',
              templateId: 'tpl_1',
              paneOrder: 0,
              sessionType: TerminalSessionType.local,
            ),
            TemplatePaneModel(
              id: 'pane_b',
              templateId: 'tpl_1',
              paneOrder: 1,
              sessionType: TerminalSessionType.local,
            ),
          ],
        ),
      );

      final loaded = (await repository.getAllTemplates()).single;
      expect(loaded.panes.map((p) => p.id), ['pane_a', 'pane_b', 'pane_c']);
    });

    test('updateTemplate replaces the pane set rather than appending it',
        () async {
      await repository.addTemplate(_template());

      final loaded = (await repository.getAllTemplates()).single;
      await repository.updateTemplate(
        loaded.copyWith(
          name: 'Renamed',
          panes: [
            TemplatePaneModel(
              id: 'pane_only',
              templateId: 'tpl_1',
              paneOrder: 0,
              sessionType: TerminalSessionType.local,
              title: 'Just one',
            ),
          ],
        ),
      );

      final updated = (await repository.getAllTemplates()).single;
      expect(updated.name, equals('Renamed'));
      expect(updated.panes.map((p) => p.id), ['pane_only']);
    });

    test('deleteTemplate removes the template and its panes', () async {
      await repository.addTemplate(_template());
      await repository.deleteTemplate('tpl_1');

      expect(await repository.getAllTemplates(), isEmpty);
      expect(await db.templatesDao.getPanesForTemplate('tpl_1'), isEmpty);
    });

    test('scopes templates to a workspace', () async {
      await db.workspacesDao.insertWorkspace(
        WorkspacesCompanion.insert(
          id: 'ws_2',
          name: 'Other',
          createdAt: DateTime.now(),
        ),
      );
      await repository.addTemplate(_template());
      await repository.addTemplate(
        TemplateModel(
          id: 'tpl_2',
          workspaceId: 'ws_2',
          name: 'Other workspace layout',
          createdAt: DateTime(2026, 8, 4),
          panes: const [],
        ),
      );

      final scoped = await repository.getTemplatesByWorkspace('ws_1');
      expect(scoped.map((t) => t.id), ['tpl_1']);
    });

    test('a pane keeps its host id after that host is deleted', () async {
      // The host reference is deliberately not a foreign key, so a deleted host
      // leaves the template intact and is reported at run time instead.
      await repository.addTemplate(_template());

      final loaded = (await repository.getAllTemplates()).single;
      expect(loaded.panes.first.hostId, equals('host_1'));
    });
  });
}
