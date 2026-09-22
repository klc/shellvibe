import 'dart:convert';
import 'dart:io';

/// One pinned server response, as stored under
/// `test/fixtures/contract/v1/`.
///
/// See that directory's `SOURCE.md`: these are copies of the fixtures
/// `shellvibe-server` generates, and they are the only agreement between the
/// two repositories about response shapes.
final class ContractFixture {
  /// Fixture name without the `.json` suffix, e.g. `sync.vault.put`.
  final String name;

  /// HTTP status the server answers with.
  final int status;

  /// Full response body, including its `data` / `meta` envelope.
  final Map<String, Object?> body;

  const ContractFixture({
    required this.name,
    required this.status,
    required this.body,
  });

  /// The `data` member as a JSON object.
  Map<String, Object?> get data {
    final value = body['data'];

    return value is Map<String, Object?> ? value : const {};
  }

  /// The `data` member as a list of JSON objects.
  List<Map<String, Object?>> get dataList {
    final value = body['data'];
    if (value is! List) return const [];

    return value.whereType<Map<String, Object?>>().toList(growable: false);
  }

  /// The `meta` member, or `{}`.
  Map<String, Object?> get meta {
    final value = body['meta'];

    return value is Map<String, Object?> ? value : const {};
  }

  /// The body re-encoded, for feeding a fake transport the exact bytes the
  /// server would have sent.
  String get rawBody => jsonEncode(body);

  /// Loads the fixture named [name] (no `.json`).
  static ContractFixture load(String name) {
    final file = File('${directory.path}/$name.json');

    if (!file.existsSync()) {
      throw StateError(
        'Contract fixture "$name" does not exist. Re-sync from '
        'shellvibe-server; see test/fixtures/contract/v1/SOURCE.md.',
      );
    }

    final decoded = jsonDecode(file.readAsStringSync());
    if (decoded is! Map<String, Object?>) {
      throw StateError('Contract fixture "$name" is not a JSON object.');
    }

    final status = decoded['status'];
    final body = decoded['body'];

    return ContractFixture(
      name: name,
      status: status is int ? status : 200,
      body: body is Map<String, Object?> ? body : const {},
    );
  }

  /// Every fixture in the directory, sorted by name.
  static List<ContractFixture> loadAll() =>
      names().map(ContractFixture.load).toList(growable: false);

  /// Fixture names present on disk, sorted.
  static List<String> names() {
    final names = directory
        .listSync()
        .whereType<File>()
        .map((f) => f.uri.pathSegments.last)
        .where((n) => n.endsWith('.json'))
        .map((n) => n.substring(0, n.length - '.json'.length))
        .toList();
    names.sort();

    return names;
  }

  /// Location of the copied fixtures, relative to the package root that
  /// `flutter test` runs from.
  static Directory get directory => Directory('test/fixtures/contract/v1');
}
