import 'dart:convert';

import 'package:cryptography/cryptography.dart';
import 'package:shellvibe/core/api/api_config.dart';
import 'package:shellvibe/core/api/api_exception.dart';
import 'package:shellvibe/core/api/api_transport.dart';

/// The backup, sync-ground and operation-log endpoints of the server, in
/// memory, behind a real [ApiTransport].
///
/// Unlike a scripted transport it answers whatever it is asked in whatever
/// order, which is what a notifier driving several services at once needs:
/// the test sets up the account, runs the notifier, and looks at what the
/// server ended up holding.
final class FakeSyncServer implements ApiTransport {
  /// Every request, in the order it arrived.
  final List<ApiRawRequest> requests = [];

  /// Stored revisions per vault kind (`backup`, `sync`), oldest first.
  final Map<String, List<Map<String, Object?>>> vaults = {
    'backup': [],
    'sync': [],
  };

  /// The operation log, in the order the server stored it. An operation's
  /// position is its index plus one.
  final List<Map<String, Object?>> operations = [];

  /// When true, every request fails as if the network were down.
  bool offline = false;

  /// Answers a request before the server does, when it returns non-null.
  ///
  /// How a test makes one endpoint refuse: a throttle, a server error, a
  /// quota.
  ApiRawResponse? Function(ApiRawRequest request)? intercept;

  /// Requests that reached a given method and path (without the version
  /// prefix), e.g. `('PUT', '/sync/vault')`.
  List<ApiRawRequest> sent(String method, String path) => requests
      .where((r) => r.method == method && _path(r) == path)
      .toList(growable: false);

  /// The newest revision of the [kind] vault, or null when it is empty.
  Map<String, Object?>? head(String kind) =>
      vaults[kind]!.isEmpty ? null : vaults[kind]!.last;

  /// Stores [ciphertext] in the [kind] vault as another device would have.
  Future<void> seedRevision(
    String kind,
    String ciphertext, {
    String deviceId = 'other-device',
  }) async {
    final revisions = vaults[kind]!;
    revisions.add(
      await _revision(
        revision: revisions.length + 1,
        baseRevision: revisions.length,
        uploadId: 'seed-${revisions.length + 1}',
        deviceId: deviceId,
        schemaVersion: 4,
        encryptionVersion: 2,
        ciphertext: ciphertext,
      ),
    );
  }

  @override
  Future<ApiRawResponse> send(ApiRawRequest request) async {
    requests.add(request);

    if (offline) {
      throw const ApiTransportException('offline');
    }

    final intercepted = intercept?.call(request);
    if (intercepted != null) return intercepted;

    final path = _path(request);
    final kind = request.url.queryParameters['kind'] ?? 'backup';

    if (request.method == 'GET' && path == '/sync/vault') {
      return _ok({'data': _head(kind)});
    }
    if (request.method == 'GET' && path == '/sync/vault/revisions') {
      final listed = vaults[kind]!.reversed
          .map((r) => {...r}..remove('ciphertext'))
          .toList();

      return _ok({
        'data': listed,
        'meta': {'count': listed.length},
      });
    }
    if (request.method == 'GET' && path.startsWith('/sync/vault/revisions/')) {
      final number = int.parse(path.split('/').last);
      final found = vaults[kind]!.where((r) => r['revision'] == number);

      return found.isEmpty
          ? _error(404, 'not_found', 'No such revision.')
          : _ok({'data': found.single});
    }
    if (request.method == 'PUT' && path == '/sync/vault') {
      return _upload(_body(request));
    }
    if (request.method == 'DELETE' && path == '/sync/vault') {
      vaults[_body(request)['kind'] as String? ?? 'backup']!.clear();

      return _ok({
        'data': {'message': 'deleted'},
      });
    }
    if (request.method == 'POST' && path == '/sync/operations') {
      final batch = (_body(request)['operations'] as List)
          .cast<Map<String, Object?>>();
      for (final operation in batch) {
        operations.add({...operation, 'id': 'op-${operations.length + 1}'});
      }

      return _ok({
        'data': <Object?>[],
        'meta': {'count': batch.length},
      });
    }
    if (request.method == 'GET' && path == '/sync/operations') {
      return _pull(request.url.queryParameters);
    }

    return _error(404, 'not_found', 'No route for ${request.method} $path.');
  }

  @override
  void close() {}

  Map<String, Object?> _head(String kind) {
    final newest = head(kind);

    return {
      'id': 'vault-$kind',
      'current_revision': newest?['revision'] ?? 0,
      'current_hash': newest?['ciphertext_sha256'],
      'bytes_used': newest?['size_bytes'] ?? 0,
      'updated_at': newest?['created_at'],
    };
  }

