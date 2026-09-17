import 'package:flutter_test/flutter_test.dart';
import 'package:shellvibe/features/billing/domain/entitlement.dart';

import '../../../support/contract_fixture.dart';

void main() {
  group('decoding the pinned fixtures', () {
    test('the free snapshot carries only the free capability', () {
      final fixture = ContractFixture.load('entitlements.index');

      final entitlement = Entitlement.fromJson(fixture.data);

      expect(entitlement.plan, BillingPlan.free);
      expect(entitlement.status, BillingStatus.active);
      expect(entitlement.capabilities, {Capabilities.localDeviceLink});
      expect(entitlement.limits.maxBackupSizeBytes, 0);
      expect(entitlement.hasCloudBackup, isFalse);
      expect(entitlement.isPaid, isFalse);
    });

    test('the reconciled pro snapshot unlocks the paid capabilities', () {
      final fixture = ContractFixture.load('billing.reconcile');
      final nested = fixture.data['entitlements'] as Map<String, Object?>;

      final entitlement = Entitlement.fromJson(nested);

      expect(entitlement.plan, BillingPlan.pro);
      expect(entitlement.isPaid, isTrue);
      expect(entitlement.hasCloudBackup, isTrue);
      expect(entitlement.has(Capabilities.remoteDeviceLink), isTrue);
      expect(entitlement.has(Capabilities.sharedWorkspaces), isFalse);
      expect(entitlement.limits.maxBackupSizeBytes, 5242880);
      expect(entitlement.limits.maxBackupRevisions, 10);
    });

    test('a paid snapshot still carries the free capability', () {
      // The server-side regression this mirrors: `pro` used to come back
      // without `local_device_link`, so paying switched off a free feature.
      final fixture = ContractFixture.load('billing.reconcile');
      final nested = fixture.data['entitlements'] as Map<String, Object?>;

      expect(
        Entitlement.fromJson(nested).capabilities,
        contains(Capabilities.localDeviceLink),
      );
    });
  });

  group('fail-safe decoding', () {
    test('an empty body decodes to the free plan, not to a crash', () {
      final entitlement = Entitlement.fromJson(const {});

      expect(entitlement.plan, BillingPlan.free);
      expect(entitlement.hasCloudBackup, isFalse);
    });

    test('an unrecognised plan is treated as the lowest tier', () {
      final entitlement = Entitlement.fromJson(const {
        'plan': 'enterprise_ultra',
        'status': 'active',
        'capabilities': ['cloud_backup'],
      });

      expect(entitlement.plan, BillingPlan.free);
      expect(
        entitlement.hasCloudBackup,
        isTrue,
        reason:
            'The capability list is authoritative for access; only the tier '
            'label was unknown.',
      );
      expect(entitlement.isPaid, isFalse);
    });

    test('an unrecognised status locks every paid capability', () {
      final entitlement = Entitlement.fromJson(const {
        'plan': 'pro',
        'status': 'something_new',
        'capabilities': ['cloud_backup', 'remote_device_link'],
      });

      expect(entitlement.status, BillingStatus.unknown);
      expect(entitlement.hasCloudBackup, isFalse);
      expect(entitlement.has(Capabilities.remoteDeviceLink), isFalse);
    });

    test('an expired plan whose capabilities the server echoes stays locked', () {
      final entitlement = Entitlement.fromJson(const {
        'plan': 'pro',
        'status': 'expired',
        'capabilities': ['cloud_backup'],
      });

      expect(entitlement.hasCloudBackup, isFalse);
      expect(entitlement.isPaid, isFalse);
    });

    test('a grace period still grants access', () {
      final entitlement = Entitlement.fromJson({
        'plan': 'pro',
        'status': 'grace',
        'capabilities': const ['cloud_backup'],
        'grace_ends_at': DateTime.now()
            .add(const Duration(days: 3))
            .toIso8601String(),
      });

      expect(entitlement.isInGracePeriod, isTrue);
      expect(entitlement.hasCloudBackup, isTrue);
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
      expect(entitlement.limits, BillingLimits.none);
      expect(entitlement.expiresAt, isNull);
      expect(entitlement.hasCloudBackup, isFalse);
    });

    test('unknown capability codes survive without unlocking anything else', () {
      final entitlement = Entitlement.fromJson(const {
        'plan': 'pro',
        'status': 'active',
        'capabilities': ['a_future_capability'],
      });

      expect(entitlement.has('a_future_capability'), isTrue);
      expect(entitlement.hasCloudBackup, isFalse);
    });

    test('numeric limits sent as strings still decode', () {
      final entitlement = Entitlement.fromJson(const {
        'plan': 'pro',
        'status': 'active',
        'limits': {'max_backup_size_bytes': '5242880'},
      });

      expect(entitlement.limits.maxBackupSizeBytes, 5242880);
    });
  });

  group('Local Device Link is never gated', () {
    test('the free default grants it', () {
      expect(Entitlement.free.has(Capabilities.localDeviceLink), isTrue);
    });

    test('an empty snapshot grants it', () {
      expect(
        Entitlement.fromJson(const {}).has(Capabilities.localDeviceLink),
        isTrue,
      );
    });

    test('an expired paid plan grants it', () {
      final entitlement = Entitlement.fromJson(const {
        'plan': 'pro',
        'status': 'expired',
        'capabilities': <String>[],
      });

      expect(
        entitlement.has(Capabilities.localDeviceLink),
        isTrue,
        reason:
            'A LAN feature that works offline must not switch off because a '
            'subscription lapsed.',
      );
    });

    test('a snapshot that omits it entirely still grants it', () {
      final entitlement = Entitlement.fromJson(const {
        'plan': 'pro',
        'status': 'active',
        'capabilities': ['cloud_backup'],
      });

      expect(entitlement.has(Capabilities.localDeviceLink), isTrue);
    });

    test('an unknown status grants it', () {
      final entitlement = Entitlement.fromJson(const {
        'status': 'nonsense',
        'capabilities': <String>[],
      });

      expect(entitlement.has(Capabilities.localDeviceLink), isTrue);
    });
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
