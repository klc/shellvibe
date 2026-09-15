import 'package:drift/drift.dart';
import '../app_database.dart';
import '../tables.dart';

part 'bookmarks_dao.g.dart';

@DriftAccessor(tables: [Bookmarks])
class BookmarksDao extends DatabaseAccessor<AppDatabase>
    with _$BookmarksDaoMixin {
  BookmarksDao(super.db);

  /// Bookmarks of [workspaceId] in the order they were added.
  Future<List<Bookmark>> getBookmarksByWorkspace(String workspaceId) {
    return (select(bookmarks)
          ..where((tbl) => tbl.workspaceId.equals(workspaceId))
          ..orderBy([
            (tbl) => OrderingTerm.asc(tbl.position),
            (tbl) => OrderingTerm.asc(tbl.createdAt),
          ]))
        .get();
  }

  Stream<List<Bookmark>> watchBookmarksByWorkspace(String workspaceId) {
    return (select(bookmarks)
          ..where((tbl) => tbl.workspaceId.equals(workspaceId))
          ..orderBy([
            (tbl) => OrderingTerm.asc(tbl.position),
            (tbl) => OrderingTerm.asc(tbl.createdAt),
          ]))
        .watch();
  }

  Future<Bookmark?> getBookmarkForHost(String hostId) {
    return (select(
      bookmarks,
    )..where((tbl) => tbl.hostId.equals(hostId))).getSingleOrNull();
  }

  Future<Bookmark?> getBookmarkForTemplate(String templateId) {
    return (select(
      bookmarks,
    )..where((tbl) => tbl.templateId.equals(templateId))).getSingleOrNull();
  }

  Future<int> insertBookmark(BookmarksCompanion bookmark) =>
      into(bookmarks).insert(bookmark);

  Future<int> deleteBookmark(String id) =>
      (delete(bookmarks)..where((tbl) => tbl.id.equals(id))).go();

  /// The position a new bookmark takes: last in the workspace's list.
  Future<int> nextPosition(String workspaceId) async {
    final highest = await (selectOnly(bookmarks)
          ..addColumns([bookmarks.position.max()])
          ..where(bookmarks.workspaceId.equals(workspaceId)))
        .getSingleOrNull();
    final current = highest?.read(bookmarks.position.max());
    return current == null ? 0 : current + 1;
  }
}