  Future<ApiRawResponse> _upload(Map<String, Object?> body) async {
    final kind = body['kind'] as String? ?? 'backup';
    final revisions = vaults[kind]!;
    final uploadId = body['upload_id'] as String?;

    // A retried upload gets back the revision it already wrote.
    final earlier = revisions.where((r) => r['upload_id'] == uploadId);
    if (uploadId != null && earlier.isNotEmpty) {
      return _ok({'data': _withoutCiphertext(earlier.single)}, status: 201);
    }

    final headRevision = revisions.length;
    if (body['base_revision'] != headRevision) {
      return _error(
        409,
        'sync_conflict',
        'The base revision does not match current vault head.',
        details: {
          'current_revision': headRevision,
          'current_hash': head(kind)?['ciphertext_sha256'],
        },
      );
    }

    final stored = await _revision(
      revision: headRevision + 1,
      baseRevision: headRevision,
      uploadId: uploadId,
      deviceId: body['device_id'] as String? ?? '',
      schemaVersion: body['schema_version'] as int? ?? 0,
      encryptionVersion: body['encryption_version'] as int? ?? 0,
      ciphertext: body['ciphertext'] as String,
    );
    revisions.add(stored);

    return _ok({'data': _withoutCiphertext(stored)}, status: 201);
  }

  ApiRawResponse _pull(Map<String, String> query) {
    final sinceClock = int.parse(query['since_clock'] ?? '0');
    final limit = int.parse(query['limit'] ?? '100');

    // Without a position the server works one out from the clock: the first
    // operation the device has not seen by clock.
    final int start;
    final sinceSeq = query['since_seq'];
    if (sinceSeq != null) {
      start = int.parse(sinceSeq);
    } else {
      final unseen = operations.indexWhere(
        (o) => (o['logical_clock'] as int) > sinceClock,
      );
      start = unseen == -1 ? operations.length : unseen;
    }

    final after = operations.skip(start).toList(growable: false);
    final page = after.take(limit).toList(growable: false);
    final maxClock = page.fold<int>(
      sinceClock,
      (top, o) =>
          (o['logical_clock'] as int) > top ? o['logical_clock'] as int : top,
    );

    return _ok({
      'data': page,
      'meta': {
        'max_clock': maxClock,
        'max_seq': start + page.length,
        'has_more': after.length > page.length,
      },
    });
  }

  Future<Map<String, Object?>> _revision({
    required int revision,
    required int baseRevision,
    required String? uploadId,
    required String deviceId,
    required int schemaVersion,
    required int encryptionVersion,
    required String ciphertext,
  }) async {
    final digest = await Sha256().hash(utf8.encode(ciphertext));

    return {
      'id': 'rev-$revision',
      'revision': revision,
      'base_revision': baseRevision,
      'upload_id': uploadId,
      'device_id': deviceId,
      'schema_version': schemaVersion,
      'encryption_version': encryptionVersion,
      'ciphertext_sha256': digest.bytes
          .map((b) => b.toRadixString(16).padLeft(2, '0'))
          .join(),
      'size_bytes': ciphertext.length,
      'created_at': DateTime.now().toUtc().toIso8601String(),
      'ciphertext': ciphertext,
    };
  }

  static Map<String, Object?> _withoutCiphertext(Map<String, Object?> r) =>
      {...r}..remove('ciphertext');

  static String _path(ApiRawRequest request) {
    final path = request.url.path;

    return path.startsWith(ApiConfig.versionPrefix)
        ? path.substring(ApiConfig.versionPrefix.length)
        : path;
  }

  static Map<String, Object?> _body(ApiRawRequest request) {
    final body = request.body;
    if (body == null || body.isEmpty) return const {};

    return jsonDecode(body) as Map<String, Object?>;
  }

  static ApiRawResponse _ok(Map<String, Object?> body, {int status = 200}) =>
      ApiRawResponse(statusCode: status, body: jsonEncode(body));

  /// An error body in the contract's shape.
  static ApiRawResponse error(
    int status,
    String code,
    String message, {
    Map<String, Object?> details = const {},
    Map<String, String> headers = const {},
  }) => ApiRawResponse(
    statusCode: status,
    headers: headers,
    body: jsonEncode({'code': code, 'message': message, 'details': details}),
  );

  static ApiRawResponse _error(
    int status,
    String code,
    String message, {
    Map<String, Object?> details = const {},
  }) => error(status, code, message, details: details);
}
