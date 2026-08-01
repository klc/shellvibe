// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'network_providers.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

String _$sshSessionManagerHash() => r'da3af5bfd09b4df5470b875700e0ce3671cb8c64';

/// Provider for [SSHSessionManager].
/// Note: [TerminalTabSession] instances instantiate dedicated [SSHSessionManager]
/// instances per connection to ensure tabs do not share SSH clients/sockets.
///
/// Copied from [sshSessionManager].
@ProviderFor(sshSessionManager)
final sshSessionManagerProvider =
    AutoDisposeProvider<SSHSessionManager>.internal(
      sshSessionManager,
      name: r'sshSessionManagerProvider',
      debugGetCreateSourceHash: const bool.fromEnvironment('dart.vm.product')
          ? null
          : _$sshSessionManagerHash,
      dependencies: null,
      allTransitiveDependencies: null,
    );

@Deprecated('Will be removed in 3.0. Use Ref instead')
// ignore: unused_element
typedef SshSessionManagerRef = AutoDisposeProviderRef<SSHSessionManager>;
String _$localPtyManagerHash() => r'6f94bf8a4b43f26d026679b597c932f75e826765';

/// Auto-disposing provider for [LocalPtyManager].
///
/// Copied from [localPtyManager].
@ProviderFor(localPtyManager)
final localPtyManagerProvider = AutoDisposeProvider<LocalPtyManager>.internal(
  localPtyManager,
  name: r'localPtyManagerProvider',
  debugGetCreateSourceHash: const bool.fromEnvironment('dart.vm.product')
      ? null
      : _$localPtyManagerHash,
  dependencies: null,
  allTransitiveDependencies: null,
);

@Deprecated('Will be removed in 3.0. Use Ref instead')
// ignore: unused_element
typedef LocalPtyManagerRef = AutoDisposeProviderRef<LocalPtyManager>;
String _$terminalSSHBridgeHash() => r'be164f244f445ec4e06c6be9c01f70f39d8c49e1';

/// Copied from Dart SDK
class _SystemHash {
  _SystemHash._();

  static int combine(int hash, int value) {
    // ignore: parameter_assignments
    hash = 0x1fffffff & (hash + value);
    // ignore: parameter_assignments
    hash = 0x1fffffff & (hash + ((0x0007ffff & hash) << 10));
    return hash ^ (hash >> 6);
  }

  static int finish(int hash) {
    // ignore: parameter_assignments
    hash = 0x1fffffff & (hash + ((0x03ffffff & hash) << 3));
    // ignore: parameter_assignments
    hash = hash ^ (hash >> 11);
    return 0x1fffffff & (hash + ((0x00003fff & hash) << 15));
  }
}

/// Auto-disposing family provider for [TerminalSSHBridge].
/// Cleanly disposes stream subscriptions and session resources when disposed.
///
/// Copied from [terminalSSHBridge].
@ProviderFor(terminalSSHBridge)
const terminalSSHBridgeProvider = TerminalSSHBridgeFamily();

/// Auto-disposing family provider for [TerminalSSHBridge].
/// Cleanly disposes stream subscriptions and session resources when disposed.
///
/// Copied from [terminalSSHBridge].
class TerminalSSHBridgeFamily extends Family<TerminalSSHBridge> {
  /// Auto-disposing family provider for [TerminalSSHBridge].
  /// Cleanly disposes stream subscriptions and session resources when disposed.
  ///
  /// Copied from [terminalSSHBridge].
  const TerminalSSHBridgeFamily();

  /// Auto-disposing family provider for [TerminalSSHBridge].
  /// Cleanly disposes stream subscriptions and session resources when disposed.
  ///
  /// Copied from [terminalSSHBridge].
  TerminalSSHBridgeProvider call(TerminalSSHBridgeParams params) {
    return TerminalSSHBridgeProvider(params);
  }

  @override
  TerminalSSHBridgeProvider getProviderOverride(
    covariant TerminalSSHBridgeProvider provider,
  ) {
    return call(provider.params);
  }

  static const Iterable<ProviderOrFamily>? _dependencies = null;

  @override
  Iterable<ProviderOrFamily>? get dependencies => _dependencies;

  static const Iterable<ProviderOrFamily>? _allTransitiveDependencies = null;

