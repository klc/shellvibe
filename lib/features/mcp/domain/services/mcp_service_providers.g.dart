// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'mcp_service_providers.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// Auto-disposing provider for [PolicyEngine].
///
/// [PolicyEngine] itself holds no mutable state between calls — it is safe
/// to rebuild whenever its repository dependencies change.

@ProviderFor(policyEngine)
final policyEngineProvider = PolicyEngineProvider._();

/// Auto-disposing provider for [PolicyEngine].
///
/// [PolicyEngine] itself holds no mutable state between calls — it is safe
/// to rebuild whenever its repository dependencies change.

final class PolicyEngineProvider
    extends $FunctionalProvider<PolicyEngine, PolicyEngine, PolicyEngine>
    with $Provider<PolicyEngine> {
  /// Auto-disposing provider for [PolicyEngine].
  ///
  /// [PolicyEngine] itself holds no mutable state between calls — it is safe
  /// to rebuild whenever its repository dependencies change.
  PolicyEngineProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'policyEngineProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$policyEngineHash();

  @$internal
  @override
  $ProviderElement<PolicyEngine> $createElement($ProviderPointer pointer) =>
      $ProviderElement(pointer);

  @override
  PolicyEngine create(Ref ref) {
    return policyEngine(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(PolicyEngine value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<PolicyEngine>(value),
    );
  }
}

String _$policyEngineHash() => r'f038819b7b95d107f7ea71b92508e65be108e7b6';

/// Provider for [ApprovalCoordinator].
///
/// Must be `keepAlive`: an autoDispose coordinator would drop a pending
/// approval — and the agent-side `Future` waiting on it — the instant
/// nothing happened to be watching it, e.g. the moment the approval dialog
/// that triggered the watch gets rebuilt or navigated away from. The
/// coordinator has to outlive any single screen; only the panic button and
/// a vault lock (via [ApprovalCoordinator.cancelAll]) get to end a pending
/// approval early.

@ProviderFor(approvalCoordinator)
final approvalCoordinatorProvider = ApprovalCoordinatorProvider._();

/// Provider for [ApprovalCoordinator].
///
/// Must be `keepAlive`: an autoDispose coordinator would drop a pending
/// approval — and the agent-side `Future` waiting on it — the instant
/// nothing happened to be watching it, e.g. the moment the approval dialog
/// that triggered the watch gets rebuilt or navigated away from. The
/// coordinator has to outlive any single screen; only the panic button and
/// a vault lock (via [ApprovalCoordinator.cancelAll]) get to end a pending
/// approval early.

final class ApprovalCoordinatorProvider
    extends
        $FunctionalProvider<
          ApprovalCoordinator,
          ApprovalCoordinator,
          ApprovalCoordinator
        >
    with $Provider<ApprovalCoordinator> {
  /// Provider for [ApprovalCoordinator].
  ///
  /// Must be `keepAlive`: an autoDispose coordinator would drop a pending
  /// approval — and the agent-side `Future` waiting on it — the instant
  /// nothing happened to be watching it, e.g. the moment the approval dialog
  /// that triggered the watch gets rebuilt or navigated away from. The
  /// coordinator has to outlive any single screen; only the panic button and
  /// a vault lock (via [ApprovalCoordinator.cancelAll]) get to end a pending
  /// approval early.
  ApprovalCoordinatorProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'approvalCoordinatorProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$approvalCoordinatorHash();

  @$internal
  @override
  $ProviderElement<ApprovalCoordinator> $createElement(
    $ProviderPointer pointer,
  ) => $ProviderElement(pointer);

  @override
  ApprovalCoordinator create(Ref ref) {
    return approvalCoordinator(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(ApprovalCoordinator value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<ApprovalCoordinator>(value),
    );
  }
}

String _$approvalCoordinatorHash() =>
    r'28517f0e806461f544b54bcbb53037d6a66dfbd6';
