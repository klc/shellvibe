// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'sync_notifier.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// Runs automatic sync.
///
/// Rebuilds when the account, the entitlement or the switch changes, so
/// signing out or turning it off stops it without anything having to listen.
///
/// `keepAlive` because it owns timers: a disposed instance would leave them
/// firing into nothing.

@ProviderFor(SyncNotifier)
final syncProvider = SyncNotifierProvider._();

/// Runs automatic sync.
///
/// Rebuilds when the account, the entitlement or the switch changes, so
/// signing out or turning it off stops it without anything having to listen.
///
/// `keepAlive` because it owns timers: a disposed instance would leave them
/// firing into nothing.
final class SyncNotifierProvider
    extends $AsyncNotifierProvider<SyncNotifier, SyncState> {
  /// Runs automatic sync.
  ///
  /// Rebuilds when the account, the entitlement or the switch changes, so
  /// signing out or turning it off stops it without anything having to listen.
  ///
  /// `keepAlive` because it owns timers: a disposed instance would leave them
  /// firing into nothing.
  SyncNotifierProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'syncProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$syncNotifierHash();

  @$internal
  @override
  SyncNotifier create() => SyncNotifier();
}

String _$syncNotifierHash() => r'cee938154b381660d23d9186310a4ca6a6ef3a96';

/// Runs automatic sync.
///
/// Rebuilds when the account, the entitlement or the switch changes, so
/// signing out or turning it off stops it without anything having to listen.
///
/// `keepAlive` because it owns timers: a disposed instance would leave them
/// firing into nothing.

abstract class _$SyncNotifier extends $AsyncNotifier<SyncState> {
  FutureOr<SyncState> build();
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref = this.ref as $Ref<AsyncValue<SyncState>, SyncState>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<AsyncValue<SyncState>, SyncState>,
              AsyncValue<SyncState>,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, build);
  }
}
