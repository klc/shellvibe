// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'cloud_backup_notifier.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// Drives the cloud backup surface.
///
/// Rebuilds when the account or the plan's limits change, so signing out
/// closes the feature without anything having to listen.

@ProviderFor(CloudBackupNotifier)
final cloudBackupProvider = CloudBackupNotifierProvider._();

/// Drives the cloud backup surface.
///
/// Rebuilds when the account or the plan's limits change, so signing out
/// closes the feature without anything having to listen.
final class CloudBackupNotifierProvider
    extends $AsyncNotifierProvider<CloudBackupNotifier, CloudBackupState> {
  /// Drives the cloud backup surface.
  ///
  /// Rebuilds when the account or the plan's limits change, so signing out
  /// closes the feature without anything having to listen.
  CloudBackupNotifierProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'cloudBackupProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$cloudBackupNotifierHash();

  @$internal
  @override
  CloudBackupNotifier create() => CloudBackupNotifier();
}

String _$cloudBackupNotifierHash() =>
    r'5aabb2936642c00021f0fd3bcdc90543aa6d1d05';

/// Drives the cloud backup surface.
///
/// Rebuilds when the account or the plan's limits change, so signing out
/// closes the feature without anything having to listen.

abstract class _$CloudBackupNotifier extends $AsyncNotifier<CloudBackupState> {
  FutureOr<CloudBackupState> build();
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref =
        this.ref as $Ref<AsyncValue<CloudBackupState>, CloudBackupState>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<AsyncValue<CloudBackupState>, CloudBackupState>,
              AsyncValue<CloudBackupState>,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, build);
  }
}
