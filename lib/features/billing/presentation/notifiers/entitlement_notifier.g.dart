// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'entitlement_notifier.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// Single source of truth for what the user may use.
///
/// Rebuilds whenever the account session changes, so signing in, signing out
/// and a rejected token all land here without a manual subscription.
///
/// Every failure path resolves to the free plan. This gate is UI only -- the
/// server's `entitlement:` middleware enforces access on every request -- so
/// the cost of locking wrongly is a dismissable paywall, while the cost of
/// unlocking wrongly is giving the product away. The asymmetry decides the
/// direction.

@ProviderFor(EntitlementNotifier)
final entitlementProvider = EntitlementNotifierProvider._();

/// Single source of truth for what the user may use.
///
/// Rebuilds whenever the account session changes, so signing in, signing out
/// and a rejected token all land here without a manual subscription.
///
/// Every failure path resolves to the free plan. This gate is UI only -- the
/// server's `entitlement:` middleware enforces access on every request -- so
/// the cost of locking wrongly is a dismissable paywall, while the cost of
/// unlocking wrongly is giving the product away. The asymmetry decides the
/// direction.
final class EntitlementNotifierProvider
    extends $AsyncNotifierProvider<EntitlementNotifier, EntitlementState> {
  /// Single source of truth for what the user may use.
  ///
  /// Rebuilds whenever the account session changes, so signing in, signing out
  /// and a rejected token all land here without a manual subscription.
  ///
  /// Every failure path resolves to the free plan. This gate is UI only -- the
  /// server's `entitlement:` middleware enforces access on every request -- so
  /// the cost of locking wrongly is a dismissable paywall, while the cost of
  /// unlocking wrongly is giving the product away. The asymmetry decides the
  /// direction.
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
    r'e9f06af818da83e5872239ab63c936c7c523e6dc';

/// Single source of truth for what the user may use.
///
/// Rebuilds whenever the account session changes, so signing in, signing out
/// and a rejected token all land here without a manual subscription.
///
/// Every failure path resolves to the free plan. This gate is UI only -- the
/// server's `entitlement:` middleware enforces access on every request -- so
/// the cost of locking wrongly is a dismissable paywall, while the cost of
/// unlocking wrongly is giving the product away. The asymmetry decides the
/// direction.

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
/// Reads as free while the notifier is still loading, so a widget never shows
/// a paid control it might have to take away a frame later.

@ProviderFor(hasCapability)
final hasCapabilityProvider = HasCapabilityFamily._();

/// Whether a single capability is unlocked right now.
///
/// Reads as free while the notifier is still loading, so a widget never shows
/// a paid control it might have to take away a frame later.

final class HasCapabilityProvider extends $FunctionalProvider<bool, bool, bool>
    with $Provider<bool> {
  /// Whether a single capability is unlocked right now.
  ///
  /// Reads as free while the notifier is still loading, so a widget never shows
  /// a paid control it might have to take away a frame later.
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

String _$hasCapabilityHash() => r'acc9de363ed23f1f46a734c8cd9ca53de120d312';

/// Whether a single capability is unlocked right now.
///
/// Reads as free while the notifier is still loading, so a widget never shows
/// a paid control it might have to take away a frame later.

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
  /// Reads as free while the notifier is still loading, so a widget never shows
  /// a paid control it might have to take away a frame later.

  HasCapabilityProvider call(String capability) =>
      HasCapabilityProvider._(argument: capability, from: this);

  @override
  String toString() => r'hasCapabilityProvider';
}
