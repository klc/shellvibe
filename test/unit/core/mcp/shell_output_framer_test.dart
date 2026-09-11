import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shellvibe/core/mcp/shell/shell_output_framer.dart';

const _nonce = 'a7f3c19d2b4e6081';

List<int> _bytes(String s) => utf8.encode(s);

/// The exact line the command envelope's `printf` emits on stdout.
String _sentinelLine(int exitCode, String cwd, {String nonce = _nonce}) =>
    '\n__TERLY_${nonce}__$exitCode|$cwd\n';

void main() {
  group('sentinel parsing', () {
    test('exit code and cwd are read off the sentinel line', () async {
      final framer = ShellOutputFramer(nonce: _nonce);
      framer.feedStdout(_bytes('hello\n'));
      framer.feedStdout(_bytes(_sentinelLine(0, '/var/log')));

      final match = await framer.sentinel;
      expect(match.exitCode, 0);
      expect(match.cwd, '/var/log');
      expect(framer.stdout, 'hello\n');
    });

    test('a non-zero exit code survives intact', () async {
      final framer = ShellOutputFramer(nonce: _nonce);
      framer.feedStdout(_bytes(_sentinelLine(137, '/')));

      expect((await framer.sentinel).exitCode, 137);
    });

    test('a cwd containing spaces is not split', () async {
      final framer = ShellOutputFramer(nonce: _nonce);
      framer.feedStdout(_bytes(_sentinelLine(0, '/home/me/My Projects/app')));

      expect((await framer.sentinel).cwd, '/home/me/My Projects/app');
    });

    test('a cwd containing a pipe character keeps everything after the first '
        'separator', () async {
      // The envelope writes `<exit>|<cwd>`, so only the FIRST pipe separates
      // the two fields; a pipe inside a path must not truncate it.
      final framer = ShellOutputFramer(nonce: _nonce);
      framer.feedStdout(_bytes(_sentinelLine(0, '/tmp/we|rd')));

      expect((await framer.sentinel).cwd, '/tmp/we|rd');
    });
  });

  group('chunk boundaries', () {
    test('a sentinel split across two chunks is still recognized', () async {
      final framer = ShellOutputFramer(nonce: _nonce);
      final line = _sentinelLine(0, '/srv');
      final split = line.length ~/ 2;

      framer.feedStdout(_bytes(line.substring(0, split)));
      expect(framer.isDone, isFalse, reason: 'half a marker is not a marker');
      framer.feedStdout(_bytes(line.substring(split)));

      final match = await framer.sentinel;
      expect(match.cwd, '/srv');
    });

    test('a sentinel delivered one byte at a time is recognized', () async {
      final framer = ShellOutputFramer(nonce: _nonce);
      for (final byte in _bytes('out\n${_sentinelLine(3, '/opt')}')) {
        framer.feedStdout([byte]);
      }

      final match = await framer.sentinel;
      expect(match.exitCode, 3);
      expect(match.cwd, '/opt');
      expect(framer.stdout, 'out\n');
    });

    test(
      'output held back at a boundary is still released as stdout',
      () async {
        // The framer withholds the trailing bytes of every chunk in case they
        // begin a marker. Anything that turns out not to be one must still
        // reach the caller.
        final framer = ShellOutputFramer(nonce: _nonce);
        framer.feedStdout(_bytes('__TERL'));
        framer.feedStdout(_bytes('Y_not_a_marker\n'));
        framer.feedStdout(_bytes(_sentinelLine(0, '/')));

        await framer.sentinel;
        expect(framer.stdout, contains('__TERLY_not_a_marker'));
      },
    );
  });

  group('false-positive sentinels', () {
    test(
      "a marker carrying another command's nonce is ordinary output",
      () async {
        final framer = ShellOutputFramer(nonce: _nonce);
        framer.feedStdout(
          _bytes(_sentinelLine(0, '/decoy', nonce: 'deadbeef')),
        );
        expect(framer.isDone, isFalse);

        framer.feedStdout(_bytes(_sentinelLine(0, '/real')));

        final match = await framer.sentinel;
        expect(match.cwd, '/real');
        expect(framer.stdout, contains('__TERLY_deadbeef__'));
      },
    );

    test('a bare marker prefix with no nonce does not end the command', () {
      final framer = ShellOutputFramer(nonce: _nonce);
      framer.feedStdout(_bytes('\n__TERLY__0|/spoofed\n'));
      expect(framer.isDone, isFalse);
    });
  });

  group('output cap', () {
    test('under the cap nothing is truncated', () async {
      final framer = ShellOutputFramer(nonce: _nonce, capBytes: 1024);
      framer.feedStdout(_bytes('x' * 500));
      framer.feedStdout(_bytes(_sentinelLine(0, '/')));

      await framer.sentinel;
      expect(framer.truncation, isNull);
      expect(framer.stdout.length, 500);
    });

    test(
      'over the cap keeps the head and the tail and marks the middle',
      () async {
        final framer = ShellOutputFramer(nonce: _nonce, capBytes: 1000);
        framer.feedStdout(_bytes('HEAD${'a' * 5000}TAIL'));
        framer.feedStdout(_bytes(_sentinelLine(0, '/')));

        await framer.sentinel;
        final out = framer.stdout;
        expect(out, startsWith('HEAD'));
        expect(out, endsWith('TAIL'));
        expect(out.length, lessThan(5008));

        final truncation = framer.truncation;
        expect(truncation, isNotNull);
        expect(truncation!.originalBytes, 5008);
        expect(truncation.keptBytes, lessThan(truncation.originalBytes));
      },
    );

    test('stdout and stderr are capped independently', () async {
      final framer = ShellOutputFramer(nonce: _nonce, capBytes: 1000);
      framer.feedStdout(_bytes('o' * 4000));
      framer.feedStderr(_bytes('e' * 100));
      framer.feedStdout(_bytes(_sentinelLine(0, '/')));

      await framer.sentinel;
      // The small stream is untouched even though the other one blew its cap.
      expect(framer.stderr, 'e' * 100);
      expect(framer.truncation, isNotNull);
    });

    test(
      'scanning continues past the cap so the sentinel is still found',
      () async {
        // The drain must never stop early: if it did, the sentinel would land
        // at the head of the next command's output and desynchronize the
        // channel permanently.
        final framer = ShellOutputFramer(nonce: _nonce, capBytes: 100);
        framer.feedStdout(_bytes('z' * 50000));
        framer.feedStdout(_bytes(_sentinelLine(42, '/still/here')));

        final match = await framer.sentinel;
        expect(match.exitCode, 42);
        expect(match.cwd, '/still/here');
      },
    );
  });

  group('robustness', () {
    test('malformed UTF-8 bytes do not throw', () async {
      final framer = ShellOutputFramer(nonce: _nonce);
      // A lone continuation byte and a truncated multi-byte sequence.
      framer.feedStdout([0x80, 0xC3]);
      framer.feedStdout(_bytes(_sentinelLine(0, '/')));

      await framer.sentinel;
      expect(() => framer.stdout, returnsNormally);
    });

    test('chunks fed after the sentinel are ignored', () async {
      final framer = ShellOutputFramer(nonce: _nonce);
      framer.feedStdout(_bytes(_sentinelLine(0, '/')));
      await framer.sentinel;

      framer.feedStdout(_bytes('late output'));
      framer.feedStderr(_bytes('late error'));

      expect(framer.stdout, isNot(contains('late output')));
      expect(framer.stderr, isNot(contains('late error')));
    });

    test('stderr never completes the sentinel', () {
      final framer = ShellOutputFramer(nonce: _nonce);
      framer.feedStderr(_bytes(_sentinelLine(0, '/via-stderr')));
      expect(framer.isDone, isFalse);
    });
  });
}
