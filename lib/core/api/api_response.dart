import 'package:flutter/foundation.dart';

/// A decoded 2xx response from the ShellVibe Server.
///
/// The contract fixes two success envelopes: `{ "data": { ... } }` for a single
/// resource and `{ "data": [ ... ], "meta": { ... } }` for a collection. This
/// type carries both so a caller reaches for [dataMap] or [dataList] rather
/// than digging through raw JSON.
@immutable
final class ApiResponse {
  final int statusCode;

  /// `X-Request-ID` from the response. Carried into error reports and logs.
  final String? requestId;

  /// The `data` member: a `Map` for a single resource, a `List` for a
  /// collection, or null when the body carried none.
  final Object? data;

  /// The `meta` member, or `{}` when absent.
  final Map<String, Object?> meta;

  const ApiResponse({
    required this.statusCode,
    this.requestId,
    this.data,
    this.meta = const {},
  });

  /// [data] as a JSON object.
  ///
  /// Returns `{}` rather than throwing when the member is missing: a caller
  /// reading named fields off it will fail on the field it actually needs,
  /// which is the more useful error.
  Map<String, Object?> get dataMap {
    final value = data;

    return value is Map<String, Object?> ? value : const {};
  }

  /// [data] as a list of JSON objects. Non-object entries are dropped.
  List<Map<String, Object?>> get dataList {
    final value = data;
    if (value is! List) return const [];

    return value
        .whereType<Map<String, Object?>>()
        .toList(growable: false);
  }

  /// Reads an integer from [meta], tolerating a numeric string.
  int? metaInt(String key) {
    final value = meta[key];

    return switch (value) {
      final int v => v,
      final num v => v.toInt(),
      final String v => int.tryParse(v),
      _ => null,
    };
  }
}
