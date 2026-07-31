import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:uuid/uuid.dart';

import '../../../../shared/providers/database_providers.dart';
import '../../data/repositories/snippets_repository.dart';
import '../../domain/models/snippet_model.dart';

part 'snippets_notifier.g.dart';

@riverpod
SnippetsRepository snippetsRepository(SnippetsRepositoryRef ref) {
  final dao = ref.watch(snippetsDaoProvider);
  return SnippetsRepository(dao);
}

@riverpod
class SnippetsNotifier extends _$SnippetsNotifier {
  @override
  Future<List<SnippetModel>> build() async {
    final repo = ref.watch(snippetsRepositoryProvider);
    return await repo.getAllSnippets();
  }

  Future<void> addSnippet({
    required String workspaceId,
    required String title,
    required String code,
    List<String> tags = const [],
  }) async {
    state = const AsyncValue.loading();
    state = await AsyncValue.guard(() async {
      final repo = ref.read(snippetsRepositoryProvider);
      final snippet = SnippetModel(
        id: const Uuid().v4(),
        workspaceId: workspaceId,
        title: title,
        code: code,
        tags: tags,
      );
      await repo.addSnippet(snippet);
      return await repo.getAllSnippets();
    });
  }

  Future<void> updateSnippet(SnippetModel snippet) async {
    state = const AsyncValue.loading();
    state = await AsyncValue.guard(() async {
      final repo = ref.read(snippetsRepositoryProvider);
      await repo.updateSnippet(snippet);
      return await repo.getAllSnippets();
    });
  }

  Future<void> deleteSnippet(String id) async {
    state = const AsyncValue.loading();
    state = await AsyncValue.guard(() async {
      final repo = ref.read(snippetsRepositoryProvider);
      await repo.deleteSnippet(id);
      return await repo.getAllSnippets();
    });
  }
}
