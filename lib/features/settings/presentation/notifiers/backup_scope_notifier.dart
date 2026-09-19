import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../../core/sync/backup_scope.dart';
import '../../../../core/sync/backup_scope_store.dart';
import '../../../../shared/providers/database_providers.dart';

part 'backup_scope_notifier.g.dart';

/// What this device puts in a backup.
///
/// One preference for both backup paths: the encrypted file saved to disk and
/// the cloud vault. Splitting them would mean "what my backups contain" had
/// two answers, and the user would find out which was which at restore time.
@Riverpod(keepAlive: true)
class BackupScopeNotifier extends _$BackupScopeNotifier {
  BackupScopeStore get _store =>
      BackupScopeStore(storage: ref.read(secureStorageServiceProvider));

  @override
  Future<BackupScope> build() {
    ref.watch(secureStorageServiceProvider);

    return _store.read();
  }

  Future<void> set(BackupScope scope) async {
    await _store.write(scope);
    state = AsyncValue.data(scope);
  }

  /// Turns one category on or off, keeping the selection consistent.
  ///
  /// Turning off a category another one requires turns that one off too: a
  /// port forward row cannot exist without its host, so leaving it selected
  /// would only produce a backup whose rows are dropped on the way in.
  Future<void> toggle(BackupCategory category, bool selected) async {
    final current = state.value ?? BackupScope.full;
    final categories = {...current.categories};

    if (selected) {
      categories.add(category);
    } else {
      categories.remove(category);
      categories.removeWhere((c) => kBackupCategoryRequires[c] == category);
    }

    await set(BackupScope.of(categories));
  }
}
