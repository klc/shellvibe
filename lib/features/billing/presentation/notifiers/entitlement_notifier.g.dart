// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'entitlement_notifier.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// Single source of truth for the account's plan limits.
///
/// Rebuilds whenever the account session changes, so signing in, signing out
/// and a rejected token all land here without a manual subscription.
///
/// Every failure path resolves to the free plan, which is the whole product:
/// the only capability it does not carry is `shared_workspaces`, and no
/// client surface asks for that one. What a failure costs is therefore
/// accuracy about limits, not access. The server enforces both regardless --
/// the `entitlement:` middleware answers `403` and an oversized upload
/// answers `413` whatever this object says.

@ProviderFor(EntitlementNotifier)
final entitlementProvider = EntitlementNotifierProvider._();

/// Single source of truth for the account's plan limits.
///
/// Rebuilds whenever the account session changes, so signing in, signing out
/// and a rejected token all land here without a manual subscription.
///
/// Every failure path resolves to the free plan, which is the whole product:
/// the only capability it does not carry is `shared_workspaces`, and no
/// client surface asks for that one. What a failure costs is therefore
/// accuracy about limits, not access. The server enforces both regardless --
/// the `entitlement:` middleware answers `403` and an oversized upload
/// answers `413` whatever this object says.
final class EntitlementNotifierProvider
    extends $AsyncNotifierProvider<EntitlementNotifier, EntitlementState> {
  /// Single source of truth for the account's plan limits.
  ///
  /// Rebuilds whenever the account session changes, so signing in, signing out
  /// and a rejected token all land here without a manual subscription.
  ///
  /// Every failure path resolves to the free plan, which is the whole product:
  /// the only capability it does not carry is `shared_workspaces`, and no
  /// client surface asks for that one. What a failure costs is therefore
  /// accuracy about limits, not access. The server enforces both regardless --
  /// the `entitlement:` middleware answers `403` and an oversized upload
  /// answers `413` whatever this object says.
  EntitlementNotifierProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'entitlementProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$entitlementNotifierHash();

  @$internal
  @override
  EntitlementNotifier create() => EntitlementNotifier();
}

String _$entitlementNotifierHash() =>
    r'2ed5524e52bdfe07afcd02d91bbe962bacb65ed9';

/// Single source of truth for the account's plan limits.
///
/// Rebuilds whenever the account session changes, so signing in, signing out
/// and a rejected token all land here without a manual subscription.
///
/// Every failure path resolves to the free plan, which is the whole product:
/// the only capability it does not carry is `shared_workspaces`, and no
/// client surface asks for that one. What a failure costs is therefore
/// accuracy about limits, not access. The server enforces both regardless --
/// the `entitlement:` middleware answers `403` and an oversized upload
/// answers `413` whatever this object says.

abstract class _$EntitlementNotifier extends $AsyncNotifier<EntitlementState> {
  FutureOr<EntitlementState> build();
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref =
        this.ref as $Ref<AsyncValue<EntitlementState>, EntitlementState>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<AsyncValue<EntitlementState>, EntitlementState>,
              AsyncValue<EntitlementState>,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, build);
  }
}

/// Whether a single capability is unlocked right now.
///
/// Answers from [Entitlement.freeCapabilities] without reading the provider
/// at all. Those do not depend on a server reply -- Local Device Link is a
/// LAN feature that works with no account, and the rest are simply free -- so
/// making them wait on one would be a round trip that can only produce the
/// answer it already has.
///
/// Anything else reads as locked while the notifier is still loading, so a
/// widget never shows a control it might have to take away a frame later.

@ProviderFor(hasCapability)
final hasCapabilityProvider = HasCapabilityFamily._();

/// Whether a single capability is unlocked right now.
///
/// Answers from [Entitlement.freeCapabilities] without reading the provider
/// at all. Those do not depend on a server reply -- Local Device Link is a
/// LAN feature that works with no account, and the rest are simply free -- so
/// making them wait on one would be a round trip that can only produce the
/// answer it already has.
///
/// Anything else reads as locked while the notifier is still loading, so a
/// widget never shows a control it might have to take away a frame later.

final class HasCapabilityProvider extends $FunctionalProvider<bool, bool, bool>
    with $Provider<bool> {
  /// Whether a single capability is unlocked right now.
  ///
  /// Answers from [Entitlement.freeCapabilities] without reading the provider
  /// at all. Those do not depend on a server reply -- Local Device Link is a
  /// LAN feature that works with no account, and the rest are simply free -- so
  /// making them wait on one would be a round trip that can only produce the
  /// answer it already has.
  ///
  /// Anything else reads as locked while the notifier is still loading, so a
  /// widget never shows a control it might have to take away a frame later.
  HasCapabilityProvider._({
    required HasCapabilityFamily super.from,
    required String super.argument,
  }) : super(
         retry: null,
         name: r'hasCapabilityProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$hasCapabilityHash();

  @override
  String toString() {
    return r'hasCapabilityProvider'
        ''
        '($argument)';
  }

  @$internal
  @override
  $ProviderElement<bool> $createElement($ProviderPointer pointer) =>
      $ProviderElement(pointer);

  @override
  bool create(Ref ref) {
    final argument = this.argument as String;
    return hasCapability(ref, argument);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(bool value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<bool>(value),
    );
  }

  @override
  bool operator ==(Object other) {
    return other is HasCapabilityProvider && other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$hasCapabilityHash() => r'8e1a5d08a6dbc11c11185a5a5d8d778cb8d14dfc';

/// Whether a single capability is unlocked right now.
///
/// Answers from [Entitlement.freeCapabilities] without reading the provider
/// at all. Those do not depend on a server reply -- Local Device Link is a
/// LAN feature that works with no account, and the rest are simply free -- so
/// making them wait on one would be a round trip that can only produce the
/// answer it already has.
///
/// Anything else reads as locked while the notifier is still loading, so a
/// widget never shows a control it might have to take away a frame later.

final class HasCapabilityFamily extends $Family
    with $FunctionalFamilyOverride<bool, String> {
  HasCapabilityFamily._()
    : super(
        retry: null,
        name: r'hasCapabilityProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  /// Whether a single capability is unlocked right now.
  ///
  /// Answers from [Entitlement.freeCapabilities] without reading the provider
  /// at all. Those do not depend on a server reply -- Local Device Link is a
  /// LAN feature that works with no account, and the rest are simply free -- so
  /// making them wait on one would be a round trip that can only produce the
  /// answer it already has.
  ///
  /// Anything else reads as locked while the notifier is still loading, so a
  /// widget never shows a control it might have to take away a frame later.

  HasCapabilityProvider call(String capability) =>
      HasCapabilityProvider._(argument: capability, from: this);

  @override
  String toString() => r'hasCapabilityProvider';
}
