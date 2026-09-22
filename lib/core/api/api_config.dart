/// Configuration for the ShellVibe Server HTTP boundary.
///
/// The base URL is a compile-time define rather than a runtime setting: a
/// bearer token issued by one host must never be replayed against another, and
/// a field that the user (or anything reading a config file) can point
/// somewhere else is exactly that replay. Override it at build time:
///
/// ```sh
/// flutter run --dart-define=SHELLVIBE_API_BASE_URL=https://api.localhost
/// ```
library;

/// Immutable API configuration resolved from `--dart-define`.
abstract final class ApiConfig {
  /// Production control plane. `api.shellvibe.dev` terminates TLS at Caddy in
  /// front of Laravel Octane.
  static const String defaultBaseUrl = 'https://api.shellvibe.dev';

  /// The base URL every request is resolved against, without a trailing slash.
  static final String baseUrl = _normalize(
    const String.fromEnvironment(
      'SHELLVIBE_API_BASE_URL',
      defaultValue: defaultBaseUrl,
    ),
  );

  /// All application endpoints live under this prefix (API contract v1 §Genel
  /// kurallar).
  static const String versionPrefix = '/api/v1';

  /// Time to establish the TCP/TLS connection.
  static const Duration connectionTimeout = Duration(seconds: 10);

  /// Time to receive the complete response body once connected. Deliberately
  /// longer than [connectionTimeout]: a vault revision is a single large JSON
  /// body, and a slow mobile uplink is not a failure.
  static const Duration responseTimeout = Duration(seconds: 60);

  /// True when [baseUrl] points at the local development stack, whose Caddy
  /// signs certificates with an internal CA no OS trust store knows.
  static final bool isLocalDevelopmentHost = _isLocalHost(baseUrl);

  /// Resolves [path] (for example `/entitlements`) into an absolute URL under
  /// [versionPrefix].
  static Uri resolve(String path, {Map<String, String>? query}) {
    final normalized = path.startsWith('/') ? path : '/$path';

    return Uri.parse('$baseUrl$versionPrefix$normalized').replace(
      queryParameters: (query == null || query.isEmpty) ? null : query,
    );
  }

  static String _normalize(String value) {
    final trimmed = value.trim();
    final withoutTrailingSlash = trimmed.endsWith('/')
        ? trimmed.substring(0, trimmed.length - 1)
        : trimmed;

    return withoutTrailingSlash.isEmpty ? defaultBaseUrl : withoutTrailingSlash;
  }

  static bool _isLocalHost(String value) {
    final host = Uri.tryParse(value)?.host ?? '';

    return host == 'localhost' ||
        host.endsWith('.localhost') ||
        host == '127.0.0.1' ||
        host == '::1' ||
        host == '10.0.2.2'; // Android emulator's route to the host machine.
  }
}
