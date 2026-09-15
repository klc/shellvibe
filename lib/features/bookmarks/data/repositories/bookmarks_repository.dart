import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import '../../../../shared/database/app_database.dart';
import '../../../../shared/database/daos/bookmarks_dao.dart';
import '../../domain/models/bookmark_model.dart';

class BookmarksRepository {
  final BookmarksDao bookmarksDao;

  BookmarksRepository({required this.bookmarksDao});

  Future<List<BookmarkModel>> getBookmarks(String workspaceId) async {
    final rows = await bookmarksDao.getBookmarksByWorkspace(workspaceId);
    return rows.map(_toModel).toList();
  }

  /// Stars [hostId], or does nothing if it already is. Returns the bookmark
  /// either way, so a caller need not care which happened.
  Future<BookmarkModel> addHost({
    required String workspaceId,
    required String hostId,
  }) async {
    final existing = await bookmarksDao.getBookmarkForHost(hostId);
    if (existing != null) return _toModel(existing);
    return _insert(workspaceId: workspaceId, hostId: hostId);
  }

  Future<BookmarkModel> addTemplate({
    required String workspaceId,
    required String templateId,
  }) async {
    final existing = await bookmarksDao.getBookmarkForTemplate(templateId);
    if (existing != null) return _toModel(existing);
    return _insert(workspaceId: workspaceId, templateId: templateId);
  }

  Future<void> removeForHost(String hostId) async {
    final existing = await bookmarksDao.getBookmarkForHost(hostId);
    if (existing == null) return;
    await bookmarksDao.deleteBookmark(existing.id);
  }

  Future<void> removeForTemplate(String templateId) async {
    final existing = await bookmarksDao.getBookmarkForTemplate(templateId);
    if (existing == null) return;
    await bookmarksDao.deleteBookmark(existing.id);
  }

  Future<BookmarkModel> _insert({
    required String workspaceId,
    String? hostId,
    String? templateId,
  }) async {
    final id = const Uuid().v4();
    final position = await bookmarksDao.nextPosition(workspaceId);
    final createdAt = DateTime.now();
    await bookmarksDao.insertBookmark(
      BookmarksCompanion(
        id: Value(id),
        workspaceId: Value(workspaceId),
        hostId: Value<String?>(hostId),
        templateId: Value<String?>(templateId),
        position: Value(position),
        createdAt: Value(createdAt),
      ),
    );
    return BookmarkModel(
      id: id,
      workspaceId: workspaceId,
      hostId: hostId,
      templateId: templateId,
      position: position,
      createdAt: createdAt,
    );
  }

  BookmarkModel _toModel(Bookmark row) {
    return BookmarkModel(
      id: row.id,
      workspaceId: row.workspaceId,
      hostId: row.hostId,
      templateId: row.templateId,
      position: row.position,
      createdAt: row.createdAt,
    );
  }
}
