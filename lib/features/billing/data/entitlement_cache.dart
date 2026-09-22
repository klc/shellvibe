import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../../../shared/storage/secure_storage_service.dart';
import '../domain/entitlement.dart';

/// A cached snapshot together with when it was taken and whose it is.
@immutable
final class CachedEntitlement {
  final Entitlement entitlement;
  final DateTime fetchedAt;

  /// The user the snapshot belongs to. A snapshot from a different account is
  /// discarded rather than applied.
  final String userId;

  const CachedEntitlement({
    required this.entitlement,
    required this.fetchedAt,
    required this.userId,
  });

  /// Whether the snapshot is still young enough to act on.
  bool isFresh({required DateTime now, required Duration maxAge}) =>
      !now.isAfter(fetchedAt.add(maxAge)) && !fetchedAt.isAfter(now);
}

/// Persists the last entitlement snapshot so a cold start has something to
/// draw before the network answers.
///
/// This is a UI cache, not an authority. The server's `entitlement:` middleware
/// decides every real request, so a tampered cache unlocks a button that then
/// gets a `403`. What the cache must not do is *outlive* the subscription it
/// describes, which is what [EntitlementCache.maxAge] is for.
final class EntitlementCache {
  /// How long a snapshot may be acted on without re-checking.
  ///
  /// Three days: long enough that a laptop offline over a weekend still shows
  /// its owner the features they paid for, short enough that a cancelled
  /// subscription stops unlocking the UI within days rather than indefinitely.
  /// Cloud backup needs the network to do anything anyway, so leniency here
  /// buys little and costs correctness.
  static const Duration maxAge = Duration(days: 3);

  final SecureStorageService storage;

  const EntitlementCache({required this.storage});

  /// Reads the cached snapshot, or null when there is none or it cannot be
  /// trusted.
  ///
  /// Returns null -- never a partially-decoded snapshot -- for corrupt JSON, a
  /// missing timestamp, a timestamp in the future (a clock moved backwards
  /// would otherwise extend access), or a snapshot belonging to another
  /// account.
  Future<CachedEntitlement?> read({required String forUserId}) async {
    final raw = await storage.read(key: _key);
    if (raw == null || raw.isEmpty) return null;

    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map<String, Object?>) return null;

      final userId = decoded['user_id'];
      if (userId is! String || userId != forUserId) return null;

      final fetchedAt = DateTime.tryParse(
        decoded['fetched_at'] as String? ?? '',
      );
      if (fetchedAt == null) return null;

      final snapshot = decoded['entitlement'];
      if (snapshot is! Map<String, Object?>) return null;

      return CachedEntitlement(
        entitlement: Entitlement.fromJson(snapshot),
        fetchedAt: fetchedAt,
        userId: userId,
      );
    } on FormatException catch (e) {
      if (kDebugMode) debugPrint('EntitlementCache: corrupt payload: $e');

      return null;
    }
  }

  /// Stores [entitlement] as the snapshot for [userId].
  Future<void> write({
    required Entitlement entitlement,
    required String userId,
    DateTime? now,
  }) => storage.write(
    key: _key,
    value: jsonEncode({
      'user_id': userId,
      'fetched_at': (now ?? DateTime.now()).toUtc().toIso8601String(),
      'entitlement': entitlement.toJson(),
    }),
  );

  /// Drops the snapshot. Called on sign-out: the next account's entitlement is
  /// none of this one's business.
  Future<void> clear() => storage.delete(key: _key);

  static const String _key = 'shellvibe_entitlement_snapshot';
}
