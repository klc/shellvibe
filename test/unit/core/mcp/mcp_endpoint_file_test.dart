// Branches on the host OS, so CI runs it on macOS and Windows as well as
// Linux on every pull request (`--tags platform`).
@TestOn('posix')
@Tags(['platform'])
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shellvibe/core/mcp/mcp_endpoint_file.dart';

/// The POSIX mode bits of [path], as the four-digit string `chmod` takes.
Future<String> _mode(String path) async {
  // `stat` speaks a different dialect on BSD/macOS than on GNU/Linux, so ask
  // for the one field this needs in whichever form the host understands.
  final result = Platform.isMacOS
      ? await Process.run('stat', ['-f', '%OLp', path])
      : await Process.run('stat', ['-c', '%a', path]);
  expect(result.exitCode, 0, reason: 'stat failed: ${result.stderr}');
  return (result.stdout as String).trim().padLeft(4, '0');
}

void main() {
  late Directory tempDir;
  late String endpointPath;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('mcp_endpoint_test');
    endpointPath = '${tempDir.path}/nested/mcp-endpoint.json';
  });

  tearDown(() async {
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  group('McpEndpointFile.write', () {
    test('locks the file to 0600 and its directory to 0700', () async {
      await McpEndpointFile.write(
        port: 8123,
        token: 'secret-token',
        pid: 4242,
        path: endpointPath,
      );

      expect(await _mode(endpointPath), '0600');
      expect(await _mode(File(endpointPath).parent.path), '0700');
    });

    test('round-trips through read', () async {
      await McpEndpointFile.write(
        port: 8123,
        token: 'secret-token',
        pid: 4242,
        path: endpointPath,
      );

      final data = await McpEndpointFile.read(endpointPath);
      expect(data, isNotNull);
      expect(data!.port, 8123);
      expect(data.token, 'secret-token');
      expect(data.pid, 4242);
    });

    test('never lets the token touch a file at default permissions', () async {
      // Rewriting over a file someone else left at 0644 is the case the
      // create-empty-then-chmod-then-write order exists for: if the token
      // were written first, it would sit there world-readable until the
      // chmod landed.
      final file = File(endpointPath);
      await file.parent.create(recursive: true);
      await file.writeAsString('stale');
      await Process.run('chmod', ['0644', endpointPath]);

      await McpEndpointFile.write(
        port: 9000,
        token: 'fresh-token',
        pid: 7,
        path: endpointPath,
      );

      expect(await _mode(endpointPath), '0600');
      final decoded =
          json.decode(await file.readAsString()) as Map<String, dynamic>;
      expect(decoded['token'], 'fresh-token');
    });

  });

  group('McpEndpointFile.delete', () {
    test('removes the file and tolerates a missing one', () async {
      await McpEndpointFile.write(
        port: 1,
        token: 't',
        pid: 1,
        path: endpointPath,
      );
      await McpEndpointFile.delete(endpointPath);
      expect(File(endpointPath).existsSync(), isFalse);

      await McpEndpointFile.delete(endpointPath);
    });
  });
}
