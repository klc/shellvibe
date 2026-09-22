import 'package:flutter_test/flutter_test.dart';
import 'package:shellvibe/core/api/api_client.dart';
import 'package:shellvibe/core/api/api_config.dart';
import 'package:shellvibe/core/api/api_exception.dart';

import '../../../support/contract_fixture.dart';
import '../../../support/fake_api_transport.dart';

void main() {
  late FakeApiTransport transport;

  setUp(() => transport = FakeApiTransport());

  ApiClient client({
    String? token = 'test-token',
    Future<void> Function()? onUnauthenticated,
  }) => ApiClient(
    transport: transport,
    tokenProvider: () async => token,
    onUnauthenticated: onUnauthenticated,
  );

  group('request construction', () {
    test('resolves paths under the versioned prefix', () async {
      transport.enqueue(body: {'data': <String, Object?>{}});

      await client().get('/entitlements');

      expect(
        transport.lastRequest!.url.path,
        '${ApiConfig.versionPrefix}/entitlements',
      );
    });

    test('sends the bearer token in the header, never the query string', () async {
      transport.enqueue(body: {'data': <String, Object?>{}});

      await client(token: 'secret-token').get('/me');

      final request = transport.lastRequest!;
      expect(request.headers['Authorization'], 'Bearer secret-token');
      expect(request.url.query, isNot(contains('secret-token')));
      expect(request.url.toString(), isNot(contains('secret-token')));
    });

    test('does not send an X-Request-ID; the server owns that value', () async {
      transport.enqueue(body: {'data': <String, Object?>{}});

      await client().get('/me');

      expect(
        transport.lastRequest!.headers.keys.map((k) => k.toLowerCase()),
        isNot(contains('x-request-id')),
      );
    });

    test('fails before sending when an authenticated call has no token', () async {
      await expectLater(
        client(token: null).get('/me'),
        throwsA(
          isA<ApiException>()
              .having((e) => e.isUnauthenticated, 'isUnauthenticated', isTrue),
        ),
      );

      expect(transport.sent, isEmpty);
    });

    test('omits the Authorization header for public endpoints', () async {
      transport.enqueue(status: 201, body: {'data': <String, Object?>{}});

      await client(token: null).post(
        '/auth/login',
        body: {'email': 'a@b.c', 'password': 'x'},
        authenticated: false,
      );

      expect(transport.lastRequest!.headers.containsKey('Authorization'), isFalse);
      expect(transport.lastBody['email'], 'a@b.c');
    });
  });

  group('success envelopes', () {
    test('decodes a single-resource body and its request id', () async {
      final fixture = ContractFixture.load('me');
      transport.enqueue(
        status: fixture.status,
        body: fixture.body,
        headers: {'X-Request-ID': '01K25G6MWBZQ98G3R5B9P4Z7XR'},
      );

      final response = await client().get('/me');

      expect(response.statusCode, 200);
      expect(response.requestId, '01K25G6MWBZQ98G3R5B9P4Z7XR');
      expect(response.dataMap, isNotEmpty);
    });

    test('decodes a collection body with its meta member', () async {
      final fixture = ContractFixture.load('sync.revisions.index');
      transport.enqueue(status: fixture.status, body: fixture.body);

      final response = await client().get('/sync/vault/revisions');

      expect(response.dataList, hasLength(1));
      expect(response.metaInt('count'), 1);
    });

    test('tolerates a success body with no data member', () async {
      transport.enqueue(status: 200, body: <String, Object?>{});

      final response = await client().get('/me');

      expect(response.dataMap, isEmpty);
      expect(response.dataList, isEmpty);
    });
  });

  group('error mapping', () {
    test('maps the pinned unauthenticated body and drops the session', () async {
      final fixture = ContractFixture.load('error.unauthenticated');
      transport.enqueue(status: fixture.status, body: fixture.body);

      var sessionDropped = false;

      await expectLater(
        client(onUnauthenticated: () async => sessionDropped = true).get('/me'),
        throwsA(
          isA<ApiException>()
              .having((e) => e.code, 'code', ApiErrorCode.unauthenticated)
              .having((e) => e.isUnauthenticated, 'isUnauthenticated', isTrue),
        ),
      );

      expect(sessionDropped, isTrue);
    });

    test('maps the pinned validation body onto field errors', () async {
      final fixture = ContractFixture.load('error.validation');
      transport.enqueue(status: fixture.status, body: fixture.body);

      try {
        await client().post('/auth/register', body: const {});
        fail('expected an ApiException');
      } on ApiException catch (e) {
        expect(e.statusCode, 422);
        expect(e.isValidationFailure, isTrue);
        expect(e.validationErrors, isNotEmpty);
        expect(e.validationErrors.values.first, isA<List<String>>());
      }
    });

    test('keeps the request id from the error body when the header is absent', () async {
      transport.enqueue(
        status: 404,
        body: {
          'code': 'not_found',
          'message': 'Vault not found.',
          'details': <String, Object?>{},
          'request_id': '01BODYONLYREQUESTID000000',
        },
      );

      try {
        await client().get('/sync/vault');
        fail('expected an ApiException');
      } on ApiException catch (e) {
        expect(e.requestId, '01BODYONLYREQUESTID000000');
      }
    });

    test('an unknown code stays unknown rather than failing to parse', () async {
      transport.enqueue(
        status: 418,
        body: {
          'code': 'a_code_this_client_has_never_heard_of',
          'message': 'new in v1',
          'details': <String, Object?>{},
        },
      );

      try {
        await client().get('/me');
        fail('expected an ApiException');
      } on ApiException catch (e) {
        expect(e.code, 'a_code_this_client_has_never_heard_of');
        expect(e.isUnauthenticated, isFalse);
        expect(e.isSyncConflict, isFalse);
        expect(e.isThrottled, isFalse);
      }
    });

    test('a non-JSON error page still produces a usable failure', () async {
      transport.enqueue(status: 502, body: '<html>bad gateway</html>');

      try {
        await client().get('/me');
        fail('expected an ApiException');
      } on ApiException catch (e) {
        expect(e.statusCode, 502);
        expect(e.code, ApiErrorCode.unknown);
        expect(e.details, isEmpty);
      }
    });

    test('reads Retry-After on a throttled response', () async {
      transport.enqueue(
        status: 429,
        body: {
          'code': 'rate_limited',
          'message': 'Too many requests.',
          'details': <String, Object?>{},
        },
        headers: {'Retry-After': '42'},
      );

      try {
        await client().get('/me');
        fail('expected an ApiException');
      } on ApiException catch (e) {
        expect(e.retryAfterSeconds, 42);
        expect(e.isThrottled, isTrue);
        expect(e.isPlanSizeLimit, isFalse);
      }
    });

    test(
      'tells a plan size limit apart from a throttle, though both say rate_limited',
      () async {
        // SyncController::putVault answers an over-quota backup with 429
        // rate_limited. Only `details.max_size_bytes` distinguishes it.
        transport.enqueue(
          status: 429,
          body: {
            'code': 'rate_limited',
            'message': 'Backup payload exceeds plan limit of 5242880 bytes.',
            'details': {'size_bytes': 6000000, 'max_size_bytes': 5242880},
          },
        );

        try {
          await client().put('/sync/vault', body: const {});
          fail('expected an ApiException');
        } on ApiException catch (e) {
          expect(e.isPlanSizeLimit, isTrue);
          expect(e.isThrottled, isFalse);
          expect(e.detailInt('max_size_bytes'), 5242880);
          expect(e.detailInt('size_bytes'), 6000000);
        }
      },
    );

    test('surfaces a sync conflict with the server head', () async {
      transport.enqueue(
        status: 409,
        body: {
          'code': 'sync_conflict',
          'message': 'The base revision does not match current vault head.',
          'details': {'current_revision': 7, 'current_hash': 'abc'},
        },
      );

      try {
        await client().put('/sync/vault', body: const {});
        fail('expected an ApiException');
      } on ApiException catch (e) {
        expect(e.isSyncConflict, isTrue);
        expect(e.detailInt('current_revision'), 7);
      }
    });

    test('does not drop the session on a non-401 failure', () async {
      transport.enqueue(
        status: 403,
        body: {
          'code': 'forbidden',
          'message': 'Policy denied.',
          'details': <String, Object?>{},
        },
      );

      var sessionDropped = false;

      await expectLater(
        client(onUnauthenticated: () async => sessionDropped = true).get('/me'),
        throwsA(isA<ApiException>()),
      );

      expect(sessionDropped, isFalse);
    });
  });

  group('retry policy', () {
    test('retries a GET once after a transport failure', () async {
      transport.enqueueTransportFailure();
      transport.enqueue(body: {'data': <String, Object?>{}});

      final response = await client().get('/entitlements');

      expect(response.statusCode, 200);
      expect(transport.sent, hasLength(2));
    });

    test('gives up after the second GET failure', () async {
      transport.enqueueTransportFailure();
      transport.enqueueTransportFailure(timedOut: true);

      await expectLater(
        client().get('/entitlements'),
        throwsA(
          isA<ApiTransportException>()
              .having((e) => e.timedOut, 'timedOut', isTrue),
        ),
      );

      expect(transport.sent, hasLength(2));
    });

    test('never retries a write', () async {
      transport.enqueueTransportFailure();

      await expectLater(
        client().put('/sync/vault', body: const {}),
        throwsA(isA<ApiTransportException>()),
      );

      expect(
        transport.sent,
        hasLength(1),
        reason: 'A replayed write can create a second revision.',
      );
    });
  });
}
