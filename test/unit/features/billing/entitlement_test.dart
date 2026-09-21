import 'package:flutter_test/flutter_test.dart';
import 'package:shellvibe/features/billing/domain/entitlement.dart';

import '../../../support/contract_fixture.dart';

void main() {
  group('decoding the pinned fixtures', () {
    test('the free snapshot carries every shipped capability', () {
      final fixture = ContractFixture.load('entitlements.index');

      final entitlement = Entitlement.fromJson(fixture.data);

      expect(entitlement.plan, BillingPlan.free);
      expect(entitlement.status, BillingStatus.active);
      expect(entitlement.capabilities, Entitlement.freeCapabilities);
      expect(entitlement.limits.maxBackupSizeBytes, 5242880);
      expect(entitlement.limits.maxBackupRevisions, 10);
      expect(entitlement.hasCloudBackup, isTrue);
      expect(entitlement.isPaid, isFalse);
    });

    test('the fixture withholds shared workspaces and nothing else', () {
      // The one capability the free plan does not carry. If this fixture ever
      // shows it, the server has given the team tier away.
      final fixture = ContractFixture.load('entitlements.index');

      final entitlement = Entitlement.fromJson(fixture.data);

      expect(entitlement.has(Capabilities.sharedWorkspaces), isFalse);
    });

    test('the pinned default matches what the server sends', () {
      // `Entitlement.free` is what the app assumes offline. If it drifts from
      // the server's free plan, an offline user sees limits that are not
      // theirs.
      final fixture = ContractFixture.load('entitlements.index');

      expect(Entitlement.fromJson(fixture.data), Entitlement.free);
    });
  });

  group('fail-safe decoding', () {
    test('an empty body decodes to the free plan, not to a crash', () {
      final entitlement = Entitlement.fromJson(const {});

      expect(entitlement.plan, BillingPlan.free);
      expect(entitlement.hasCloudBackup, isTrue);
      expect(entitlement.has(Capabilities.sharedWorkspaces), isFalse);
    });

    test('an unrecognised plan is treated as the lowest tier', () {
      final entitlement = Entitlement.fromJson(const {
        'plan': 'enterprise_ultra',
        'status': 'active',
        'capabilities': ['shared_workspaces'],
      });

      expect(entitlement.plan, BillingPlan.free);
      expect(
        entitlement.has(Capabilities.sharedWorkspaces),
        isTrue,
        reason:
            'The capability list is authoritative for access; only the tier '
            'label was unknown.',
      );
      expect(entitlement.isPaid, isFalse);
    });

    test('an unrecognised status locks what is not free', () {
      final entitlement = Entitlement.fromJson(const {
        'plan': 'team',
        'status': 'something_new',
        'capabilities': ['cloud_backup', 'shared_workspaces'],
      });

      expect(entitlement.status, BillingStatus.unknown);
      expect(entitlement.has(Capabilities.sharedWorkspaces), isFalse);
      expect(
        entitlement.hasCloudBackup,
        isTrue,
        reason: 'A free feature does not depend on the tier being current.',
      );
    });

    test(
      'an expired tier whose capabilities the server echoes stays locked',
      () {
        final entitlement = Entitlement.fromJson(const {
          'plan': 'team',
          'status': 'expired',
          'capabilities': ['shared_workspaces'],
        });

        expect(entitlement.has(Capabilities.sharedWorkspaces), isFalse);
        expect(entitlement.isPaid, isFalse);
      },
    );

    test('a grace period still grants access', () {
      final entitlement = Entitlement.fromJson({
        'plan': 'team',
        'status': 'grace',
        'capabilities': const ['shared_workspaces'],
        'grace_ends_at': DateTime.now()
            .add(const Duration(days: 3))
            .toIso8601String(),
      });

      expect(entitlement.isInGracePeriod, isTrue);
      expect(entitlement.has(Capabilities.sharedWorkspaces), isTrue);
      expect(entitlement.isPaid, isTrue);
      expect(entitlement.graceEndsAt, isNotNull);
    });

    test('junk types in every field decode to the free plan', () {
      final entitlement = Entitlement.fromJson(const {
        'plan': 42,
        'status': ['active'],
        'capabilities': 'cloud_backup',
        'limits': 'none',
        'expires_at': 99,
        'grace_ends_at': {},
      });

      expect(entitlement.plan, BillingPlan.free);
      expect(entitlement.capabilities, isEmpty);
      expect(
        entitlement.limits,
        BillingLimits.freePlan,
        reason:
            'An unreadable limits member must not read as "no quota at all"; '
            'that would take a free feature away over a parse failure.',
      );
      expect(entitlement.expiresAt, isNull);
      expect(entitlement.hasCloudBackup, isTrue);
    });

    test(
      'unknown capability codes survive without unlocking anything else',
      () {
        final entitlement = Entitlement.fromJson(const {
          'plan': 'team',
          'status': 'active',
          'capabilities': ['a_future_capability'],
        });

        expect(entitlement.has('a_future_capability'), isTrue);
        expect(entitlement.has(Capabilities.sharedWorkspaces), isFalse);
      },
    );

    test('numeric limits sent as strings still decode', () {
      final entitlement = Entitlement.fromJson(const {
        'plan': 'pro',
        'status': 'active',
        'limits': {'max_backup_size_bytes': '5242880'},
      });

      expect(entitlement.limits.maxBackupSizeBytes, 5242880);
    });
  });

  group('the free capabilities are never gated', () {
    for (final capability in Entitlement.freeCapabilities) {
      test('the free default grants $capability', () {
        expect(Entitlement.free.has(capability), isTrue);
      });

      test('an empty snapshot grants $capability', () {
        expect(Entitlement.fromJson(const {}).has(capability), isTrue);
      });

      test('an expired tier grants $capability', () {
        final entitlement = Entitlement.fromJson(const {
          'plan': 'team',
          'status': 'expired',
          'capabilities': <String>[],
        });

        expect(
          entitlement.has(capability),
          isTrue,
          reason:
              'A free feature must not switch off because a tier lapsed. '
              'Local Device Link additionally works offline and with no '
              'account at all.',
        );
      });

      test('a snapshot that omits $capability entirely still grants it', () {
        final entitlement = Entitlement.fromJson(const {
          'plan': 'team',
          'status': 'active',
          'capabilities': ['shared_workspaces'],
        });

        expect(entitlement.has(capability), isTrue);
      });

      test('an unknown status grants $capability', () {
        final entitlement = Entitlement.fromJson(const {
          'status': 'nonsense',
          'capabilities': <String>[],
        });

        expect(entitlement.has(capability), isTrue);
      });
    }
  });

  group('round-trip', () {
    test('toJson and fromJson preserve the snapshot', () {
      final original = Entitlement.fromJson({
        'plan': 'team',
        'status': 'active',
        'capabilities': const [
          'local_device_link',
          'cloud_backup',
          'shared_workspaces',
        ],
        'limits': const {
          'max_backup_size_bytes': 15728640,
          'max_backup_revisions': 30,
          'relay_concurrent_sessions': 5,
          'team_seats': 5,
        },
        'expires_at': '2026-12-01T00:00:00.000Z',
        'grace_ends_at': null,
      });

      expect(Entitlement.fromJson(original.toJson()), original);
    });
  });
}
