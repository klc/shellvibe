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

  group('reconcile', () {
    test('decodes the nested entitlements member', () async {
      final fixture = ContractFixture.load('billing.reconcile');
      transport.enqueue(status: fixture.status, body: fixture.body);

      final entitlement = await api.reconcile();

      expect(entitlement.plan, BillingPlan.pro);
      expect(entitlement.hasCloudBackup, isTrue);
    });

    test('falls back to free when the nested member is missing', () async {
      transport.enqueue(status: 200, body: {'data': {'reconciled': true}});

      final entitlement = await api.reconcile();

      expect(entitlement.plan, BillingPlan.free);
      expect(entitlement.hasCloudBackup, isFalse);
    });
  });

  group('checkout', () {
    test('returns the URL the server built', () async {
      transport.enqueue(
        status: 200,
        body: {
          'data': {
            'checkout_url': 'https://checkout.shellvibe.dev?plan=pro_monthly',
            'plan': 'pro_monthly',
            'platform': 'macos',
          },
        },
      );

      final target = await api.checkout(
        plan: CheckoutPlans.proMonthly,
        platform: 'macos',
      );

      expect(target.url.host, 'checkout.shellvibe.dev');
      expect(target.plan, 'pro_monthly');
      expect(target.platform, 'macos');
      expect(transport.lastRequest!.url.queryParameters['plan'], 'pro_monthly');
      expect(transport.lastRequest!.url.queryParameters['platform'], 'macos');
    });

    test('omits platform from the query when none is given', () async {
      transport.enqueue(
        status: 200,
        body: {
          'data': {
            'checkout_url': 'https://checkout.shellvibe.dev',
            'plan': 'pro_yearly',
            'platform': 'web',
          },
        },
      );

      await api.checkout(plan: CheckoutPlans.proYearly);

      expect(
        transport.lastRequest!.url.queryParameters.containsKey('platform'),
        isFalse,
      );
    });

    test('rejects a body with no usable URL', () async {
      transport.enqueue(
        status: 200,
        body: {'data': {'checkout_url': 'not a url', 'plan': 'pro_monthly'}},
      );

      await expectLater(
        api.checkout(plan: CheckoutPlans.proMonthly),
        throwsA(isA<BillingApiException>()),
      );
    });

    test('every known plan id is one the server validates', () {
      // Mirrors `BillingController::checkout`'s `in:` rule. Drifting from it
      // would spend a request to learn a 422.
      expect(CheckoutPlans.all, {
        'pro_monthly',
        'pro_yearly',
        'team_monthly',
        'team_yearly',
      });
    });
  });

  group('manage', () {
    test('returns the management URL', () async {
      transport.enqueue(
        status: 200,
        body: {
          'data': {
            'management_url': 'https://checkout.shellvibe.dev/manage?x=1',
          },
        },
      );

      final url = await api.manageUrl();

      expect(url.path, '/manage');
    });

    test('rejects a missing management URL', () async {
      transport.enqueue(status: 200, body: {'data': <String, Object?>{}});

      await expectLater(
        api.manageUrl(),
        throwsA(isA<BillingApiException>()),
      );
    });
  });
}
