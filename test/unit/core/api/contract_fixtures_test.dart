import 'dart:convert';
import 'dart:io';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../support/contract_fixture.dart';

/// Integrity of the copied server contract fixtures.
///
/// This guards the *copies*, not the server. It catches a fixture edited
/// locally to make a failing decoder pass -- which would turn the whole
/// contract exercise into a tautology. Server-side drift is only caught by
/// re-syncing; see `test/fixtures/contract/v1/SOURCE.md`.
void main() {
  group('contract fixtures', () {
    test('the directory and its manifest exist', () {
      expect(
        ContractFixture.directory.existsSync(),
        isTrue,
        reason: 'test/fixtures/contract/v1 is missing.',
      );
      expect(File(_manifestPath).existsSync(), isTrue);
    });

    test('the manifest lists exactly the fixtures on disk', () {
      final onDisk = ContractFixture.names().toSet();
      final listed = _manifest().keys
          .map((n) => n.substring(0, n.length - '.json'.length))
          .toSet();

      expect(
        listed.difference(onDisk),
        isEmpty,
        reason: 'The manifest lists fixtures that are not on disk.',
      );
      expect(
        onDisk.difference(listed),
        isEmpty,
        reason: 'These fixtures are not in the manifest. Regenerate it: see '
            'SOURCE.md.',
      );
    });

    test('every fixture matches its recorded SHA-256', () async {
      final sha256 = Sha256();

      for (final entry in _manifest().entries) {
        final bytes = File(
          '${ContractFixture.directory.path}/${entry.key}',
        ).readAsBytesSync();
        final digest = await sha256.hash(bytes);
        final hex = digest.bytes
            .map((b) => b.toRadixString(16).padLeft(2, '0'))
            .join();

        expect(
          hex,
          entry.value,
          reason:
              '${entry.key} was modified locally. Copies are not editable; '
              'change the server and re-sync.',
        );
      }
    });

    test('every fixture carries a status and a body envelope', () {
      final fixtures = ContractFixture.loadAll();

      expect(fixtures, hasLength(32));

      for (final fixture in fixtures) {
        expect(
          fixture.status,
          inInclusiveRange(200, 599),
          reason: '${fixture.name} has no usable HTTP status.',
        );
        expect(
          fixture.body,
          isNotEmpty,
          reason: '${fixture.name} has an empty body.',
        );

        // Success shapes carry `data`; error shapes carry the contract error
        // fields. Nothing in v1 carries neither.
        final isError = fixture.status >= 400;
        if (isError) {
          expect(
            fixture.body.containsKey('code'),
            isTrue,
            reason: '${fixture.name} is an error without a `code`.',
          );
          expect(fixture.body.containsKey('message'), isTrue);
          expect(fixture.body.containsKey('details'), isTrue);
        } else if (!_envelopeExempt.containsKey(fixture.name)) {
          expect(
            fixture.body.containsKey('data'),
            isTrue,
            reason: '${fixture.name} is a success without a `data` member.',
          );
        }
      }
    });

    test('the envelope-exempt fixtures are the ones we expect', () {
      // Guards the exemption list itself: if a future fixture drops its `data`
      // envelope, the test above must fail rather than be quietly excused.
      for (final name in _envelopeExempt.keys) {
        expect(
          ContractFixture.names(),
          contains(name),
          reason: 'Exemption for "$name" is stale; the fixture is gone.',
        );
        expect(
          ContractFixture.load(name).body.containsKey('data'),
          isFalse,
          reason: '"$name" now has a `data` member; drop its exemption.',
        );
      }
    });

    test('every error body carries `details` as an object, never a list', () {
      // The contract documents `{}` for "no extra context". The server builds
      // it as a stdClass, but the fixtures used to pin `[]` because the
      // capture decoded associatively -- which taught this client the wrong
      // shape for the one field every error carries.
      for (final fixture in ContractFixture.loadAll()) {
        if (fixture.status < 400) continue;

        expect(
          fixture.body['details'],
          isA<Map<String, Object?>>(),
          reason: '${fixture.name} pins `details` as something other than an '
              'object.',
        );
      }
    });

    test('the pinned error bodies use the documented codes', () {
      expect(
        ContractFixture.load('error.unauthenticated').body['code'],
        'unauthenticated',
      );
      expect(ContractFixture.load('error.not-found').body['code'], 'not_found');
      expect(
        ContractFixture.load('error.validation').body['code'],
        'validation_failed',
      );
    });
  });
}

/// Success fixtures that legitimately carry no `data` envelope, and why.
///
/// Anything not listed here must use the contract's `{ "data": ... }` shape.
const Map<String, String> _envelopeExempt = {
  'realtime.channel-auth':
      'Shaped by the Pusher channel-authorization protocol that Sockudo '
          'speaks, not by our API contract: the client hands this body '
          'straight to the socket library.',
};

const String _manifestPath = 'test/fixtures/contract/v1/MANIFEST.sha256';

/// Parses `MANIFEST.sha256` into `{filename: hex digest}`.
Map<String, String> _manifest() {
  final lines = const LineSplitter()
      .convert(File(_manifestPath).readAsStringSync())
      .where((l) => l.trim().isNotEmpty);

  return {
    for (final line in lines)
      line.split(RegExp(r'\s+'))[0]: line.split(RegExp(r'\s+'))[1],
  };
}
