import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shellvibe/core/diagnostics/crash_log.dart';

void main() {
  group('CrashLog', () {
    late Directory dir;
    late CrashLog log;

    setUp(() async {
      dir = await Directory.systemTemp.createTemp('crash_log_test');
      log = CrashLog(dir);
    });

    tearDown(() => dir.delete(recursive: true));

    test('a missing log has nothing to offer', () async {
      expect(await log.readUnoffered(), isNull);
      expect(await log.readTail(), isNull);
    });

    test('a crash is offered once, then only what came after it', () async {
      await log.append('FlutterError', StateError('first'), null);

      expect(await log.readUnoffered(), contains('first'));
      await log.markOffered();
      expect(
        await log.readUnoffered(),
        isNull,
        reason: 'Asking about the same crash on every launch is nagging.',
      );

      await log.append('PlatformDispatcher', StateError('second'), null);
      final next = await log.readUnoffered();

      expect(next, contains('second'));
      expect(next, isNot(contains('first')));
    });

    test('a log truncated by hand is offered from its start', () async {
      await log.append('FlutterError', StateError('a long first error'), null);
      await log.markOffered();

      await File('${dir.path}/crash.log').writeAsString('--- x [t] ---\nnew\n');

      expect(await log.readUnoffered(), contains('new'));
    });

    test('the tail keeps the newest text', () async {
      await log.append('FlutterError', StateError('old ${'x' * 200}'), null);
      await log.append('FlutterError', StateError('newest'), null);

      final tail = await log.readTail(maxChars: 60);

      expect(tail, contains('newest'));
      expect(tail!.length, lessThanOrEqualTo(60));
    });
  });

  group('CrashReport.scrub', () {
    test('masks the home directory, user@host pairs and addresses', () {
      const raw =
          'SocketException: Connection refused (address = 10.0.0.12, '
          'port = 22) deploy@db-1.internal\n'
          'PathNotFoundException: /Users/alice/.ssh/id_ed25519\n'
          'C:\\Users\\bob\\AppData\\shellvibe\n'
          '/home/carol/projects\n'
          'fe80:0:0:0:1ff:fe23:4567:890a and ::1';

      final out = CrashReport.scrub(raw);

      for (final leaked in [
        '10.0.0.12',
        'deploy',
        'db-1.internal',
        'alice',
        'bob',
        'carol',
        'fe80',
      ]) {
        expect(out, isNot(contains(leaked)), reason: leaked);
      }
      expect(out, contains('~/.ssh/id_ed25519'));
    });

    test('leaves timestamps and stack frames readable', () {
      const raw =
          '--- 2026-09-25T10:00:00.000 [FlutterError] ---\n'
          '#0      main (package:shellvibe/main.dart:12:5)';

      expect(CrashReport.scrub(raw), raw);
    });

    test('masks the given home directory wherever it sits', () {
      expect(
        CrashReport.scrub('/srv/u/dave/log', homeDirectory: '/srv/u/dave'),
        '~/log',
      );
    });
  });

  group('CrashReport', () {
    CrashReport report(String? log) => CrashReport(
      appVersion: '1.4.0',
      platform: 'macOS',
      osVersion: 'Version 15.6',
      log: log,
    );

    test('is titled after the newest error', () {
      final r = report(
        '--- t1 [FlutterError] ---\nBad state: old\n\n'
        '--- t2 [PlatformDispatcher] ---\nBad state: newest\n#0 main',
      );

      expect(r.title, 'Bad state: newest');
    });

    test('carries the build line and the log in the body', () {
      final body = report('--- t [x] ---\nboom').body();

      expect(body, contains('ShellVibe 1.4.0 · macOS · Version 15.6'));
      expect(body, contains('```text\n--- t [x] ---\nboom\n```'));
    });

    test('a report with no log still opens an issue', () {
      final uri = report(null).issueUri();

      expect(uri.host, 'github.com');
      expect(uri.path, '/${CrashReport.repository}/issues/new');
      expect(uri.queryParameters['title'], 'Problem report');
      expect(uri.queryParameters['body'], isNot(contains('Error log')));
    });

    test('a long log is trimmed to fit a URL GitHub accepts', () {
      final log = '--- t [x] ---\nBad state: boom\n${'#1 frame ü\n' * 3000}';
      final uri = report(log).issueUri();

      expect(
        uri.toString().length,
        lessThanOrEqualTo(CrashReport.maxUrlLength),
      );
      expect(uri.queryParameters['body'], contains('earlier lines cut'));
      expect(uri.queryParameters['title'], 'Bad state: boom');
    });
  });
}
