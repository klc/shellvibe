import 'package:flutter_test/flutter_test.dart';
import 'package:shellvibe/core/api/api_client.dart';
import 'package:shellvibe/features/cloud_backup/data/sync_operations_api.dart';

import '../../../support/contract_fixture.dart';
import '../../../support/fake_api_transport.dart';

/// The pull request and the page it decodes to.
///
/// The cursor is the part that loses data when it is wrong, and it is split
/// across two sides: the client asks by position or by clock, and the server's
/// answer says which one it used.
void main() {
  late FakeApiTransport transport;

  setUp(() => transport = FakeApiTransport());

  SyncOperationsApi api() => SyncOperationsApi(
    client: ApiClient(transport: transport, tokenProvider: () async => 'token'),
  );

  group('the request', () {
    test('asks by position once the device has one', () async {
      transport.enqueue(
        body: {'data': <Object?>[], 'meta': <String, Object?>{}},
      );

      await api().pull(sinceClock: 40, sinceSeq: 7);

      final query = transport.lastRequest!.url.queryParameters;
      expect(query['since_seq'], '7');
      expect(query.containsKey('cursor'), isFalse);
      // Still sent: a server that predates positions reads only this.
      expect(query['since_clock'], '40');
    });

    test('asks where positions start while it has none', () async {
      transport.enqueue(
        body: {'data': <Object?>[], 'meta': <String, Object?>{}},
      );

      await api().pull(sinceClock: 40);

      final query = transport.lastRequest!.url.queryParameters;
      expect(query['cursor'], 'seq');
      expect(query['since_clock'], '40');
      expect(query.containsKey('since_seq'), isFalse);
    });
  });

  group('the page', () {
    test('an answer by clock carries no position', () async {
      final fixture = ContractFixture.load('sync.operations.pull');
      transport.enqueue(status: fixture.status, body: fixture.body);

      final page = await api().pull(sinceClock: 100);

      expect(page.operations, hasLength(1));
      expect(page.maxClock, 101);
      expect(page.maxSeq, isNull);
      expect(page.hasMore, isFalse);
    });

    test('an answer by position says how far it got', () async {
      final fixture = ContractFixture.load('sync.operations.pull.seq');
      transport.enqueue(status: fixture.status, body: fixture.body);

      final page = await api().pull(sinceClock: 0, sinceSeq: 0);

      expect(page.operations, hasLength(1));
      expect(page.maxSeq, 1);
      expect(page.maxClock, 101);
      expect(page.hasMore, isFalse);
    });
  });
}
