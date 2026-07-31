import 'dart:convert';
import 'package:drift/drift.dart';

import '../../../../shared/database/app_database.dart';
import '../../../../shared/database/daos/snippets_dao.dart';
import '../../domain/models/snippet_model.dart';

class SnippetsRepository {
  final SnippetsDao _dao;

  SnippetsRepository(this._dao);

  Future<List<SnippetModel>> getAllSnippets() async {
    final rows = await _dao.getAllSnippets();
    return rows.map(_mapToModel).toList();
  }

  Future<List<SnippetModel>> getSnippetsByWorkspace(String workspaceId) async {
    final rows = await _dao.getSnippetsByWorkspace(workspaceId);
    return rows.map(_mapToModel).toList();
  }

  Stream<List<SnippetModel>> watchSnippetsByWorkspace(String workspaceId) {
    return _dao
        .watchSnippetsByWorkspace(workspaceId)
        .map((rows) => rows.map(_mapToModel).toList());
  }

  Future<void> addSnippet(SnippetModel snippet) async {
    final companion = SnippetsCompanion.insert(
      id: snippet.id,
      workspaceId: snippet.workspaceId,
      title: snippet.title,
      code: snippet.code,
      tags: Value(jsonEncode(snippet.tags)),
    );
    await _dao.insertSnippet(companion);
  }

  Future<void> updateSnippet(SnippetModel snippet) async {
    final companion = SnippetsCompanion(
      id: Value(snippet.id),
      workspaceId: Value(snippet.workspaceId),
      title: Value(snippet.title),
      code: Value(snippet.code),
      tags: Value(jsonEncode(snippet.tags)),
    );
    await _dao.updateSnippet(companion);
  }

  Future<void> deleteSnippet(String id) async {
    await _dao.deleteSnippet(id);
  }

  SnippetModel _mapToModel(Snippet row) {
    List<String> tags = [];
    if (row.tags != null && row.tags!.isNotEmpty) {
      try {
        final decoded = jsonDecode(row.tags!);
        if (decoded is List) {
          tags = decoded.map((e) => e.toString()).toList();
        }
      } catch (_) {}
    }
    return SnippetModel(
      id: row.id,
      workspaceId: row.workspaceId,
      title: row.title,
      code: row.code,
      tags: tags,
    );
  }
}
