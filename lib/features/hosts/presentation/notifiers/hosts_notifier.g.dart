// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'hosts_notifier.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

@ProviderFor(hostsRepository)
final hostsRepositoryProvider = HostsRepositoryProvider._();

final class HostsRepositoryProvider
    extends
        $FunctionalProvider<HostsRepository, HostsRepository, HostsRepository>
    with $Provider<HostsRepository> {
  HostsRepositoryProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'hostsRepositoryProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$hostsRepositoryHash();

  @$internal
  @override
  $ProviderElement<HostsRepository> $createElement($ProviderPointer pointer) =>
      $ProviderElement(pointer);

  @override
  HostsRepository create(Ref ref) {
    return hostsRepository(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(HostsRepository value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<HostsRepository>(value),
    );
  }
}

String _$hostsRepositoryHash() => r'eb1ad318e8dd075d697339e5344112f17e4d95ad';

@ProviderFor(HostsNotifier)
final hostsProvider = HostsNotifierProvider._();

final class HostsNotifierProvider
    extends $AsyncNotifierProvider<HostsNotifier, List<HostModel>> {
  HostsNotifierProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'hostsProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$hostsNotifierHash();

  @$internal
  @override
  HostsNotifier create() => HostsNotifier();
}

String _$hostsNotifierHash() => r'612286aa89e91531f379b758c3dc162c80213832';

abstract class _$HostsNotifier extends $AsyncNotifier<List<HostModel>> {
  FutureOr<List<HostModel>> build();
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref = this.ref as $Ref<AsyncValue<List<HostModel>>, List<HostModel>>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<AsyncValue<List<HostModel>>, List<HostModel>>,
              AsyncValue<List<HostModel>>,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, build);
  }
}
