// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'backup_scope_notifier.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// What this device puts in a backup, for one [BackupTarget].
///
/// One notifier per target rather than one for all three: narrowing the file
/// backup says nothing about what the cloud vault should hold, and neither
/// says anything about what runs in the background.

@ProviderFor(BackupScopeNotifier)
final backupScopeProvider = BackupScopeNotifierFamily._();

/// What this device puts in a backup, for one [BackupTarget].
///
/// One notifier per target rather than one for all three: narrowing the file
/// backup says nothing about what the cloud vault should hold, and neither
/// says anything about what runs in the background.
final class BackupScopeNotifierProvider
    extends $AsyncNotifierProvider<BackupScopeNotifier, BackupScope> {
  /// What this device puts in a backup, for one [BackupTarget].
  ///
  /// One notifier per target rather than one for all three: narrowing the file
  /// backup says nothing about what the cloud vault should hold, and neither
  /// says anything about what runs in the background.
  BackupScopeNotifierProvider._({
    required BackupScopeNotifierFamily super.from,
    required BackupTarget super.argument,
  }) : super(
         retry: null,
         name: r'backupScopeProvider',
         isAutoDispose: false,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$backupScopeNotifierHash();

  @override
  String toString() {
    return r'backupScopeProvider'
        ''
        '($argument)';
  }

  @$internal
  @override
  BackupScopeNotifier create() => BackupScopeNotifier();

  @override
  bool operator ==(Object other) {
    return other is BackupScopeNotifierProvider && other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$backupScopeNotifierHash() =>
    r'd99bc6fae4539f89a21a4b0ed96b376354628a4b';

/// What this device puts in a backup, for one [BackupTarget].
///
/// One notifier per target rather than one for all three: narrowing the file
/// backup says nothing about what the cloud vault should hold, and neither
/// says anything about what runs in the background.

final class BackupScopeNotifierFamily extends $Family
    with
        $ClassFamilyOverride<
          BackupScopeNotifier,
          AsyncValue<BackupScope>,
          BackupScope,
          FutureOr<BackupScope>,
          BackupTarget
        > {
  BackupScopeNotifierFamily._()
    : super(
        retry: null,
        name: r'backupScopeProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: false,
      );

  /// What this device puts in a backup, for one [BackupTarget].
  ///
  /// One notifier per target rather than one for all three: narrowing the file
  /// backup says nothing about what the cloud vault should hold, and neither
  /// says anything about what runs in the background.

  BackupScopeNotifierProvider call(BackupTarget target) =>
      BackupScopeNotifierProvider._(argument: target, from: this);

  @override
  String toString() => r'backupScopeProvider';
}

/// What this device puts in a backup, for one [BackupTarget].
///
/// One notifier per target rather than one for all three: narrowing the file
/// backup says nothing about what the cloud vault should hold, and neither
/// says anything about what runs in the background.

abstract class _$BackupScopeNotifier extends $AsyncNotifier<BackupScope> {
  late final _$args = ref.$arg as BackupTarget;
  BackupTarget get target => _$args;

  FutureOr<BackupScope> build(BackupTarget target);
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
    return element.handleCreate(ref, () => build(_$args));
  }
}

/// Whether automatic sync runs on this device.
///
/// Separate from every scope: "sync in the background" and "carry hosts" are
/// different decisions, and folding them together would make turning the last
/// category off mean something it does not.

@ProviderFor(AutoSyncEnabledNotifier)
final autoSyncEnabledProvider = AutoSyncEnabledNotifierProvider._();

/// Whether automatic sync runs on this device.
///
/// Separate from every scope: "sync in the background" and "carry hosts" are
/// different decisions, and folding them together would make turning the last
/// category off mean something it does not.
final class AutoSyncEnabledNotifierProvider
    extends $AsyncNotifierProvider<AutoSyncEnabledNotifier, bool> {
  /// Whether automatic sync runs on this device.
  ///
  /// Separate from every scope: "sync in the background" and "carry hosts" are
  /// different decisions, and folding them together would make turning the last
  /// category off mean something it does not.
  AutoSyncEnabledNotifierProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'autoSyncEnabledProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$autoSyncEnabledNotifierHash();

  @$internal
  @override
  AutoSyncEnabledNotifier create() => AutoSyncEnabledNotifier();
}

String _$autoSyncEnabledNotifierHash() =>
    r'df56f221d22931a0f1e57d5437162a8b444ae7cb';

/// Whether automatic sync runs on this device.
///
/// Separate from every scope: "sync in the background" and "carry hosts" are
/// different decisions, and folding them together would make turning the last
/// category off mean something it does not.

abstract class _$AutoSyncEnabledNotifier extends $AsyncNotifier<bool> {
  FutureOr<bool> build();
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref = this.ref as $Ref<AsyncValue<bool>, bool>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<AsyncValue<bool>, bool>,
              AsyncValue<bool>,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, build);
  }
}
