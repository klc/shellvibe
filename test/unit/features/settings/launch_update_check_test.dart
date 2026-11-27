import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shellvibe/features/settings/domain/services/launch_update_check.dart';
import 'package:shellvibe/features/settings/domain/services/update_check_service.dart';
import 'package:shellvibe/shared/storage/secure_storage_service.dart';

/// The launch-time update check: once a day, silent and retried when the feed
/// is unreachable, and quiet about a skipped version.
void main() {
  late Map<String, String> stored;
  late int fetches;
  late String? feed; // null: unreachable
  late DateTime now;

  LaunchUpdateCheck check() => LaunchUpdateCheck(
    service: UpdateCheckService(
      fetch: (_) async {
        fetches++;
        final body = feed;
        if (body == null) throw Exception('offline');
        return body;
      },
    ),
    storage: _MemoryStorage(stored),
    now: () => now,
  );

  String release(String tag) =>
      json.encode({'tag_name': tag, 'html_url': 'https://example.test/$tag'});

  setUp(() {
    stored = {};
    fetches = 0;
    feed = release('v99.0.0');
    now = DateTime.utc(2026, 11, 26, 9);
  });

  test('announces a newer release, then waits a day', () async {
    final update = await check().run();
    expect(update?.version, '99.0.0');
    expect(update?.url, 'https://example.test/v99.0.0');

    now = now.add(const Duration(hours: 23));
    expect(await check().run(), isNull);
    expect(fetches, 1, reason: 'not asked again within the day');

    now = now.add(const Duration(hours: 2));
    expect((await check().run())?.version, '99.0.0');
    expect(fetches, 2);
  });

  test(
    'an unreachable feed is silent and retried at the next launch',
    () async {
      feed = null;
      expect(await check().run(), isNull);
      expect(stored, isNot(contains(LaunchUpdateCheck.lastCheckedKey)));

      feed = release('v99.0.0');
      expect((await check().run())?.version, '99.0.0');
      expect(fetches, 2);
    },
  );

  test('an up-to-date build is told nothing and still waits a day', () async {
    feed = release('v0.0.1');
    expect(await check().run(), isNull);
    expect(stored, contains(LaunchUpdateCheck.lastCheckedKey));
  });

  test('a skipped version stays quiet; the next one is announced', () async {
    await check().skip('99.0.0');
    expect(await check().run(), isNull);

    now = now.add(const Duration(days: 2));
    feed = release('v99.1.0');
    expect((await check().run())?.version, '99.1.0');
  });

  test('a clock set back counts as due', () async {
    await check().run();
    now = now.subtract(const Duration(days: 3));
    await check().run();
    expect(fetches, 2);
  });
}

final class _MemoryStorage extends SecureStorageService {
  final Map<String, String> values;

  _MemoryStorage(this.values) : super(storage: const FlutterSecureStorage());

  @override
  Future<String?> read({required String key}) async => values[key];

  @override
  Future<void> write({required String key, required String value}) async {
    values[key] = value;
  }
}
