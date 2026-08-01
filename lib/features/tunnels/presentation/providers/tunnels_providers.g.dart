// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'tunnels_providers.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// Provider for [TunnelRepository]

@ProviderFor(tunnelRepository)
final tunnelRepositoryProvider = TunnelRepositoryProvider._();

/// Provider for [TunnelRepository]

final class TunnelRepositoryProvider
    extends
        $FunctionalProvider<
          TunnelRepository,
          TunnelRepository,
          TunnelRepository
        >
    with $Provider<TunnelRepository> {
  /// Provider for [TunnelRepository]
  TunnelRepositoryProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'tunnelRepositoryProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$tunnelRepositoryHash();

  @$internal
  @override
  $ProviderElement<TunnelRepository> $createElement($ProviderPointer pointer) =>
      $ProviderElement(pointer);

  @override
  TunnelRepository create(Ref ref) {
    return tunnelRepository(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(TunnelRepository value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<TunnelRepository>(value),
    );
  }
}

String _$tunnelRepositoryHash() => r'0015025dc51e3be2433739fd7b65f4ce7f460d13';

/// Provider for [TunnelEngine]

@ProviderFor(tunnelEngine)
final tunnelEngineProvider = TunnelEngineProvider._();

/// Provider for [TunnelEngine]

final class TunnelEngineProvider
    extends $FunctionalProvider<TunnelEngine, TunnelEngine, TunnelEngine>
    with $Provider<TunnelEngine> {
  /// Provider for [TunnelEngine]
  TunnelEngineProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'tunnelEngineProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$tunnelEngineHash();

  @$internal
  @override
  $ProviderElement<TunnelEngine> $createElement($ProviderPointer pointer) =>
      $ProviderElement(pointer);

  @override
  TunnelEngine create(Ref ref) {
    return tunnelEngine(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(TunnelEngine value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<TunnelEngine>(value),
    );
  }
}

String _$tunnelEngineHash() => r'7aa0beb251d42456ace1deeef18e015a6ab575c7';

/// Stream provider for active tunnels from [TunnelEngine]

@ProviderFor(activeTunnelsStream)
final activeTunnelsStreamProvider = ActiveTunnelsStreamProvider._();

/// Stream provider for active tunnels from [TunnelEngine]

final class ActiveTunnelsStreamProvider
    extends
        $FunctionalProvider<
          AsyncValue<List<ActiveTunnel>>,
          List<ActiveTunnel>,
          Stream<List<ActiveTunnel>>
        >
    with
        $FutureModifier<List<ActiveTunnel>>,
        $StreamProvider<List<ActiveTunnel>> {
  /// Stream provider for active tunnels from [TunnelEngine]
  ActiveTunnelsStreamProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'activeTunnelsStreamProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$activeTunnelsStreamHash();

  @$internal
  @override
  $StreamProviderElement<List<ActiveTunnel>> $createElement(
    $ProviderPointer pointer,
  ) => $StreamProviderElement(pointer);

  @override
  Stream<List<ActiveTunnel>> create(Ref ref) {
    return activeTunnelsStream(ref);
  }
}

String _$activeTunnelsStreamHash() =>
    r'd2dacf7ab6f683021286c8aac57d138740c6f676';

@ProviderFor(TunnelsNotifier)
final tunnelsProvider = TunnelsNotifierProvider._();

final class TunnelsNotifierProvider
    extends $NotifierProvider<TunnelsNotifier, TunnelsState> {
  TunnelsNotifierProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'tunnelsProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$tunnelsNotifierHash();

  @$internal
  @override
  TunnelsNotifier create() => TunnelsNotifier();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(TunnelsState value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<TunnelsState>(value),
    );
  }
}

String _$tunnelsNotifierHash() => r'7357fec4d91437f6afd1aba639d3636768901233';

abstract class _$TunnelsNotifier extends $Notifier<TunnelsState> {
  TunnelsState build();
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref = this.ref as $Ref<TunnelsState, TunnelsState>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<TunnelsState, TunnelsState>,
              TunnelsState,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, build);
  }
}
