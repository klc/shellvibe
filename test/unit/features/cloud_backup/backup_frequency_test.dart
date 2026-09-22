import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shellvibe/features/cloud_backup/data/cloud_backup_store.dart';
import 'package:shellvibe/shared/storage/secure_storage_service.dart';

/// The schedule a backup runs on, and the mark that decides whether one is
/// due.
///
/// The mark carries a clock as well as a time because "is one due" and "is
/// there anything to write" are two questions. An hourly backup that skips the
/// second one writes the same bytes every hour and turns a ten revision window
/// into ten copies of one state -- which is not a history, and is the thing a
/// revision list exists to give someone.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late CloudBackupStore store;

  setUp(() {
    FlutterSecureStorage.setMockInitialValues({});
    store = CloudBackupStore(storage: SecureStorageService());
  });

  group('the schedule', () {
    test('is off until it is chosen', () async {
      // A feature shipping is not a reason to start writing to someone's
      // account on a schedule they did not pick.
      expect(await store.readBackupFrequency(), BackupFrequency.off);
    });

    test('survives a round trip', () async {
      await store.writeBackupFrequency(BackupFrequency.daily);

      expect(await store.readBackupFrequency(), BackupFrequency.daily);
    });

    test('an unknown value reads as off rather than as something', () async {
      // Written by a build that had an option this one does not. Guessing at
      // it would run a schedule nobody here can describe.
      await SecureStorageService().write(
        key: 'shellvibe_backup_frequency',
        value: 'fortnightly',
      );

      expect(await store.readBackupFrequency(), BackupFrequency.off);
    });

    test('off has no interval, and every other option does', () {
      expect(BackupFrequency.off.interval, isNull);

      for (final frequency in BackupFrequency.values) {
        if (frequency == BackupFrequency.off) continue;
        expect(frequency.interval, isNotNull, reason: frequency.name);
      }
    });

    test('the wire names are stable, not the Dart identifiers', () {
      // Renaming an enum value must not change what a stored schedule means.
      expect(BackupFrequency.values.map((f) => f.wireName), [
        'off',
        'hourly',
        'daily',
        'weekly',
      ]);
    });

    test('each option says what it actually promises', () {
      // There is no background task, so "daily" is "once a day, the first
      // time you open the app". A schedule that quietly does not happen on a
      // device nobody opened is worse than one that says so.
      for (final frequency in BackupFrequency.values) {
        expect(frequency.promise, isNotEmpty, reason: frequency.name);
      }
    });
  });

  group('the mark', () {
    test('is absent until a scheduled backup has run', () async {
      expect(await store.readAutoBackupMark(), isNull);
    });

    test('carries both the time and the clock', () async {
      final at = DateTime.parse('2026-09-19T10:30:00.000Z');
      await store.writeAutoBackupMark(at: at, clock: 1234);

      final mark = await store.readAutoBackupMark();

      expect(mark, isNotNull);
      expect(mark!.at.toUtc(), at);
      expect(mark.clock, 1234);
    });

    test('a corrupt mark reads as none rather than as zero', () async {
      // Zero would mean "nothing has changed since clock zero", which is the
      // one reading that makes a device stop backing up.
      await SecureStorageService().write(
        key: 'shellvibe_backup_auto_mark',
        value: 'not-a-mark',
      );

      expect(await store.readAutoBackupMark(), isNull);
    });

    test('clearing the device forgets it with everything else', () async {
      await store.writeBackupFrequency(BackupFrequency.weekly);
      await store.writeAutoBackupMark(at: DateTime.now(), clock: 7);

      await store.clear();

      expect(await store.readAutoBackupMark(), isNull);

      // The schedule too. A device whose vault was deleted that still
      // believes it backs up weekly starts writing again the moment a
      // passphrase is set on it, without anyone choosing that.
      expect(await store.readBackupFrequency(), BackupFrequency.off);
    });
  });
}
