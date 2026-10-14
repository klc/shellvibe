import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:uuid/uuid.dart';

import '../../../../shared/providers/database_providers.dart';
import '../../../workspaces/presentation/providers/workspace_provider.dart';
import '../../data/repositories/snippets_repository.dart';
import '../../domain/models/snippet_model.dart';
import '../../domain/models/variable_declaration.dart';

part 'snippets_notifier.g.dart';

@riverpod
SnippetsRepository snippetsRepository(Ref ref) {
  final dao = ref.watch(snippetsDaoProvider);
  return SnippetsRepository(dao);
}

@riverpod
class SnippetsNotifier extends _$SnippetsNotifier {
  @override
  Future<List<SnippetModel>> build() async {
    final repo = ref.watch(snippetsRepositoryProvider);
    return await repo.getSnippetsByWorkspace(
      ref.watch(activeWorkspaceIdProvider),
    );
  }

  /// Runs [op], then reloads the list in place: an add, edit or delete must
  /// not blank the list to a spinner on the way through.
  Future<void> _mutate(Future<void> Function() op) async {
    state = await AsyncValue.guard(() async {
      await op();
      return ref
          .read(snippetsRepositoryProvider)
          .getSnippetsByWorkspace(ref.read(activeWorkspaceIdProvider));
    });
  }

  Future<void> addSnippet({
    required String workspaceId,
    required String title,
    required String code,
    List<String> tags = const [],
    List<VariableDeclaration> variables = const [],
  }) => _mutate(
    () => ref
        .read(snippetsRepositoryProvider)
        .addSnippet(
          SnippetModel(
            id: const Uuid().v4(),
            workspaceId: workspaceId,
            title: title,
            code: code,
            tags: tags,
            variables: variables,
          ),
        ),
  );

  Future<void> updateSnippet(SnippetModel snippet) => _mutate(
    () => ref.read(snippetsRepositoryProvider).updateSnippet(snippet),
  );

  Future<void> deleteSnippet(String id) =>
      _mutate(() => ref.read(snippetsRepositoryProvider).deleteSnippet(id));
}
