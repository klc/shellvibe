import '../../../core/api/api_client.dart';
import '../domain/entitlement.dart';

/// The `/entitlements` half of the v1 API.
///
/// One endpoint, because there is nothing else left: no checkout, no
/// management portal and no provider to reconcile against. Every feature this
/// client ships is on the free plan, so the snapshot this returns is read for
/// its limits rather than for permission.
final class EntitlementApi {
  final ApiClient client;

  const EntitlementApi({required this.client});

  /// Current entitlement snapshot.
  Future<Entitlement> fetch() async {
    final response = await client.get('/entitlements');

    return Entitlement.fromJson(response.dataMap);
  }
}
