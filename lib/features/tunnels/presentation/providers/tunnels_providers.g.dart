// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'tunnels_providers.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

String _$tunnelEngineHash() => r'7aa0beb251d42456ace1deeef18e015a6ab575c7';

/// Provider for [TunnelEngine]
///
/// Copied from [tunnelEngine].
@ProviderFor(tunnelEngine)
final tunnelEngineProvider = Provider<TunnelEngine>.internal(
  tunnelEngine,
  name: r'tunnelEngineProvider',
  debugGetCreateSourceHash: const bool.fromEnvironment('dart.vm.product')
      ? null
      : _$tunnelEngineHash,
  dependencies: null,
  allTransitiveDependencies: null,
);

@Deprecated('Will be removed in 3.0. Use Ref instead')
// ignore: unused_element
typedef TunnelEngineRef = ProviderRef<TunnelEngine>;
String _$activeTunnelsStreamHash() =>
    r'd2dacf7ab6f683021286c8aac57d138740c6f676';

/// Stream provider for active tunnels from [TunnelEngine]
///
/// Copied from [activeTunnelsStream].
@ProviderFor(activeTunnelsStream)
final activeTunnelsStreamProvider =
    AutoDisposeStreamProvider<List<ActiveTunnel>>.internal(
      activeTunnelsStream,
      name: r'activeTunnelsStreamProvider',
      debugGetCreateSourceHash: const bool.fromEnvironment('dart.vm.product')
          ? null
          : _$activeTunnelsStreamHash,
      dependencies: null,
      allTransitiveDependencies: null,
    );

@Deprecated('Will be removed in 3.0. Use Ref instead')
// ignore: unused_element
typedef ActiveTunnelsStreamRef =
    AutoDisposeStreamProviderRef<List<ActiveTunnel>>;
String _$tunnelsNotifierHash() => r'1b579c9fcfae5838c5c088a8e77d50d1773f64eb';

/// See also [TunnelsNotifier].
@ProviderFor(TunnelsNotifier)
final tunnelsNotifierProvider =
    AutoDisposeNotifierProvider<TunnelsNotifier, TunnelsState>.internal(
      TunnelsNotifier.new,
      name: r'tunnelsNotifierProvider',
      debugGetCreateSourceHash: const bool.fromEnvironment('dart.vm.product')
          ? null
          : _$tunnelsNotifierHash,
      dependencies: null,
      allTransitiveDependencies: null,
    );

typedef _$TunnelsNotifier = AutoDisposeNotifier<TunnelsState>;
// ignore_for_file: type=lint
// ignore_for_file: subtype_of_sealed_class, invalid_use_of_internal_member, invalid_use_of_visible_for_testing_member, deprecated_member_use_from_same_package
