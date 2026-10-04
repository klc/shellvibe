import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shellvibe/app/window/single_instance.dart';

void main() {
  late Directory dir;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('single_instance_test');
  });

  tearDown(() async {
    await dir.delete(recursive: true);
  });

  test('a later launch asks the first copy to show itself', () async {
    final activated = Completer<void>();
    final first = await SingleInstance.claim(
      directory: dir,
      name: 'app',
      onActivate: activated.complete,
    );
    expect(first, isNotNull);

    await SingleInstance.activateRunning(File('${dir.path}/app.port'));
    await activated.future.timeout(const Duration(seconds: 2));

    await first!.release();
  });

  test('a caller without the token raises nothing', () async {
    var activations = 0;
    final first = await SingleInstance.claim(
      directory: dir,
      name: 'app',
      onActivate: () => activations++,
    );
    final endpoint =
        jsonDecode(await File('${dir.path}/app.port').readAsString())
            as Map<String, dynamic>;

    final socket = await Socket.connect(
      InternetAddress.loopbackIPv4,
      endpoint['port'] as int,
    );
    socket.writeln('show not-the-token');
    await socket.flush();
    await socket.close();
    await Future<void>.delayed(const Duration(milliseconds: 200));

    expect(activations, 0);
    await first!.release();
  });

  test(
    'an unreachable first copy does not throw at the later launch',
    () async {
      await File(
        '${dir.path}/app.port',
      ).writeAsString(jsonEncode({'port': 1, 'token': 'x'}));
      await SingleInstance.activateRunning(File('${dir.path}/app.port'));
    },
  );

  test('a released claim can be taken again', () async {
    final first = await SingleInstance.claim(
      directory: dir,
      name: 'app',
      onActivate: () {},
    );
    await first!.release();
    final second = await SingleInstance.claim(
      directory: dir,
      name: 'app',
      onActivate: () {},
    );
    expect(second, isNotNull);
    await second!.release();
  });

  test('the lock handle survives an AOT build', () {
    // A test runs under the JIT, which keeps every field, so it cannot see
    // the failure this guards: in a release build the tree shaker dropped
    // the never-read lock field, the handle was collected and closed, and
    // the claim fell away seconds after it was made. The pragma is the fix.
    final source = File(
      'lib/app/window/single_instance.dart',
    ).readAsStringSync();
    expect(
      source,
      matches(
        RegExp(r"@pragma\('vm:entry-point'\)\s+final RandomAccessFile _lock;"),
      ),
    );
  });
}
