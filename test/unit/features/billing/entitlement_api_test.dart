import 'package:flutter_test/flutter_test.dart';
import 'package:shellvibe/core/api/api_client.dart';
import 'package:shellvibe/core/api/api_exception.dart';
import 'package:shellvibe/features/billing/data/entitlement_api.dart';
import 'package:shellvibe/features/billing/domain/entitlement.dart';

import '../../../support/contract_fixture.dart';
import '../../../support/fake_api_transport.dart';

void main() {
  late FakeApiTransport transport;
  late EntitlementApi api;

  setUp(() {
    transport = FakeApiTransport();
    api = EntitlementApi(
      client: ApiClient(
        transport: transport,
        tokenProvider: () async => 'test-token',
      ),
    );
  });

  group('fetch', () {
    test('decodes the pinned entitlements fixture', () async {
      final fixture = ContractFixture.load('entitlements.index');
      transport.enqueue(status: fixture.status, body: fixture.body);

      final entitlement = await api.fetch();

      expect(entitlement.plan, BillingPlan.free);
      expect(transport.lastRequest!.url.path, endsWith('/entitlements'));
    });

    test('propagates an API failure instead of inventing a plan', () async {
      transport.enqueue(
        status: 500,
        body: {
          'code': 'internal_error',
          'message': 'boom',
          'details': <String, Object?>{},
        },
      );

      await expectLater(api.fetch(), throwsA(isA<ApiException>()));
    });
  });
}
