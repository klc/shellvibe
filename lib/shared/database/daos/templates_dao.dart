import 'package:drift/drift.dart';
import '../app_database.dart';
import '../tables.dart';

part 'templates_dao.g.dart';

@DriftAccessor(tables: [Templates, TemplatePanes])
class TemplatesDao extends DatabaseAccessor<AppDatabase>
    with _$TemplatesDaoMixin {
  TemplatesDao(super.db);

  Future<List<Template>> getAllTemplates() => select(templates).get();

  Future<List<Template>> getTemplatesByWorkspace(String workspaceId) {
    return (select(
      templates,
    )..where((tbl) => tbl.workspaceId.equals(workspaceId))).get();
  }

  Stream<List<Template>> watchAllTemplates() => select(templates).watch();

  /// Panes in capture order — replay depends on this ordering, so it is applied
  /// here rather than left to the caller.
  Future<List<TemplatePane>> getPanesForTemplate(String templateId) {
    return (select(templatePanes)
          ..where((tbl) => tbl.templateId.equals(templateId))
          ..orderBy([(tbl) => OrderingTerm.asc(tbl.paneOrder)]))
        .get();
  }

  Future<int> insertTemplate(TemplatesCompanion template) => db.recordUpsert(
    entityType: 'templates',
    entityId: template.id.value,
    write: () => into(templates).insert(template),
  );

  Future<bool> updateTemplate(TemplatesCompanion template) => db.recordUpsert(
    entityType: 'templates',
    entityId: template.id.value,
    write: () => update(templates).replace(template),
  );

  /// Deletes the template. Its panes and any bookmark pointing at it go too.
  ///
  /// The explicit pane delete is gone: `template_panes.template_id` cascades,
  /// so the database was going to remove them anyway, and doing it by hand
  /// meant the sync journal saw a bare delete it could not attribute.
  Future<int> deleteTemplate(String id) => db.recordDelete(
    entityType: 'templates',
    entityId: id,
    write: () => (delete(templates)..where((tbl) => tbl.id.equals(id))).go(),
  );

  Future<void> replacePanes(
    String templateId,
    List<TemplatePanesCompanion> panes,
  ) async {
    await transaction(() async {
      final removed = await (select(
        templatePanes,
      )..where((tbl) => tbl.templateId.equals(templateId))).get();

      for (final pane in removed) {
        await db.recordDelete(
          entityType: 'template_panes',
          entityId: pane.id,
          write: () => (delete(
            templatePanes,
          )..where((tbl) => tbl.id.equals(pane.id))).go(),
        );
      }

      for (final pane in panes) {
        await db.recordUpsert(
          entityType: 'template_panes',
          entityId: pane.id.value,
          write: () => into(templatePanes).insert(pane),
        );
      }
    });
  }
}