  @override
  Iterable<ProviderOrFamily>? get allTransitiveDependencies =>
      _allTransitiveDependencies;

  @override
  String? get name => r'terminalSSHBridgeProvider';
}

/// Auto-disposing family provider for [TerminalSSHBridge].
/// Cleanly disposes stream subscriptions and session resources when disposed.
///
/// Copied from [terminalSSHBridge].
class TerminalSSHBridgeProvider extends AutoDisposeProvider<TerminalSSHBridge> {
  /// Auto-disposing family provider for [TerminalSSHBridge].
  /// Cleanly disposes stream subscriptions and session resources when disposed.
  ///
  /// Copied from [terminalSSHBridge].
  TerminalSSHBridgeProvider(TerminalSSHBridgeParams params)
    : this._internal(
        (ref) => terminalSSHBridge(ref as TerminalSSHBridgeRef, params),
        from: terminalSSHBridgeProvider,
        name: r'terminalSSHBridgeProvider',
        debugGetCreateSourceHash: const bool.fromEnvironment('dart.vm.product')
            ? null
            : _$terminalSSHBridgeHash,
        dependencies: TerminalSSHBridgeFamily._dependencies,
        allTransitiveDependencies:
            TerminalSSHBridgeFamily._allTransitiveDependencies,
        params: params,
      );

  TerminalSSHBridgeProvider._internal(
    super._createNotifier, {
    required super.name,
    required super.dependencies,
    required super.allTransitiveDependencies,
    required super.debugGetCreateSourceHash,
    required super.from,
    required this.params,
  }) : super.internal();

  final TerminalSSHBridgeParams params;

  @override
  Override overrideWith(
    TerminalSSHBridge Function(TerminalSSHBridgeRef provider) create,
  ) {
    return ProviderOverride(
      origin: this,
      override: TerminalSSHBridgeProvider._internal(
        (ref) => create(ref as TerminalSSHBridgeRef),
        from: from,
        name: null,
        dependencies: null,
        allTransitiveDependencies: null,
        debugGetCreateSourceHash: null,
        params: params,
      ),
    );
  }

  @override
  AutoDisposeProviderElement<TerminalSSHBridge> createElement() {
    return _TerminalSSHBridgeProviderElement(this);
  }

  @override
  bool operator ==(Object other) {
    return other is TerminalSSHBridgeProvider && other.params == params;
  }

  @override
  int get hashCode {
    var hash = _SystemHash.combine(0, runtimeType.hashCode);
    hash = _SystemHash.combine(hash, params.hashCode);

    return _SystemHash.finish(hash);
  }
}

@Deprecated('Will be removed in 3.0. Use Ref instead')
// ignore: unused_element
mixin TerminalSSHBridgeRef on AutoDisposeProviderRef<TerminalSSHBridge> {
  /// The parameter `params` of this provider.
  TerminalSSHBridgeParams get params;
}

class _TerminalSSHBridgeProviderElement
    extends AutoDisposeProviderElement<TerminalSSHBridge>
    with TerminalSSHBridgeRef {
  _TerminalSSHBridgeProviderElement(super.provider);

  @override
  TerminalSSHBridgeParams get params =>
      (origin as TerminalSSHBridgeProvider).params;
}

String _$terminalPtyBridgeHash() => r'2e1b05c481c71f813ebb77db82651370c3eb9b4e';

/// Auto-disposing family provider for [TerminalLocalPtyBridge].
/// Cleanly disposes PTY stream subscriptions and process resources when disposed.
///
/// Copied from [terminalPtyBridge].
@ProviderFor(terminalPtyBridge)
const terminalPtyBridgeProvider = TerminalPtyBridgeFamily();

/// Auto-disposing family provider for [TerminalLocalPtyBridge].
/// Cleanly disposes PTY stream subscriptions and process resources when disposed.
///
/// Copied from [terminalPtyBridge].
class TerminalPtyBridgeFamily extends Family<TerminalLocalPtyBridge> {
  /// Auto-disposing family provider for [TerminalLocalPtyBridge].
  /// Cleanly disposes PTY stream subscriptions and process resources when disposed.
  ///
  /// Copied from [terminalPtyBridge].
  const TerminalPtyBridgeFamily();

