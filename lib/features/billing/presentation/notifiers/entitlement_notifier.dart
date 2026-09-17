import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../../core/api/api_exception.dart';
import '../../../../shared/providers/database_providers.dart';
import '../../../account/presentation/notifiers/account_notifier.dart';
import '../../data/entitlement_api.dart';
import '../../data/entitlement_cache.dart';
import '../../domain/entitlement.dart';

part 'entitlement_notifier.g.dart';

/// Where the snapshot in [EntitlementState.entitlement] came from.
enum EntitlementSource {
  /// No account, so the free plan applies by definition.
  signedOut,

  /// A cached snapshot inside its freshness window.
  cache,

  /// Straight from the server.
  server,

  /// The server could not be reached and the cache was missing or stale, so
  /// the free plan is assumed. Paid features stay locked and the UI can say
  /// why rather than implying the subscription is gone.
  unavailable,
}

/// Immutable entitlement state.
@immutable
final class EntitlementState {
  final Entitlement entitlement;
  final EntitlementSource source;

  /// True while a refresh is in flight over an already-published snapshot.
  final bool isRefreshing;

  const EntitlementState({
    required this.entitlement,
    required this.source,
    this.isRefreshing = false,
  });

  /// Whether the UI should offer a paid feature.
  bool has(String capability) => entitlement.has(capability);

  /// The paid feature this client work is for.
  bool get hasCloudBackup => entitlement.hasCloudBackup;

  /// True when the lock is the network's fault, not the subscription's.
  ///
  /// Worth telling apart in the UI: "you need Pro" and "we could not check
  /// your subscription" ask the user to do completely different things.
  bool get isLockedByUnavailability => source == EntitlementSource.unavailable;

  EntitlementState copyWith({
    Entitlement? entitlement,
    EntitlementSource? source,
    bool? isRefreshing,
  }) => EntitlementState(
    entitlement: entitlement ?? this.entitlement,
    source: source ?? this.source,
    isRefreshing: isRefreshing ?? this.isRefreshing,
  );
}

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
@Riverpod(keepAlive: true)
class EntitlementNotifier extends _$EntitlementNotifier {
  late final EntitlementCache _cache;
  EntitlementApi? _api;

  @override
  Future<EntitlementState> build() async {
    _cache = EntitlementCache(
      storage: ref.watch(secureStorageServiceProvider),
    );

    final account = await ref.watch(accountProvider.future);

    if (!account.isSignedIn) {
      // Not an error state: the app is fully usable signed out, and the free
      // plan is exactly what applies.
      return const EntitlementState(
        entitlement: Entitlement.free,
        source: EntitlementSource.signedOut,
      );
    }

    final userId = account.session!.userId;
    _api = EntitlementApi(
      client: ref.watch(accountProvider.notifier).apiClient,
    );

    // Publish a fresh cached snapshot first so the UI does not flash a paywall
    // at a paying user while the request is in flight, then refresh behind it.
    final cached = await _cache.read(forUserId: userId);
    if (cached != null &&
        cached.isFresh(
          now: DateTime.now(),
          maxAge: EntitlementCache.maxAge,
        )) {
      Future.microtask(refresh);

      return EntitlementState(
        entitlement: cached.entitlement,
        source: EntitlementSource.cache,
        isRefreshing: true,
      );
    }

    return _fetchAndStore(userId);
  }

  /// Re-reads the snapshot from the server.
  ///
  /// Never throws: a failure publishes [EntitlementSource.unavailable] over the
  /// free plan rather than propagating, because there is no caller for whom an
  /// entitlement check failing is worth an exception.
  Future<void> refresh() async {
    final account = await ref.read(accountProvider.future);
    if (!account.isSignedIn) return;

    final current = state.value;
    if (current != null) {
      state = AsyncValue.data(current.copyWith(isRefreshing: true));
    }

    state = AsyncValue.data(await _fetchAndStore(account.session!.userId));
  }

  /// Asks the server to re-read the payment provider, then adopts the result.
  ///
  /// Call after a purchase or a restore. Throws [ApiFailure] so a purchase flow
  /// can tell the user their payment went through but has not landed yet --
  /// that one *is* worth surfacing, unlike a background refresh.
  Future<void> reconcileAfterPurchase() async {
    final account = await ref.read(accountProvider.future);
    if (!account.isSignedIn) return;

    final api = _api;
    if (api == null) return;

    final userId = account.session!.userId;
    final entitlement = await api.reconcile();

    await _cache.write(entitlement: entitlement, userId: userId);

    state = AsyncValue.data(
      EntitlementState(
        entitlement: entitlement,
        source: EntitlementSource.server,
      ),
    );
  }

  /// Drops the cached snapshot. Called when an account stops being this
  /// device's account.
  Future<void> clearCache() => _cache.clear();

  Future<EntitlementState> _fetchAndStore(String userId) async {
    final api = _api;
    if (api == null) {
      return const EntitlementState(
        entitlement: Entitlement.free,
        source: EntitlementSource.unavailable,
      );
    }

    try {
      final entitlement = await api.fetch();
      await _cache.write(entitlement: entitlement, userId: userId);

      return EntitlementState(
        entitlement: entitlement,
        source: EntitlementSource.server,
      );
    } on ApiFailure catch (e) {
      if (kDebugMode) debugPrint('Entitlement refresh failed: $e');

      // A stale cache is not a licence. Fall back to a fresh one if the window
      // still holds, otherwise to free.
      final cached = await _cache.read(forUserId: userId);
      if (cached != null &&
          cached.isFresh(
            now: DateTime.now(),
            maxAge: EntitlementCache.maxAge,
          )) {
        return EntitlementState(
          entitlement: cached.entitlement,
          source: EntitlementSource.cache,
        );
      }

      return const EntitlementState(
        entitlement: Entitlement.free,
        source: EntitlementSource.unavailable,
      );
    }
  }
}

/// Whether a single capability is unlocked right now.
///
/// Reads as free while the notifier is still loading, so a widget never shows
/// a paid control it might have to take away a frame later.
@riverpod
bool hasCapability(Ref ref, String capability) {
  // Local Device Link is free, offline and accountless. Answering it from the
  // entitlement snapshot at all would make a LAN feature depend on a server
  // reply, so it short-circuits before the provider is even read.
  if (capability == Capabilities.localDeviceLink) return true;

  final state = ref.watch(entitlementProvider).value;

  return state?.has(capability) ?? false;
}
