import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/constants/app_constants.dart';

/// Fetches the body of [url] as text. Replaced in tests so the version
/// comparison can be exercised without a network; a fake signals a non-200
/// answer by throwing [UpdateFeedHttpException].
typedef ReleaseFetcher = Future<String> Function(Uri url);

/// The update feed answered with something other than 200.
class UpdateFeedHttpException implements Exception {
  const UpdateFeedHttpException(this.statusCode);

  final int statusCode;

  @override
  String toString() => 'UpdateFeedHttpException($statusCode)';
}

/// Outcome of asking the release feed what the newest published version is.
sealed class UpdateCheckResult {
  const UpdateCheckResult();
}

/// A newer release than the running build is published.
final class UpdateAvailable extends UpdateCheckResult {
  const UpdateAvailable({
    required this.version,
    required this.url,
    this.publishedAt,
  });

  /// Version of the newest release, without the tag's leading `v`.
  final String version;

  /// Page a human should be sent to in order to get it.
  final String url;

  final DateTime? publishedAt;
}

/// The running build is the newest published one, or newer than it.
final class UpToDate extends UpdateCheckResult {
  const UpToDate(this.version);

  final String version;
}

/// The feed could not be consulted. Carries a sentence fit to show a user.
final class UpdateCheckUnavailable extends UpdateCheckResult {
  const UpdateCheckUnavailable(this.reason);

  final String reason;
}

/// Asks GitHub which release is newest and compares it to this build.
///
/// This is a manual check behind a button, never a background poll: the
/// application makes no network request the user did not ask for, and an
/// update check that runs on its own is a request that reports back when the
/// app was last launched.
///
/// **The repository this points at is not public yet.** GitHub answers an
/// unauthenticated request for a private repository's releases with 404 — the
/// same answer it gives for a repository that does not exist, deliberately, so
/// that a 404 reveals nothing. Until the source moves to its public home the
/// check therefore reports that no published releases are visible, which is
/// the honest answer. Embedding a token to work around this is not an option:
/// a token shipped inside a distributed binary is a published token. When the
/// repository becomes public, [releasesRepository] is the only line that has
/// to change.
class UpdateCheckService {
  UpdateCheckService({ReleaseFetcher? fetch}) : _fetch = fetch ?? _httpGet;

  final ReleaseFetcher _fetch;

  /// `owner/name` of the repository whose releases are the update feed.
  static const String releasesRepository = 'klc/shellvibe';

  static const Duration _timeout = Duration(seconds: 10);

  Uri get _latestReleaseUrl =>
      Uri.https('api.github.com', '/repos/$releasesRepository/releases/latest');

  /// Compares [currentVersion] against the newest published release.
  Future<UpdateCheckResult> check({
    String currentVersion = AppConstants.appVersion,
  }) async {
    final String body;
    try {
      body = await _fetch(_latestReleaseUrl).timeout(_timeout);
    } on UpdateFeedHttpException catch (e) {
      if (e.statusCode == HttpStatus.notFound) {
        return const UpdateCheckUnavailable(
          'No published releases are visible yet.',
        );
      }
      if (e.statusCode == HttpStatus.forbidden) {
        // Unauthenticated calls are rate limited per IP; the limit resets
        // within the hour and there is nothing for the user to fix.
        return const UpdateCheckUnavailable(
          'GitHub is rate limiting update checks right now. Try again later.',
        );
      }
      return UpdateCheckUnavailable(
        'The update feed answered with HTTP ${e.statusCode}.',
      );
    } on Object {
      // Offline, DNS failure, TLS failure, timeout: all the same to the user,
      // and none of them worth spelling out in a dialog.
      return const UpdateCheckUnavailable(
        'Could not reach the update feed. Check your connection.',
      );
    }

    final Map<String, dynamic> release;
    try {
      final decoded = json.decode(body);
      if (decoded is! Map<String, dynamic>) throw const FormatException();
      release = decoded;
    } on FormatException {
      return const UpdateCheckUnavailable(
        'The update feed returned something unreadable.',
      );
    }

    final tag = release['tag_name'];
    if (tag is! String || tag.isEmpty) {
      return const UpdateCheckUnavailable(
        'The update feed returned no version.',
      );
    }

    final latest = normalizeVersion(tag);
    if (!isNewer(latest, currentVersion)) return UpToDate(currentVersion);

    final url = release['html_url'];
    final publishedAt = release['published_at'];
    return UpdateAvailable(
      version: latest,
      url: url is String && url.isNotEmpty
          ? url
          : 'https://github.com/$releasesRepository/releases',
      publishedAt: publishedAt is String
          ? DateTime.tryParse(publishedAt)
          : null,
    );
  }

  /// Strips a release tag down to its dotted numeric core: `v1.2.3` and
  /// `1.2.3+7` both become `1.2.3`. The build number is deliberately dropped —
  /// it distinguishes store uploads of the same release, not releases.
  @visibleForTesting
  static String normalizeVersion(String raw) {
    var version = raw.trim();
    if (version.startsWith('v') || version.startsWith('V')) {
      version = version.substring(1);
    }
    final plus = version.indexOf('+');
    if (plus != -1) version = version.substring(0, plus);
    final dash = version.indexOf('-');
    if (dash != -1) version = version.substring(0, dash);
    return version;
  }

  /// Whether [candidate] is a strictly higher version than [current].
  ///
  /// Compares numerically segment by segment, so `1.10.0` sorts above `1.9.0`
  /// where a string comparison would get it backwards. A segment that is not
  /// a number makes the whole comparison unsafe, and an unsafe comparison
  /// answers "not newer" — nagging a user about an update that may not exist
  /// is worse than staying quiet.
  @visibleForTesting
  static bool isNewer(String candidate, String current) {
    final a = _segments(normalizeVersion(candidate));
    final b = _segments(normalizeVersion(current));
    if (a == null || b == null) return false;

    for (var i = 0; i < (a.length > b.length ? a.length : b.length); i++) {
      final left = i < a.length ? a[i] : 0;
      final right = i < b.length ? b[i] : 0;
      if (left != right) return left > right;
    }
    return false;
  }

  static List<int>? _segments(String version) {
    if (version.isEmpty) return null;
    final parts = version.split('.');
    final out = <int>[];
    for (final part in parts) {
      final value = int.tryParse(part);
      if (value == null || value < 0) return null;
      out.add(value);
    }
    return out;
  }

  static Future<String> _httpGet(Uri url) async {
    final client = HttpClient()..connectionTimeout = _timeout;
    try {
      final request = await client.getUrl(url);
      // GitHub requires a User-Agent and answers 403 without one.
      request.headers.set(HttpHeaders.userAgentHeader, _userAgent);
      request.headers.set(
        HttpHeaders.acceptHeader,
        'application/vnd.github+json',
      );
      final response = await request.close();
      if (response.statusCode != HttpStatus.ok) {
        await response.drain<void>();
        throw UpdateFeedHttpException(response.statusCode);
      }
      return await response.transform(utf8.decoder).join();
    } finally {
      client.close(force: true);
    }
  }

  static String get _userAgent =>
      '${AppConstants.appName}/${AppConstants.appVersion}';
}

final updateCheckServiceProvider = Provider<UpdateCheckService>(
  (ref) => UpdateCheckService(),
);
