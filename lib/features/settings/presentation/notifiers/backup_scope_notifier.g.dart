// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'backup_scope_notifier.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// What this device puts in a backup.
///
/// One preference for both backup paths: the encrypted file saved to disk and
/// the cloud vault. Splitting them would mean "what my backups contain" had
/// two answers, and the user would find out which was which at restore time.

@ProviderFor(BackupScopeNotifier)
final backupScopeProvider = BackupScopeNotifierProvider._();

/// What this device puts in a backup.
///
/// One preference for both backup paths: the encrypted file saved to disk and
/// the cloud vault. Splitting them would mean "what my backups contain" had
/// two answers, and the user would find out which was which at restore time.
final class BackupScopeNotifierProvider
    extends $AsyncNotifierProvider<BackupScopeNotifier, BackupScope> {
  /// What this device puts in a backup.
  ///
  /// One preference for both backup paths: the encrypted file saved to disk and
  /// the cloud vault. Splitting them would mean "what my backups contain" had
  /// two answers, and the user would find out which was which at restore time.
  BackupScopeNotifierProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'backupScopeProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$backupScopeNotifierHash();

  @$internal
  @override
  BackupScopeNotifier create() => BackupScopeNotifier();
}

String _$backupScopeNotifierHash() =>
    r'bc8a6c61051f9cc3867e9c075a0ee9e5d68e5c27';

/// What this device puts in a backup.
///
/// One preference for both backup paths: the encrypted file saved to disk and
/// the cloud vault. Splitting them would mean "what my backups contain" had
/// two answers, and the user would find out which was which at restore time.

abstract class _$BackupScopeNotifier extends $AsyncNotifier<BackupScope> {
  FutureOr<BackupScope> build();
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref = this.ref as $Ref<AsyncValue<BackupScope>, BackupScope>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<AsyncValue<BackupScope>, BackupScope>,
              AsyncValue<BackupScope>,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, build);
  }
}
