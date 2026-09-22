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
  /// the free plan is assumed.
  ///
  /// Nothing the client draws is locked by this -- the free plan carries all
  /// of it -- but the limits in the snapshot are then this build's defaults
  /// rather than the server's, which is worth being able to say.
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

  /// Whether the UI should offer [capability].
  bool has(String capability) => entitlement.has(capability);

  /// Encrypted cloud backup. Free, so always true.
  bool get hasCloudBackup => entitlement.hasCloudBackup;

  /// True when the snapshot is this build's assumption rather than the
  /// server's answer.
  ///
  /// The limits shown alongside it are defaults, so an upload the client
  /// thinks fits may still come back `413`.
  bool get isFromFallback => source == EntitlementSource.unavailable;

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
@Riverpod(keepAlive: true)
class EntitlementNotifier extends _$EntitlementNotifier {
  late final EntitlementCache _cache;
  EntitlementApi? _api;

  @override
  Future<EntitlementState> build() async {
    _cache = EntitlementCache(storage: ref.watch(secureStorageServiceProvider));

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

    // Publish a fresh cached snapshot first so the UI does not flash this
    // build's default limits while the request is in flight, then refresh
    // behind it.
    final cached = await _cache.read(forUserId: userId);
    if (cached != null &&
        cached.isFresh(now: DateTime.now(), maxAge: EntitlementCache.maxAge)) {
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

      // Fall back to the cache if its window still holds, otherwise to the
      // free plan's own numbers.
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
/// Answers from [Entitlement.freeCapabilities] without reading the provider
/// at all. Those do not depend on a server reply -- Local Device Link is a
/// LAN feature that works with no account, and the rest are simply free -- so
/// making them wait on one would be a round trip that can only produce the
/// answer it already has.
///
/// Anything else reads as locked while the notifier is still loading, so a
/// widget never shows a control it might have to take away a frame later.
@riverpod
bool hasCapability(Ref ref, String capability) {
  if (Entitlement.freeCapabilities.contains(capability)) return true;

  final state = ref.watch(entitlementProvider).value;

  return state?.has(capability) ?? false;
}
