/// Error surface of the ShellVibe Server HTTP boundary.
///
/// The server's error body is fixed by the API contract:
///
/// ```json
/// { "code": "...", "message": "...", "details": {}, "request_id": "..." }
/// ```
///
/// Only `code` and documented `details` keys are stable. `message` is a debug
/// summary and explicitly *not* a UI translation key, so nothing in the app may
/// branch on it.
library;

/// Stable machine codes the client branches on.
///
/// The server may add codes within v1, so this is a lookup table and not an
/// enum: an unknown code must stay unknown rather than fail to parse.
abstract final class ApiErrorCode {
  static const String badRequest = 'bad_request';
  static const String unauthenticated = 'unauthenticated';
  static const String forbidden = 'forbidden';
  static const String notFound = 'not_found';
  static const String conflict = 'conflict';
  static const String syncConflict = 'sync_conflict';
  static const String keyRotationRequired = 'key_rotation_required';
  static const String validationFailed = 'validation_failed';
  static const String rateLimited = 'rate_limited';
  static const String internalError = 'internal_error';
  static const String serviceUnavailable = 'service_unavailable';
  static const String syncCursorExpired = 'sync_cursor_expired';
  static const String invalidCredentials = 'invalid_credentials';
  static const String accountOwnsSharedTeam = 'account_owns_shared_team';

  /// Substituted when a response carries no usable `code`, so that callers
  /// always have a non-empty string to switch on.
  static const String unknown = 'unknown_error';
}

/// Base class for every failure raised at the API boundary.
sealed class ApiFailure implements Exception {
  const ApiFailure();

  /// Correlation id from the response, when there was a response. Worth
  /// surfacing in error UI: it is the only handle support has on a request.
  String? get requestId;
}

/// The request never produced an HTTP response: DNS, TCP, TLS, or a timeout.
///
/// Distinct from [ApiException] because it says nothing about the caller's
/// intent being wrong — the same request may well succeed on the next network.
final class ApiTransportException extends ApiFailure {
  /// Human-readable cause, for logs.
  final String reason;

  /// The underlying [Exception] or [Error], kept for logging.
  final Object? cause;

  /// True when the failure was a timeout rather than a refused or dropped
  /// connection.
  final bool timedOut;

  const ApiTransportException(this.reason, {this.cause, this.timedOut = false});

  @override
  String? get requestId => null;

  @override
  String toString() => 'ApiTransportException($reason)';
}

/// The server answered with a non-2xx status and (usually) a contract error
/// body.
final class ApiException extends ApiFailure {
  /// HTTP status code.
  final int statusCode;

  /// Stable `snake_case` machine code, or [ApiErrorCode.unknown].
  final String code;

  /// Debug summary. Never shown as a translated string and never parsed.
  final String message;

  /// Safe extra context. `{}` when the server sent none.
  final Map<String, Object?> details;

  @override
  final String? requestId;

  /// Value of the `Retry-After` header in seconds, when present.
  final int? retryAfterSeconds;

  const ApiException({
    required this.statusCode,
    required this.code,
    required this.message,
    this.details = const {},
    this.requestId,
    this.retryAfterSeconds,
  });

  /// Token missing, invalid or revoked. The caller must drop the stored session.
  bool get isUnauthenticated =>
      code == ApiErrorCode.unauthenticated || statusCode == 401;

  /// Field validation failure; see [validationErrors].
  bool get isValidationFailure => code == ApiErrorCode.validationFailed;

  /// Upload raced another device: the vault head moved.
  bool get isSyncConflict => code == ApiErrorCode.syncConflict;

  /// `429 rate_limited` carries two unrelated meanings on this server.
  ///
  /// `SyncController::putVault` answers an over-quota backup with the same
  /// `rate_limited` code a throttled request gets, and the only thing telling
  /// them apart is that the plan limit sends `details.max_size_bytes`. That is
  /// a fragile seam and the server should grow its own code for it; until then
  /// this getter is where the distinction lives, so no call site has to know.
  bool get isPlanSizeLimit =>
      code == ApiErrorCode.rateLimited && details.containsKey('max_size_bytes');

  /// A genuine throttle: too many requests, retry later.
  bool get isThrottled => code == ApiErrorCode.rateLimited && !isPlanSizeLimit;

  /// Field errors from a `422 validation_failed`, as `{field: [messages]}`.
  ///
  /// Empty for every other failure, so a form can bind to it unconditionally.
  Map<String, List<String>> get validationErrors {
    if (!isValidationFailure) return const {};

    final result = <String, List<String>>{};
    for (final entry in details.entries) {
      final value = entry.value;
      if (value is List) {
        result[entry.key] = value.map((e) => '$e').toList(growable: false);
      } else if (value is String) {
        result[entry.key] = [value];
      }
    }

    return result;
  }

  /// Reads an integer from [details], tolerating the JSON-numeric-as-string
  /// case. Returns null when the key is absent or unparseable.
  int? detailInt(String key) {
    final value = details[key];

    return switch (value) {
      final int v => v,
      final num v => v.toInt(),
      final String v => int.tryParse(v),
      _ => null,
    };
  }

  @override
  String toString() =>
      'ApiException($statusCode $code'
      '${requestId == null ? '' : ', request_id: $requestId'}): $message';
}
