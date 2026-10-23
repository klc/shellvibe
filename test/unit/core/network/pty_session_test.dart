// Drives a real PTY, so it only runs where one exists; CI runs it on macOS and
// Linux on every pull request (`--tags platform`).
@Tags(['platform'])
library;

import 'dart:async';
import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:shellvibe/core/network/pty_session.dart';

/// The PTY plugin, whose native library `flutter test` does not build.
const _plugin = 'flutter_pty2';

void main() {
  late Directory nativeDir;
  late Directory originalCwd;

  setUpAll(() async {
    // Builds the plugin's single C translation unit and puts it where the
    // plugin's own loader looks: `<name>.framework/<name>` relative to the
    // working directory on macOS, an already-loaded soname on Linux.
    // `Isolate.resolvePackageUri` is unsupported under `flutter test`.
    final configFile = File('.dart_tool/package_config.json');
    final config = jsonDecode(await configFile.readAsString()) as Map;
    final package = (config['packages'] as List).cast<Map>().singleWhere(
      (p) => p['name'] == _plugin,
    );
    final root = configFile.absolute.uri.resolve('${package['rootUri']}/');
    final source = File.fromUri(root.resolve('src/flutter_pty.c'));
    originalCwd = Directory.current;
    nativeDir = await Directory.systemTemp.createTemp('pty_session_test');
    final out = Platform.isMacOS
        ? '${nativeDir.path}/$_plugin.framework/$_plugin'
        : '${nativeDir.path}/lib$_plugin.so';
    await File(out).parent.create(recursive: true);
    final cc = await Process.run('cc', [
      '-shared',
      '-fPIC',
      '-DDART_SHARED_LIB',
      if (Platform.isLinux) '-Wl,-soname,lib$_plugin.so',
      if (Platform.isLinux) '-lpthread',
      '-o',
      out,
      source.path,
    ]);
    expect(cc.exitCode, 0, reason: '${cc.stderr}');
    if (Platform.isMacOS) {
      Directory.current = nativeDir;
    } else {
      DynamicLibrary.open(out);
    }
  });

  tearDownAll(() async {
    Directory.current = originalCwd;
    await nativeDir.delete(recursive: true);
  });

  test(
    'a paste larger than the tty input queue reaches the process',
    () async {
      // Tags the child so a deadlocked run can still be killed: the reader
      // isolate stuck in a blocking write only returns once the child dies.
      final tag = 'pty-session-test-${DateTime.now().microsecondsSinceEpoch}';
      addTearDown(() => Process.run('pkill', ['-f', tag]));

      final session = await PtyIsolateSession.start(
        PtySessionConfig(
          executable: '/bin/sh',
          arguments: ['-c', 'cat # $tag'],
          workingDirectory: null,
          environment: Platform.environment,
          rows: 24,
          columns: 80,
        ),
      );

      const marker = 'END-OF-PASTE';
      final seen = Completer<void>();
      final received = StringBuffer();
      // Consumed and acknowledged batch by batch, as TerminalLocalPtyBridge
      // does.
      final subscription = session.output.listen((batch) {
        received.write(utf8.decode(batch, allowMalformed: true));
        session.acknowledge();
        if (!seen.isCompleted && received.toString().contains(marker)) {
          seen.complete();
        }
      });

      // 64 KiB of short lines in one write, far past the ~1 KiB the tty
      // accepts before the writer has to wait for the process to read.
      final line = '${'x' * 63}\n';
      final paste = Uint8List.fromList(utf8.encode(line * 1024));
      session.write(paste);
      session.write(Uint8List.fromList(utf8.encode('$marker\n')));

      await expectLater(
        seen.future.timeout(const Duration(seconds: 5)),
        completes,
      );

      await subscription.cancel();
      await session.dispose();
    },
    timeout: const Timeout(Duration(seconds: 20)),
    skip: Platform.isWindows,
  );
}
