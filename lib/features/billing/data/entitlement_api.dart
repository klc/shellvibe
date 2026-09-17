import 'package:flutter/foundation.dart';

import '../../../core/api/api_client.dart';
import '../domain/entitlement.dart';

/// A web checkout destination from `GET /billing/checkout`.
@immutable
final class CheckoutTarget {
  final Uri url;
  final String plan;
  final String platform;

  const CheckoutTarget({
    required this.url,
    required this.plan,
    required this.platform,
  });
}

/// Purchasable plan identifiers the server accepts on `/billing/checkout`.
abstract final class CheckoutPlans {
  static const String proMonthly = 'pro_monthly';
  static const String proYearly = 'pro_yearly';
  static const String teamMonthly = 'team_monthly';
  static const String teamYearly = 'team_yearly';

  /// The full set the server validates against, so the client can fail before
  /// spending a request on a 422.
  static const Set<String> all = {
    proMonthly,
    proYearly,
    teamMonthly,
    teamYearly,
  };
}

/// The `/entitlements` and `/billing` half of the v1 API.
final class EntitlementApi {
  final ApiClient client;

  const EntitlementApi({required this.client});

  /// Current entitlement snapshot.
  Future<Entitlement> fetch() async {
    final response = await client.get('/entitlements');

    return Entitlement.fromJson(response.dataMap);
  }

  /// Asks the server to re-read the provider and returns the resulting
  /// snapshot.
  ///
  /// Call after a purchase or a restore. The server swallows provider errors
  /// and answers with its cached state, so a `reconciled: true` reply does not
  /// prove the provider was reachable -- only that the server tried. A purchase
  /// that has not landed yet therefore needs retrying, not trusting.
  Future<Entitlement> reconcile() async {
    final response = await client.post('/billing/reconcile');

    final entitlements = response.dataMap['entitlements'];

    return entitlements is Map<String, Object?>
        ? Entitlement.fromJson(entitlements)
        : Entitlement.free;
  }

  /// Authenticated web checkout URL for [plan].
  ///
  /// [platform] is what the server accepts here: `windows`, `linux`, `macos`
  /// or `web`. Mobile is absent on purpose -- an in-app purchase goes through
  /// the store, not through this URL.
  Future<CheckoutTarget> checkout({
    required String plan,
    String? platform,
  }) async {
    assert(
      CheckoutPlans.all.contains(plan),
      'Unknown checkout plan "$plan"; the server answers 422 for these.',
    );

    final response = await client.get(
      '/billing/checkout',
      query: {'plan': plan, 'platform': ?platform},
    );

    final data = response.dataMap;
    final url = Uri.tryParse(data['checkout_url'] as String? ?? '');

    if (url == null || !url.hasScheme) {
      throw const BillingApiException(
        'The server returned no usable checkout URL.',
      );
    }

    return CheckoutTarget(
      url: url,
      plan: data['plan'] as String? ?? plan,
      platform: data['platform'] as String? ?? platform ?? 'web',
    );
  }

  /// Subscription management URL for the channel the purchase came through.
  Future<Uri> manageUrl() async {
    final response = await client.get('/billing/manage');

    final url = Uri.tryParse(
      response.dataMap['management_url'] as String? ?? '',
    );

    if (url == null || !url.hasScheme) {
      throw const BillingApiException(
        'The server returned no usable management URL.',
      );
    }

    return url;
  }
}

/// A 2xx billing response that did not carry a usable URL.
@immutable
final class BillingApiException implements Exception {
  final String message;

  const BillingApiException(this.message);

  @override
  String toString() => 'BillingApiException: $message';
}
