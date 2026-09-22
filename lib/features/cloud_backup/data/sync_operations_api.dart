import '../../../core/api/api_client.dart';

/// One operation as the server stores it.
///
/// Every field that could say something about the user is either opaque
/// (`entityType` and `entityId` are HMAC aliases) or ciphertext. What is left
/// in the clear -- the clock, the device, the kind -- is what the server needs
/// to order and serve the log.
final class SyncOperationDto {
  final String id;
  final String deviceId;
  final int logicalClock;
  final String entityType;
  final String entityId;

  /// `upsert` or `delete`.
  final String operation;

  /// Sealed under the vault's sync key. Empty for a delete.
  final String encryptedPayload;

  const SyncOperationDto({
    required this.id,
    required this.deviceId,
    required this.logicalClock,
    required this.entityType,
    required this.entityId,
    required this.operation,
    required this.encryptedPayload,
  });

  bool get isDelete => operation == 'delete';

  factory SyncOperationDto.fromJson(Map<String, Object?> json) =>
      SyncOperationDto(
        id: json['id'] as String? ?? '',
        deviceId: json['device_id'] as String? ?? '',
        logicalClock: (json['logical_clock'] as num?)?.toInt() ?? 0,
        entityType: json['entity_type'] as String? ?? '',
        entityId: json['entity_id'] as String? ?? '',
        operation: json['operation'] as String? ?? 'upsert',
        encryptedPayload: json['encrypted_payload'] as String? ?? '',
      );

  Map<String, Object?> toJson() => {
    'device_id': deviceId,
    'logical_clock': logicalClock,
    'entity_type': entityType,
    'entity_id': entityId,
    'operation': operation,
    'encrypted_payload': encryptedPayload,
  };
}

/// One page of the operation log.
final class SyncOperationPage {
  final List<SyncOperationDto> operations;

  /// Highest clock in this page, or the cursor that was sent when it is empty.
  final int maxClock;

  /// True while the server still has operations past this page.
  ///
  /// Read from the server rather than inferred from the row count: comparing
  /// the count to the limit the client sent works only until the server caps
  /// it at something smaller.
  final bool hasMore;

  const SyncOperationPage({
    required this.operations,
    required this.maxClock,
    required this.hasMore,
  });

  bool get isEmpty => operations.isEmpty;
}

/// What the sync engine needs from the operation log.
///
/// A seam in the same spirit as `ApiTransport`: the engine's interesting
/// behaviour is convergence between two devices, and testing that over a
/// scripted HTTP queue would obscure it behind request plumbing.
abstract interface class SyncOperationTransport {
  Future<int> push(List<SyncOperationDto> operations);

  Future<SyncOperationPage> pull({required int sinceClock, int limit});
}

/// The `/sync/operations` half of the v1 API.
///
/// Like [CloudBackupApi], it carries opaque values and nothing else.
final class SyncOperationsApi implements SyncOperationTransport {
  final ApiClient client;

  const SyncOperationsApi({required this.client});

  /// The server caps a page at 500 and defaults to 100.
  static const int defaultLimit = 100;

  /// Sends a batch of operations.
  ///
  /// Batched because the write limit is 30 requests a minute: one request per
  /// change would spend the whole budget on a handful of edits.
  @override
  Future<int> push(List<SyncOperationDto> operations) async {
    if (operations.isEmpty) return 0;

    final response = await client.post(
      '/sync/operations',
      body: {'operations': operations.map((o) => o.toJson()).toList()},
    );

    return response.metaInt('count') ?? operations.length;
  }

  /// Reads operations after [sinceClock].
  ///
  /// Throws `ApiException` with `isSyncCursorExpired` when the log no longer
  /// reaches back this far, which means restoring from the snapshot instead.
  @override
  Future<SyncOperationPage> pull({
    required int sinceClock,
    int limit = defaultLimit,
  }) async {
    final response = await client.get(
      '/sync/operations',
      query: {'since_clock': '$sinceClock', 'limit': '$limit'},
    );

    return SyncOperationPage(
      operations: response.dataList
          .map(SyncOperationDto.fromJson)
          .toList(growable: false),
      maxClock: response.metaInt('max_clock') ?? sinceClock,
      // Absent on a server that predates the field. Treating that as "no more"
      // is the safe reading: the client stops early and picks the rest up on
      // the next pull, rather than looping forever on a page it cannot end.
      hasMore: response.meta['has_more'] == true,
    );
  }
}