  /// Auto-disposing family provider for [TerminalLocalPtyBridge].
  /// Cleanly disposes PTY stream subscriptions and process resources when disposed.
  ///
  /// Copied from [terminalPtyBridge].
  TerminalPtyBridgeProvider call(TerminalPtyBridgeParams params) {
    return TerminalPtyBridgeProvider(params);
  }

  @override
  TerminalPtyBridgeProvider getProviderOverride(
    covariant TerminalPtyBridgeProvider provider,
  ) {
    return call(provider.params);
  }

  static const Iterable<ProviderOrFamily>? _dependencies = null;

  @override
  Iterable<ProviderOrFamily>? get dependencies => _dependencies;

  static const Iterable<ProviderOrFamily>? _allTransitiveDependencies = null;

  @override
  Iterable<ProviderOrFamily>? get allTransitiveDependencies =>
      _allTransitiveDependencies;

  @override
  String? get name => r'terminalPtyBridgeProvider';
}

/// Auto-disposing family provider for [TerminalLocalPtyBridge].
/// Cleanly disposes PTY stream subscriptions and process resources when disposed.
///
/// Copied from [terminalPtyBridge].
class TerminalPtyBridgeProvider
    extends AutoDisposeProvider<TerminalLocalPtyBridge> {
  /// Auto-disposing family provider for [TerminalLocalPtyBridge].
  /// Cleanly disposes PTY stream subscriptions and process resources when disposed.
  ///
  /// Copied from [terminalPtyBridge].
  TerminalPtyBridgeProvider(TerminalPtyBridgeParams params)
    : this._internal(
        (ref) => terminalPtyBridge(ref as TerminalPtyBridgeRef, params),
        from: terminalPtyBridgeProvider,
        name: r'terminalPtyBridgeProvider',
        debugGetCreateSourceHash: const bool.fromEnvironment('dart.vm.product')
            ? null
            : _$terminalPtyBridgeHash,
        dependencies: TerminalPtyBridgeFamily._dependencies,
        allTransitiveDependencies:
            TerminalPtyBridgeFamily._allTransitiveDependencies,
        params: params,
      );

  TerminalPtyBridgeProvider._internal(
    super._createNotifier, {
    required super.name,
    required super.dependencies,
    required super.allTransitiveDependencies,
    required super.debugGetCreateSourceHash,
    required super.from,
    required this.params,
  }) : super.internal();

  final TerminalPtyBridgeParams params;

  @override
  Override overrideWith(
    TerminalLocalPtyBridge Function(TerminalPtyBridgeRef provider) create,
  ) {
    return ProviderOverride(
      origin: this,
      override: TerminalPtyBridgeProvider._internal(
        (ref) => create(ref as TerminalPtyBridgeRef),
        from: from,
        name: null,
        dependencies: null,
        allTransitiveDependencies: null,
        debugGetCreateSourceHash: null,
        params: params,
      ),
    );
  }

  @override
  AutoDisposeProviderElement<TerminalLocalPtyBridge> createElement() {
    return _TerminalPtyBridgeProviderElement(this);
  }

  @override
  bool operator ==(Object other) {
    return other is TerminalPtyBridgeProvider && other.params == params;
  }

  @override
  int get hashCode {
    var hash = _SystemHash.combine(0, runtimeType.hashCode);
    hash = _SystemHash.combine(hash, params.hashCode);

    return _SystemHash.finish(hash);
  }
}

@Deprecated('Will be removed in 3.0. Use Ref instead')
// ignore: unused_element
mixin TerminalPtyBridgeRef on AutoDisposeProviderRef<TerminalLocalPtyBridge> {
  /// The parameter `params` of this provider.
  TerminalPtyBridgeParams get params;
}

class _TerminalPtyBridgeProviderElement
    extends AutoDisposeProviderElement<TerminalLocalPtyBridge>
    with TerminalPtyBridgeRef {
  _TerminalPtyBridgeProviderElement(super.provider);

  @override
  TerminalPtyBridgeParams get params =>
      (origin as TerminalPtyBridgeProvider).params;
}

// ignore_for_file: type=lint
// ignore_for_file: subtype_of_sealed_class, invalid_use_of_internal_member, invalid_use_of_visible_for_testing_member, deprecated_member_use_from_same_package
