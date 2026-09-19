import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../../core/sync/backup_scope.dart';
import '../../../../core/sync/backup_scope_store.dart';
import '../../../../shared/providers/database_providers.dart';

part 'backup_scope_notifier.g.dart';

/// What this device puts in a backup, for one [BackupTarget].
///
/// One notifier per target rather than one for all three: narrowing the file
/// backup says nothing about what the cloud vault should hold, and neither
/// says anything about what runs in the background.
@Riverpod(keepAlive: true)
class BackupScopeNotifier extends _$BackupScopeNotifier {
  BackupScopeStore get _store =>
      BackupScopeStore(storage: ref.read(secureStorageServiceProvider));

  @override
  Future<BackupScope> build(BackupTarget target) {
    ref.watch(secureStorageServiceProvider);

    return _store.read(target);
  }

  Future<void> set(BackupScope scope) async {
    await _store.write(target, scope);
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

/// Whether automatic sync runs on this device.
///
/// Separate from every scope: "sync in the background" and "carry hosts" are
/// different decisions, and folding them together would make turning the last
/// category off mean something it does not.
@Riverpod(keepAlive: true)
class AutoSyncEnabledNotifier extends _$AutoSyncEnabledNotifier {
  BackupScopeStore get _store =>
      BackupScopeStore(storage: ref.read(secureStorageServiceProvider));

  @override
  Future<bool> build() {
    ref.watch(secureStorageServiceProvider);

    return _store.readAutoSyncEnabled();
  }

  Future<void> set(bool enabled) async {
    await _store.writeAutoSyncEnabled(enabled);
    state = AsyncValue.data(enabled);
  }
}
