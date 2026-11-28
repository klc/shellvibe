import 'package:flutter/foundation.dart';

import '../../../core/api/api_client.dart';
import '../../../core/api/api_exception.dart';

/// What the server holds for the account's key.
@immutable
final class AccountKeyHead {
  /// Counts writes. 0 while the account has no record.
  final int revision;

  /// The record itself, opaque to the server. See `AccountKeyRecord`.
  final String? record;

  /// Whether the server lets an account that has no record get one.
  ///
  /// A rollout switch, and the server's to throw: a record makes builds that
  /// predate the account key unable to back up, so it is not created until
  /// every platform has a build that understands it. An account that already
  /// has a record keeps working whatever this says.
  final bool enabled;

  const AccountKeyHead({
    required this.revision,
    required this.record,
    required this.enabled,
  });

  /// A server that predates the account key: no record, and none to be made.
  static const AccountKeyHead unsupported = AccountKeyHead(
    revision: 0,
    record: null,
    enabled: false,
  );

  bool get exists => record != null && record!.isNotEmpty;

  factory AccountKeyHead.fromJson(Map<String, Object?> json) => AccountKeyHead(
    revision: switch (json['revision']) {
      final num v => v.toInt(),
      _ => 0,
    },
    record: json['record'] as String?,
    enabled: json['enabled'] == true,
  );
}

/// Where the account's key record is read and written.
///
/// The seam a test substitutes.
abstract interface class AccountKeyTransport {
  Future<AccountKeyHead> read();

  /// Writes [record] on top of [baseRevision].
  ///
  /// Throws [ApiException] with [AccountKeyApi.isConflict] when another device
  /// wrote first, which is how two devices setting up at once end with one
  /// key: the loser reads what the winner stored and adopts it.
  Future<AccountKeyHead> write({
    required int baseRevision,
    required String record,
    required String deviceId,
  });
}

/// The `/sync/account-key` part of the v1 API.
final class AccountKeyApi implements AccountKeyTransport {
  final ApiClient client;

  const AccountKeyApi({required this.client});

  static const String _conflict = 'account_key_conflict';

  static bool isConflict(ApiException e) => e.code == _conflict;

  @override
  Future<AccountKeyHead> read() async {
    try {
      final response = await client.get('/sync/account-key');

      return AccountKeyHead.fromJson(response.dataMap);
    } on ApiException catch (e) {
      // A server from before the endpoint existed. Not an error: the account
      // carries on sealing with the passphrase, as it does today.
      if (e.statusCode == 404) return AccountKeyHead.unsupported;
      rethrow;
    }
  }

  @override
  Future<AccountKeyHead> write({
    required int baseRevision,
    required String record,
    required String deviceId,
  }) async {
    final response = await client.put(
      '/sync/account-key',
      body: {
        'base_revision': baseRevision,
        'record': record,
        'device_id': deviceId,
      },
    );

    return AccountKeyHead.fromJson(response.dataMap);
  }
}

/// One handoff mailbox, as the server reports it.
@immutable
final class HandoffMailbox {
  final String id;
  final String? offer;
  final String? answer;
  final DateTime expiresAt;

  const HandoffMailbox({
    required this.id,
    required this.offer,
    required this.answer,
    required this.expiresAt,
  });

  factory HandoffMailbox.fromJson(Map<String, Object?> json) => HandoffMailbox(
    id: json['id'] as String,
    offer: json['offer'] as String?,
    answer: json['answer'] as String?,
    expiresAt: DateTime.parse(json['expires_at'] as String).toUtc(),
  );
}

/// Where two devices of one account leave each other a message.
abstract interface class HandoffTransport {
  Future<HandoffMailbox> open();

  Future<HandoffMailbox> read(String id);

  Future<void> writeOffer(String id, String message);

  Future<void> writeAnswer(String id, String message);

  Future<void> close(String id);
}

/// The `/sync/handoffs` part of the v1 API.
///
/// Carries two opaque messages and nothing else. What is in them, and why the
/// server cannot read or replace them, is `DeviceHandoff`'s business.
final class HandoffApi implements HandoffTransport {
  final ApiClient client;

  const HandoffApi({required this.client});

  @override
  Future<HandoffMailbox> open() async {
    final response = await client.post('/sync/handoffs');
    final data = response.dataMap;

    return HandoffMailbox(
      id: data['id'] as String,
      offer: null,
      answer: null,
      expiresAt: DateTime.parse(data['expires_at'] as String).toUtc(),
    );
  }

  @override
  Future<HandoffMailbox> read(String id) async {
    final response = await client.get('/sync/handoffs/$id');

    return HandoffMailbox.fromJson(response.dataMap);
  }

  @override
  Future<void> writeOffer(String id, String message) =>
      client.put('/sync/handoffs/$id/offer', body: {'message': message});

  @override
  Future<void> writeAnswer(String id, String message) =>
      client.put('/sync/handoffs/$id/answer', body: {'message': message});

  @override
  Future<void> close(String id) => client.delete('/sync/handoffs/$id');
}
