import 'dart:convert';

import 'package:cryptography/cryptography.dart';

/// Opaque names for the rows an operation refers to.
///
/// The server stores `entity_type` and `entity_id` and never reads them: it
/// validates their length and hands them back. That is what lets them be
/// aliases rather than the real thing.
///
/// The aliases are deterministic, which is the whole requirement -- entity
/// level last-writer-wins only works if two devices name the same row the same
/// way. They are also meaningless to the server: it learns how many distinct
/// buckets exist and how often each one is written, not what any of them is.
///
/// What that does not hide is written down in the design note: an alias is
/// stable for the lifetime of the vault, so a long-lived activity profile per
/// row is visible. Rotating aliases per snapshot epoch would sever the very
/// identity last-writer-wins depends on, which is a worse trade.
final class SyncAliases {
  /// Characters kept from the base64url encoding.
  ///
  /// The server's columns hold 64 characters; 32 leaves room and still carries
  /// 192 bits, far past any collision concern within one vault.
  static const int aliasLength = 32;

  final Hmac _hmac;
  final SecretKey syncKey;

  SyncAliases({required this.syncKey}) : _hmac = Hmac.sha256();

  /// The alias for a table, such as `hosts`.
  Future<String> forType(String entityType) => _alias('type:$entityType');

  /// The alias for one row of a table.
  ///
  /// The table name is part of the input, so the same id under two tables --
  /// which nothing prevents -- produces two different aliases.
  Future<String> forEntity({
    required String entityType,
    required String entityId,
  }) => _alias('$entityType:$entityId');

  Future<String> _alias(String input) async {
    final mac = await _hmac.calculateMac(
      utf8.encode(input),
      secretKey: syncKey,
    );

    return base64Url
        .encode(mac.bytes)
        .replaceAll('=', '')
        .substring(0, aliasLength);
  }
}
