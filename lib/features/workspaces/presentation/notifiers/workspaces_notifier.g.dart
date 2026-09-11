// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'workspaces_notifier.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

@ProviderFor(workspaceRepository)
final workspaceRepositoryProvider = WorkspaceRepositoryProvider._();

final class WorkspaceRepositoryProvider
    extends
        $FunctionalProvider<
          WorkspaceRepository,
          WorkspaceRepository,
          WorkspaceRepository
        >
    with $Provider<WorkspaceRepository> {
  WorkspaceRepositoryProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'workspaceRepositoryProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$workspaceRepositoryHash();

  @$internal
  @override
  $ProviderElement<WorkspaceRepository> $createElement(
    $ProviderPointer pointer,
  ) => $ProviderElement(pointer);

  @override
  WorkspaceRepository create(Ref ref) {
    return workspaceRepository(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(WorkspaceRepository value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<WorkspaceRepository>(value),
    );
  }
}

String _$workspaceRepositoryHash() =>
    r'9854660eeae4f561f47bccc16a13a849f9ec5e24';

/// Must be [Riverpod(keepAlive: true)]: every call site only does
/// `ref.read(...notifier)`, never `watch`, so with autoDispose this has
/// zero listeners and gets torn down mid-`await`, leaving `create`/`rename`/
/// `delete` mutating a disposed ref.

@ProviderFor(WorkspaceManagerNotifier)
final workspaceManagerProvider = WorkspaceManagerNotifierProvider._();

/// Must be [Riverpod(keepAlive: true)]: every call site only does
/// `ref.read(...notifier)`, never `watch`, so with autoDispose this has
/// zero listeners and gets torn down mid-`await`, leaving `create`/`rename`/
/// `delete` mutating a disposed ref.
final class WorkspaceManagerNotifierProvider
    extends
        $AsyncNotifierProvider<WorkspaceManagerNotifier, List<WorkspaceModel>> {
  /// Must be [Riverpod(keepAlive: true)]: every call site only does
  /// `ref.read(...notifier)`, never `watch`, so with autoDispose this has
  /// zero listeners and gets torn down mid-`await`, leaving `create`/`rename`/
  /// `delete` mutating a disposed ref.
  WorkspaceManagerNotifierProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'workspaceManagerProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$workspaceManagerNotifierHash();

  @$internal
  @override
  WorkspaceManagerNotifier create() => WorkspaceManagerNotifier();
}

String _$workspaceManagerNotifierHash() =>
    r'd30962aaf4e0ba1c42ea5d3e96147b08e373bfe7';

/// Must be [Riverpod(keepAlive: true)]: every call site only does
/// `ref.read(...notifier)`, never `watch`, so with autoDispose this has
/// zero listeners and gets torn down mid-`await`, leaving `create`/`rename`/
/// `delete` mutating a disposed ref.

abstract class _$WorkspaceManagerNotifier
    extends $AsyncNotifier<List<WorkspaceModel>> {
  FutureOr<List<WorkspaceModel>> build();
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref =
        this.ref
            as $Ref<AsyncValue<List<WorkspaceModel>>, List<WorkspaceModel>>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<
                AsyncValue<List<WorkspaceModel>>,
                List<WorkspaceModel>
              >,
              AsyncValue<List<WorkspaceModel>>,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, build);
  }
}
