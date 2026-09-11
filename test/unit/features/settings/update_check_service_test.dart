import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shellvibe/features/settings/domain/services/update_check_service.dart';

String _release({
  required String tag,
  String url = 'https://example.test/releases/tag',
  String? publishedAt,
}) => json.encode({
  'tag_name': tag,
  'html_url': url,
  'published_at': ?publishedAt,
});

UpdateCheckService _serviceReturning(String body) =>
    UpdateCheckService(fetch: (_) async => body);

UpdateCheckService _serviceThrowing(Exception error) =>
    UpdateCheckService(fetch: (_) async => throw error);

void main() {
  group('version arithmetic', () {
    test('normalizes tags down to their numeric core', () {
      expect(UpdateCheckService.normalizeVersion('v1.2.3'), '1.2.3');
      expect(UpdateCheckService.normalizeVersion('1.2.3+7'), '1.2.3');
      expect(UpdateCheckService.normalizeVersion('V1.2.3-beta.1'), '1.2.3');
      expect(UpdateCheckService.normalizeVersion('  1.2.3  '), '1.2.3');
    });

    test('compares segments numerically, not as strings', () {
      // The case a string comparison gets backwards.
      expect(UpdateCheckService.isNewer('1.10.0', '1.9.0'), isTrue);
      expect(UpdateCheckService.isNewer('1.9.0', '1.10.0'), isFalse);
    });

    test('treats missing trailing segments as zero', () {
      expect(UpdateCheckService.isNewer('1.1', '1.0.9'), isTrue);
      expect(UpdateCheckService.isNewer('1.0', '1.0.0'), isFalse);
      expect(UpdateCheckService.isNewer('1.0.0', '1.0'), isFalse);
    });

    test('an equal version is not newer', () {
      expect(UpdateCheckService.isNewer('1.0.0', '1.0.0'), isFalse);
      expect(UpdateCheckService.isNewer('v1.0.0', '1.0.0+9'), isFalse);
    });

    test('refuses to call an unparseable version newer', () {
      // Better to stay quiet than to announce an update that may not exist.
      expect(UpdateCheckService.isNewer('nightly', '1.0.0'), isFalse);
      expect(UpdateCheckService.isNewer('1.0.x', '1.0.0'), isFalse);
      expect(UpdateCheckService.isNewer('', '1.0.0'), isFalse);
    });
  });

  group('check', () {
    test('reports a newer published release', () async {
      final result = await _serviceReturning(
        _release(
          tag: 'v1.1.0',
          url: 'https://example.test/v1.1.0',
          publishedAt: '2026-08-23T10:00:00Z',
        ),
      ).check(currentVersion: '1.0.0');

      expect(result, isA<UpdateAvailable>());
      final available = result as UpdateAvailable;
      expect(available.version, '1.1.0');
      expect(available.url, 'https://example.test/v1.1.0');
      expect(available.publishedAt, DateTime.utc(2026, 8, 23, 10));
    });

    test('reports up to date on an equal or older release', () async {
      expect(
        await _serviceReturning(_release(tag: 'v1.0.0')).check(
          currentVersion: '1.0.0',
        ),
        isA<UpToDate>(),
      );
      expect(
        await _serviceReturning(_release(tag: 'v0.9.0')).check(
          currentVersion: '1.0.0',
        ),
        isA<UpToDate>(),
      );
    });

    test('falls back to the releases page when the tag has no url', () async {
      final result =
          await _serviceReturning(json.encode({'tag_name': 'v2.0.0'})).check(
        currentVersion: '1.0.0',
      );

      expect(
        (result as UpdateAvailable).url,
        contains(UpdateCheckService.releasesRepository),
      );
    });

    test('explains a 404 as no visible releases', () async {
      // What a private repository answers to an unauthenticated caller, which
      // is where this feed points until the source is public.
      final result = await _serviceThrowing(
        const UpdateFeedHttpException(HttpStatus.notFound),
      ).check(currentVersion: '1.0.0');

      expect(result, isA<UpdateCheckUnavailable>());
      expect(
        (result as UpdateCheckUnavailable).reason,
        contains('No published releases'),
      );
    });

    test('explains rate limiting separately from other statuses', () async {
      final limited = await _serviceThrowing(
        const UpdateFeedHttpException(HttpStatus.forbidden),
      ).check(currentVersion: '1.0.0');
      expect(
        (limited as UpdateCheckUnavailable).reason,
        contains('rate limiting'),
      );

      final other = await _serviceThrowing(
        const UpdateFeedHttpException(HttpStatus.internalServerError),
      ).check(currentVersion: '1.0.0');
      expect((other as UpdateCheckUnavailable).reason, contains('HTTP 500'));
    });

    test('turns a network failure into one plain sentence', () async {
      final result = await _serviceThrowing(
        const SocketException('no route to host'),
      ).check(currentVersion: '1.0.0');

      expect(result, isA<UpdateCheckUnavailable>());
      expect(
        (result as UpdateCheckUnavailable).reason,
        contains('Could not reach'),
      );
    });

    test('survives a body that is not the expected shape', () async {
      for (final body in ['not json at all', '[]', '{}', '{"tag_name": ""}']) {
        final result = await _serviceReturning(body).check(
          currentVersion: '1.0.0',
        );
        expect(
          result,
          isA<UpdateCheckUnavailable>(),
          reason: 'body: $body',
        );
      }
    });
  });
}
