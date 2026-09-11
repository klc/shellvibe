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

  Future<int> insertTemplate(TemplatesCompanion template) =>
      into(templates).insert(template);

  Future<bool> updateTemplate(TemplatesCompanion template) =>
      update(templates).replace(template);

  Future<int> deleteTemplate(String id) async {
    await (delete(
      templatePanes,
    )..where((tbl) => tbl.templateId.equals(id))).go();
    return (delete(templates)..where((tbl) => tbl.id.equals(id))).go();
  }

  Future<void> replacePanes(
    String templateId,
    List<TemplatePanesCompanion> panes,
  ) async {
    await transaction(() async {
      await (delete(
        templatePanes,
      )..where((tbl) => tbl.templateId.equals(templateId))).go();
      for (final pane in panes) {
        await into(templatePanes).insert(pane);
      }
    });
  }
}
