// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'runbooks_notifier.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

@ProviderFor(runbooksRepository)
final runbooksRepositoryProvider = RunbooksRepositoryProvider._();

final class RunbooksRepositoryProvider
    extends
        $FunctionalProvider<
          RunbooksRepository,
          RunbooksRepository,
          RunbooksRepository
        >
    with $Provider<RunbooksRepository> {
  RunbooksRepositoryProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'runbooksRepositoryProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$runbooksRepositoryHash();

  @$internal
  @override
  $ProviderElement<RunbooksRepository> $createElement(
    $ProviderPointer pointer,
  ) => $ProviderElement(pointer);

  @override
  RunbooksRepository create(Ref ref) {
    return runbooksRepository(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(RunbooksRepository value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<RunbooksRepository>(value),
    );
  }
}

String _$runbooksRepositoryHash() =>
    r'd7ba2bcba52eec919e5705e24a718fd1b2cb460e';

@ProviderFor(RunbooksNotifier)
final runbooksProvider = RunbooksNotifierProvider._();

final class RunbooksNotifierProvider
    extends $AsyncNotifierProvider<RunbooksNotifier, List<RunbookModel>> {
  RunbooksNotifierProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'runbooksProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$runbooksNotifierHash();

  @$internal
  @override
  RunbooksNotifier create() => RunbooksNotifier();
}

String _$runbooksNotifierHash() => r'9c4db46f7f0ed22b00c8c5d2180e718a391b8f42';

abstract class _$RunbooksNotifier extends $AsyncNotifier<List<RunbookModel>> {
  FutureOr<List<RunbookModel>> build();
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref =
        this.ref as $Ref<AsyncValue<List<RunbookModel>>, List<RunbookModel>>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<AsyncValue<List<RunbookModel>>, List<RunbookModel>>,
              AsyncValue<List<RunbookModel>>,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, build);
  }
}
