// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'snippets_notifier.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

@ProviderFor(snippetsRepository)
final snippetsRepositoryProvider = SnippetsRepositoryProvider._();

final class SnippetsRepositoryProvider
    extends
        $FunctionalProvider<
          SnippetsRepository,
          SnippetsRepository,
          SnippetsRepository
        >
    with $Provider<SnippetsRepository> {
  SnippetsRepositoryProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'snippetsRepositoryProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$snippetsRepositoryHash();

  @$internal
  @override
  $ProviderElement<SnippetsRepository> $createElement(
    $ProviderPointer pointer,
  ) => $ProviderElement(pointer);

  @override
  SnippetsRepository create(Ref ref) {
    return snippetsRepository(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(SnippetsRepository value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<SnippetsRepository>(value),
    );
  }
}

String _$snippetsRepositoryHash() =>
    r'1b0226fba9a47337b60d6bd0dd00677d3e34a974';

@ProviderFor(SnippetsNotifier)
final snippetsProvider = SnippetsNotifierProvider._();

final class SnippetsNotifierProvider
    extends $AsyncNotifierProvider<SnippetsNotifier, List<SnippetModel>> {
  SnippetsNotifierProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'snippetsProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$snippetsNotifierHash();

  @$internal
  @override
  SnippetsNotifier create() => SnippetsNotifier();
}

String _$snippetsNotifierHash() => r'5d3a95fd239a8af3fd6af1bc98d7485c4ef41408';

abstract class _$SnippetsNotifier extends $AsyncNotifier<List<SnippetModel>> {
  FutureOr<List<SnippetModel>> build();
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref =
        this.ref as $Ref<AsyncValue<List<SnippetModel>>, List<SnippetModel>>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<AsyncValue<List<SnippetModel>>, List<SnippetModel>>,
              AsyncValue<List<SnippetModel>>,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, build);
  }
}
