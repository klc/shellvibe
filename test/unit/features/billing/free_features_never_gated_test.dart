import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shellvibe/features/billing/domain/entitlement.dart';
import 'package:shellvibe/features/billing/presentation/notifiers/entitlement_notifier.dart';

/// Free features must keep working with no account, no grant and no network.
///
/// This began as the Local Device Link rule from `RELEASE_READINESS.md`. Every
/// shipped capability is free now, so the rule covers all of them: the only
/// way one of them could break is a client asking permission it was never
/// supposed to ask for.
///
/// The other half is still worth pinning down. `shared_workspaces` is not on
/// the free plan, so the gate has to stay a gate -- otherwise the machinery
/// is decorative and there is nothing left to build a team tier on.
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
    'expired tier': EntitlementState(
      entitlement: Entitlement.fromJson(const {
        'plan': 'team',
        'status': 'expired',
        'capabilities': <String>[],
      }),
      source: EntitlementSource.server,
    ),
    'unknown status': EntitlementState(
      entitlement: Entitlement.fromJson(const {
        'plan': 'team',
        'status': 'something_new',
        'capabilities': ['shared_workspaces'],
      }),
      source: EntitlementSource.server,
    ),
    'snapshot listing nothing at all': EntitlementState(
      entitlement: Entitlement.fromJson(const {
        'plan': 'free',
        'status': 'active',
        'capabilities': <String>[],
      }),
      source: EntitlementSource.server,
    ),
    'garbage snapshot': EntitlementState(
      entitlement: Entitlement.fromJson(const {'plan': 42, 'status': []}),
      source: EntitlementSource.server,
    ),
  };

  ProviderContainer containerFor(EntitlementState state) => ProviderContainer(
    overrides: [
      entitlementProvider.overrideWith(() => _StubEntitlementNotifier(state)),
    ],
  );

  group('free capabilities are never gated', () {
    for (final entry in states.entries) {
      for (final capability in Entitlement.freeCapabilities) {
        test('${entry.key}: $capability still answers true', () async {
          final container = containerFor(entry.value);
          addTearDown(container.dispose);
          await container.read(entitlementProvider.future);

          expect(
            container.read(hasCapabilityProvider(capability)),
            isTrue,
            reason:
                'A free feature must not depend on a server reply, including '
                'a reply that never came.',
          );
        });
      }
    }

    test('they answer true before the notifier has produced anything', () {
      // App start: the provider is still loading. A widget reading it must not
      // briefly hide a free feature and then bring it back.
      final container = ProviderContainer();
      addTearDown(container.dispose);

      for (final capability in Entitlement.freeCapabilities) {
        expect(
          container.read(hasCapabilityProvider(capability)),
          isTrue,
          reason: '$capability was hidden while the snapshot was loading.',
        );
      }
    });
  });

  group('the gate still shuts', () {
    test(
      'shared workspaces stays locked in every one of those states',
      () async {
        // The other half of the rule: the exemption is for the free set, not a
        // hole in the gate. Each container is resolved first, so this cannot
        // pass merely because the provider was still loading.
        //
        // 'unknown status' is included on purpose: the server echoing the
        // capability is not enough when it will not say the tier is current.
        for (final entry in states.entries) {
          final container = containerFor(entry.value);
          addTearDown(container.dispose);
          await container.read(entitlementProvider.future);

          expect(
            container.read(
              hasCapabilityProvider(Capabilities.sharedWorkspaces),
            ),
            isFalse,
            reason: '${entry.key} must not unlock shared workspaces.',
          );
        }
      },
    );

    test('an active team tier does unlock shared workspaces', () async {
      // Proves the previous test is not passing because the gate is stuck shut.
      final container = containerFor(
        EntitlementState(
          entitlement: Entitlement.fromJson(const {
            'plan': 'team',
            'status': 'active',
            'capabilities': ['local_device_link', 'shared_workspaces'],
          }),
          source: EntitlementSource.server,
        ),
      );
      addTearDown(container.dispose);
      await container.read(entitlementProvider.future);

      expect(
        container.read(hasCapabilityProvider(Capabilities.sharedWorkspaces)),
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
