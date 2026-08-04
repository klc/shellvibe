import 'package:drift/drift.dart';

import '../../../../shared/database/app_database.dart';
import '../../../../shared/database/daos/templates_dao.dart';
import '../../domain/models/template_model.dart';
import '../../domain/models/template_pane_model.dart';

class TemplatesRepository {
  final TemplatesDao _dao;

  TemplatesRepository(this._dao);

  Future<List<TemplateModel>> getAllTemplates() async {
    return _loadModels(await _dao.getAllTemplates());
  }

  Future<List<TemplateModel>> getTemplatesByWorkspace(
    String workspaceId,
  ) async {
    return _loadModels(await _dao.getTemplatesByWorkspace(workspaceId));
  }

  Future<TemplateModel?> getTemplate(String id) async {
    final rows = await _dao.getAllTemplates();
    final row = rows.where((t) => t.id == id).firstOrNull;
    if (row == null) return null;
    return _mapToModel(row, await _dao.getPanesForTemplate(row.id));
  }

  Future<List<TemplateModel>> _loadModels(List<Template> rows) async {
    final results = <TemplateModel>[];
    for (final row in rows) {
      final panes = await _dao.getPanesForTemplate(row.id);
      results.add(_mapToModel(row, panes));
    }
    return results;
  }

  Stream<List<TemplateModel>> watchAllTemplates() {
    return _dao.watchAllTemplates().asyncMap(_loadModels);
  }

  Future<void> addTemplate(TemplateModel template) async {
    await _dao.insertTemplate(
      TemplatesCompanion.insert(
        id: template.id,
        workspaceId: template.workspaceId,
        name: template.name,
        description: Value(template.description),
        activePaneId: Value(template.activePaneId),
        createdAt: template.createdAt,
      ),
    );
    await _dao.replacePanes(template.id, _paneCompanions(template));
  }

  Future<void> updateTemplate(TemplateModel template) async {
    await _dao.updateTemplate(
      TemplatesCompanion(
        id: Value(template.id),
        workspaceId: Value(template.workspaceId),
        name: Value(template.name),
        description: Value(template.description),
        activePaneId: Value(template.activePaneId),
        createdAt: Value(template.createdAt),
      ),
    );
    await _dao.replacePanes(template.id, _paneCompanions(template));
  }

  Future<void> deleteTemplate(String id) async {
    await _dao.deleteTemplate(id);
  }

  List<TemplatePanesCompanion> _paneCompanions(TemplateModel template) {
    return template.panes
        .map(
          (pane) => TemplatePanesCompanion.insert(
            id: pane.id,
            templateId: template.id,
            paneOrder: pane.paneOrder,
            parentPaneId: Value(pane.parentPaneId),
            splitDirection: Value(encodeSplitDirection(pane.splitDirection)),
            splitRatio: Value(pane.splitRatio),
            sessionType: encodeSessionType(pane.sessionType),
            hostId: Value(pane.hostId),
            title: Value(pane.title),
          ),
        )
        .toList();
  }

  TemplateModel _mapToModel(Template row, List<TemplatePane> panes) {
    return TemplateModel(
      id: row.id,
      workspaceId: row.workspaceId,
      name: row.name,
      description: row.description,
      activePaneId: row.activePaneId,
      createdAt: row.createdAt,
      panes: panes
          .map(
            (pane) => TemplatePaneModel(
              id: pane.id,
              templateId: pane.templateId,
              paneOrder: pane.paneOrder,
              parentPaneId: pane.parentPaneId,
              splitDirection: decodeSplitDirection(pane.splitDirection),
              splitRatio: pane.splitRatio,
              sessionType: decodeSessionType(pane.sessionType),
              hostId: pane.hostId,
              title: pane.title,
            ),
          )
          .toList(),
    );
  }
}
