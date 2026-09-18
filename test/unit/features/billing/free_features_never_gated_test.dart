import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shellvibe/features/billing/domain/entitlement.dart';
import 'package:shellvibe/features/billing/presentation/notifiers/entitlement_notifier.dart';

/// The regression `RELEASE_READINESS.md` lists as red: free Local Device Link
/// must keep working with no account, no subscription and no network.
///
/// It is a client-side rule, so this is where it can actually be enforced. The
/// server never gates `local_device_link` on any route, which means the only
/// way the free LAN feature could break is a client asking permission it was
/// never supposed to ask for.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => FlutterSecureStorage.setMockInitialValues({}));

  /// Every entitlement state the app can be in, including the ones that mean
  /// "we could not find out".
  final states = <String, EntitlementState>{
    'signed out': const EntitlementState(
      entitlement: Entitlement.free,
      source: EntitlementSource.signedOut,
    ),
    'free plan': const EntitlementState(
      entitlement: Entitlement.free,
      source: EntitlementSource.server,
    ),
    'entitlement check failed': const EntitlementState(
      entitlement: Entitlement.free,
      source: EntitlementSource.unavailable,
    ),
    'expired pro': EntitlementState(
      entitlement: Entitlement.fromJson(const {
        'plan': 'pro',
        'status': 'expired',
        'capabilities': <String>[],
      }),
      source: EntitlementSource.server,
    ),
    'unknown status': EntitlementState(
      entitlement: Entitlement.fromJson(const {
        'plan': 'pro',
        'status': 'something_new',
        'capabilities': ['cloud_backup'],
      }),
      source: EntitlementSource.server,
    ),
    'snapshot omitting the capability': EntitlementState(
      entitlement: Entitlement.fromJson(const {
        'plan': 'pro',
        'status': 'active',
        'capabilities': ['cloud_backup'],
      }),
      source: EntitlementSource.server,
    ),
    'garbage snapshot': EntitlementState(
      entitlement: Entitlement.fromJson(const {'plan': 42, 'status': []}),
      source: EntitlementSource.server,
    ),
  };

  group('Local Device Link is never gated', () {
    for (final entry in states.entries) {
      test('${entry.key}: the capability provider still answers true', () async {
        final container = ProviderContainer(
          overrides: [
            entitlementProvider.overrideWith(
              () => _StubEntitlementNotifier(entry.value),
            ),
          ],
        );
        addTearDown(container.dispose);
        await container.read(entitlementProvider.future);

        expect(
          container.read(
            hasCapabilityProvider(Capabilities.localDeviceLink),
          ),
          isTrue,
          reason:
              'A LAN feature that works offline must not depend on a server '
              'reply, including a reply that never came.',
        );
      });
    }

    test('it answers true before the notifier has produced anything', () {
      // App start: the provider is still loading. A widget reading it must not
      // briefly hide the free feature and then bring it back.
      final container = ProviderContainer();
      addTearDown(container.dispose);

      expect(
        container.read(hasCapabilityProvider(Capabilities.localDeviceLink)),
        isTrue,
      );
    });

    test('paid capabilities stay locked in exactly the same states', () async {
      // The other half of the rule: the exemption is for this one capability,
      // not a hole in the gate. Each container is resolved first, so this
      // cannot pass merely because the provider was still loading.
      //
      // 'snapshot omitting the capability' is excluded because it is an
      // entitled state by construction -- it grants cloud_backup and omits
      // only local_device_link, which is the case the block above covers.
      final locked = Map.of(states)..remove('snapshot omitting the capability');

      for (final entry in locked.entries) {
        final container = ProviderContainer(
          overrides: [
            entitlementProvider.overrideWith(
              () => _StubEntitlementNotifier(entry.value),
            ),
          ],
        );
        addTearDown(container.dispose);
        await container.read(entitlementProvider.future);

        expect(
          container.read(hasCapabilityProvider(Capabilities.cloudBackup)),
          isFalse,
          reason: '${entry.key} must not unlock cloud backup.',
        );
      }
    });

    test('an active paid plan does unlock cloud backup', () async {
      // Proves the previous test is not passing because the gate is stuck shut.
      final container = ProviderContainer(
        overrides: [
          entitlementProvider.overrideWith(
            () => _StubEntitlementNotifier(
              EntitlementState(
                entitlement: Entitlement.fromJson(const {
                  'plan': 'pro',
                  'status': 'active',
                  'capabilities': ['local_device_link', 'cloud_backup'],
                }),
                source: EntitlementSource.server,
              ),
            ),
          ),
        ],
      );
      addTearDown(container.dispose);
      await container.read(entitlementProvider.future);

      expect(
        container.read(hasCapabilityProvider(Capabilities.cloudBackup)),
        isTrue,
      );
    });
  });
}

final class _StubEntitlementNotifier extends EntitlementNotifier {
  _StubEntitlementNotifier(this._state);

  final EntitlementState _state;

  @override
  Future<EntitlementState> build() async => _state;
}
