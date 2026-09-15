import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../../shared/providers/database_providers.dart';
import '../../../../shared/providers/workspace_provider.dart';
import '../../data/repositories/bookmarks_repository.dart';
import '../../domain/models/bookmark_model.dart';

part 'bookmarks_notifier.g.dart';

@riverpod
BookmarksRepository bookmarksRepository(Ref ref) {
  final dao = ref.watch(bookmarksDaoProvider);
  return BookmarksRepository(bookmarksDao: dao);
}

@riverpod
class BookmarksNotifier extends _$BookmarksNotifier {
  @override
  Future<List<BookmarkModel>> build() async {
    final repo = ref.watch(bookmarksRepositoryProvider);
    final workspaceId = ref.watch(activeWorkspaceIdProvider);
    return repo.getBookmarks(workspaceId);
  }

  /// Stars [hostId] if it is not starred, unstars it if it is.
  ///
  /// The toggle is one call because that is what the star in the host row does;
  /// asking the caller to read the current state first would let two taps in
  /// quick succession decide from the same stale answer.
  Future<void> toggleHost(String hostId) async {
    final repo = ref.read(bookmarksRepositoryProvider);
    final workspaceId = ref.read(activeWorkspaceIdProvider);
    if (isHostBookmarked(hostId)) {
      await repo.removeForHost(hostId);
    } else {
      await repo.addHost(workspaceId: workspaceId, hostId: hostId);
    }
    await _refresh(repo, workspaceId);
  }

  Future<void> toggleTemplate(String templateId) async {
    final repo = ref.read(bookmarksRepositoryProvider);
    final workspaceId = ref.read(activeWorkspaceIdProvider);
    if (isTemplateBookmarked(templateId)) {
      await repo.removeForTemplate(templateId);
    } else {
      await repo.addTemplate(workspaceId: workspaceId, templateId: templateId);
    }
    await _refresh(repo, workspaceId);
  }

  bool isHostBookmarked(String hostId) {
    return state.value?.any((b) => b.hostId == hostId) ?? false;
  }

  bool isTemplateBookmarked(String templateId) {
    return state.value?.any((b) => b.templateId == templateId) ?? false;
  }

  Future<void> _refresh(
    BookmarksRepository repo,
    String workspaceId,
  ) async {
    state = AsyncValue.data(await repo.getBookmarks(workspaceId));
  }
}
