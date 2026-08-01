// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'network_providers.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// Provider for [SSHSessionManager].
/// Note: [TerminalTabSession] instances instantiate dedicated [SSHSessionManager]
/// instances per connection to ensure tabs do not share SSH clients/sockets.

@ProviderFor(sshSessionManager)
final sshSessionManagerProvider = SshSessionManagerProvider._();

/// Provider for [SSHSessionManager].
/// Note: [TerminalTabSession] instances instantiate dedicated [SSHSessionManager]
/// instances per connection to ensure tabs do not share SSH clients/sockets.

final class SshSessionManagerProvider
    extends
        $FunctionalProvider<
          SSHSessionManager,
          SSHSessionManager,
          SSHSessionManager
        >
    with $Provider<SSHSessionManager> {
  /// Provider for [SSHSessionManager].
  /// Note: [TerminalTabSession] instances instantiate dedicated [SSHSessionManager]
  /// instances per connection to ensure tabs do not share SSH clients/sockets.
  SshSessionManagerProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'sshSessionManagerProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$sshSessionManagerHash();

  @$internal
  @override
  $ProviderElement<SSHSessionManager> $createElement(
    $ProviderPointer pointer,
  ) => $ProviderElement(pointer);

  @override
  SSHSessionManager create(Ref ref) {
    return sshSessionManager(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(SSHSessionManager value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<SSHSessionManager>(value),
    );
  }
}

String _$sshSessionManagerHash() => r'8cc894adfd88a46cd733a95b97f7df9f40b2a337';

/// Auto-disposing provider for [LocalPtyManager].

@ProviderFor(localPtyManager)
final localPtyManagerProvider = LocalPtyManagerProvider._();

/// Auto-disposing provider for [LocalPtyManager].

final class LocalPtyManagerProvider
    extends
        $FunctionalProvider<LocalPtyManager, LocalPtyManager, LocalPtyManager>
    with $Provider<LocalPtyManager> {
  /// Auto-disposing provider for [LocalPtyManager].
  LocalPtyManagerProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'localPtyManagerProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$localPtyManagerHash();

  @$internal
  @override
  $ProviderElement<LocalPtyManager> $createElement($ProviderPointer pointer) =>
      $ProviderElement(pointer);

  @override
  LocalPtyManager create(Ref ref) {
    return localPtyManager(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(LocalPtyManager value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<LocalPtyManager>(value),
    );
  }
}

String _$localPtyManagerHash() => r'586576942c0a03be027627397f97981964ea0dc6';

/// Auto-disposing family provider for [TerminalSSHBridge].
/// Cleanly disposes stream subscriptions and session resources when disposed.

@ProviderFor(terminalSSHBridge)
final terminalSSHBridgeProvider = TerminalSSHBridgeFamily._();

/// Auto-disposing family provider for [TerminalSSHBridge].
/// Cleanly disposes stream subscriptions and session resources when disposed.

final class TerminalSSHBridgeProvider
    extends
        $FunctionalProvider<
          TerminalSSHBridge,
          TerminalSSHBridge,
          TerminalSSHBridge
        >
    with $Provider<TerminalSSHBridge> {
  /// Auto-disposing family provider for [TerminalSSHBridge].
  /// Cleanly disposes stream subscriptions and session resources when disposed.
  TerminalSSHBridgeProvider._({
    required TerminalSSHBridgeFamily super.from,
    required TerminalSSHBridgeParams super.argument,
  }) : super(
         retry: null,
         name: r'terminalSSHBridgeProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$terminalSSHBridgeHash();

  @override
  String toString() {
    return r'terminalSSHBridgeProvider'
        ''
        '($argument)';
  }

  @$internal
  @override
  $ProviderElement<TerminalSSHBridge> $createElement(
    $ProviderPointer pointer,
  ) => $ProviderElement(pointer);

  @override
  TerminalSSHBridge create(Ref ref) {
    final argument = this.argument as TerminalSSHBridgeParams;
    return terminalSSHBridge(ref, argument);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(TerminalSSHBridge value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<TerminalSSHBridge>(value),
    );
  }

  @override
  bool operator ==(Object other) {
    return other is TerminalSSHBridgeProvider && other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$terminalSSHBridgeHash() => r'c9e461908673827ee91ab24f2dddb85115d21dc0';

/// Auto-disposing family provider for [TerminalSSHBridge].
/// Cleanly disposes stream subscriptions and session resources when disposed.

final class TerminalSSHBridgeFamily extends $Family
    with $FunctionalFamilyOverride<TerminalSSHBridge, TerminalSSHBridgeParams> {
  TerminalSSHBridgeFamily._()
    : super(
        retry: null,
        name: r'terminalSSHBridgeProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  /// Auto-disposing family provider for [TerminalSSHBridge].
  /// Cleanly disposes stream subscriptions and session resources when disposed.

  TerminalSSHBridgeProvider call(TerminalSSHBridgeParams params) =>
      TerminalSSHBridgeProvider._(argument: params, from: this);

  @override
  String toString() => r'terminalSSHBridgeProvider';
}

/// Auto-disposing family provider for [TerminalLocalPtyBridge].
/// Cleanly disposes PTY stream subscriptions and process resources when disposed.

@ProviderFor(terminalPtyBridge)
final terminalPtyBridgeProvider = TerminalPtyBridgeFamily._();

/// Auto-disposing family provider for [TerminalLocalPtyBridge].
/// Cleanly disposes PTY stream subscriptions and process resources when disposed.

final class TerminalPtyBridgeProvider
    extends
        $FunctionalProvider<
          TerminalLocalPtyBridge,
          TerminalLocalPtyBridge,
          TerminalLocalPtyBridge
        >
    with $Provider<TerminalLocalPtyBridge> {
  /// Auto-disposing family provider for [TerminalLocalPtyBridge].
  /// Cleanly disposes PTY stream subscriptions and process resources when disposed.
  TerminalPtyBridgeProvider._({
    required TerminalPtyBridgeFamily super.from,
    required TerminalPtyBridgeParams super.argument,
  }) : super(
         retry: null,
         name: r'terminalPtyBridgeProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$terminalPtyBridgeHash();

  @override
  String toString() {
    return r'terminalPtyBridgeProvider'
        ''
        '($argument)';
  }

  @$internal
  @override
  $ProviderElement<TerminalLocalPtyBridge> $createElement(
    $ProviderPointer pointer,
  ) => $ProviderElement(pointer);

  @override
  TerminalLocalPtyBridge create(Ref ref) {
    final argument = this.argument as TerminalPtyBridgeParams;
    return terminalPtyBridge(ref, argument);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(TerminalLocalPtyBridge value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<TerminalLocalPtyBridge>(value),
    );
  }

  @override
  bool operator ==(Object other) {
    return other is TerminalPtyBridgeProvider && other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$terminalPtyBridgeHash() => r'51bc0a650e5cc48e3b936d831ac24cd712d83445';

/// Auto-disposing family provider for [TerminalLocalPtyBridge].
/// Cleanly disposes PTY stream subscriptions and process resources when disposed.

final class TerminalPtyBridgeFamily extends $Family
    with
        $FunctionalFamilyOverride<
          TerminalLocalPtyBridge,
          TerminalPtyBridgeParams
        > {
  TerminalPtyBridgeFamily._()
    : super(
        retry: null,
        name: r'terminalPtyBridgeProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  /// Auto-disposing family provider for [TerminalLocalPtyBridge].
  /// Cleanly disposes PTY stream subscriptions and process resources when disposed.

  TerminalPtyBridgeProvider call(TerminalPtyBridgeParams params) =>
      TerminalPtyBridgeProvider._(argument: params, from: this);

  @override
  String toString() => r'terminalPtyBridgeProvider';
}
