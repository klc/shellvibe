import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:xterm3/xterm.dart';

import 'package:terly2/core/network/device_link/device_link_snapshot.dart';

void main() {
  group('DeviceLinkSnapshot', () {
    test('serializes SGR runs including named, 256 and RGB colours', () {
      final terminal = Terminal(maxLines: 32);
      terminal.resize(40, 4);
      terminal.write(
        '\x1b[31mansi-red\x1b[0m '
        '\x1b[1;38;5;196mindexed\x1b[0m '
        '\x1b[38;2;12;34;56;48;5;23mtruecolor\x1b[0m',
      );

      final snapshot = DeviceLinkSnapshot.capture(terminal, scrollbackLines: 4);
      final sgr = snapshot.rows
          .expand((row) => row.runs)
          .map((run) => run.sgr)
          .join();

      expect(sgr, contains('\x1b[0;31m'));
      expect(sgr, contains('\x1b[0;1;38;5;196m'));
      expect(sgr, contains('\x1b[0;38;2;12;34;56;48;5;23m'));
      expect(
        snapshot.rows
            .expand((row) => row.runs)
            .where((run) => run.sgr == '\x1b[0;31m')
            .map((run) => run.text)
            .toList(),
        ['ansi-red'],
      );
      expect(
        snapshot.rows.expand((row) => row.runs).map((run) => run.text).join(),
        contains('indexed'),
      );
    });

    test('preserves wide and combining cells through applyTo', () {
      final source = Terminal(maxLines: 32);
      source.resize(20, 3);
      source.write('A界e\u0301');

      final snapshot = DeviceLinkSnapshot.capture(source, scrollbackLines: 3);
      final destination = Terminal(maxLines: 32);
      snapshot.applyTo(destination);

      final sourceLine = source.buffer.lines[source.buffer.lines.length - 3];
      final destinationLine =
          destination.buffer.lines[destination.buffer.lines.length - 3];
      expect(destinationLine.getCodePoint(0), sourceLine.getCodePoint(0));
      expect(destinationLine.getCodePoint(1), sourceLine.getCodePoint(1));
      expect(destinationLine.getWidth(1), 2);
      expect(destinationLine.getWidth(2), 0);
      expect(destinationLine.getCodePoint(3), sourceLine.getCodePoint(3));
      expect(destinationLine.getCombiningCharacters(3), '\u0301');
    });

    test('preserves wrapped rows, cursor and visibility', () {
      final source = Terminal(maxLines: 32);
      source.resize(5, 3);
      source.write('12345abcdef');
      source.setCursorVisibleMode(false);
      source.setCursor(2, 1);

      final snapshot = DeviceLinkSnapshot.capture(source, scrollbackLines: 3);
      expect(snapshot.rows.any((row) => row.isWrapped), isTrue);

      final destination = Terminal(maxLines: 32);
      snapshot.applyTo(destination);

      expect(destination.cursorVisibleMode, isFalse);
      expect(destination.buffer.cursorX, 2);
      expect(destination.buffer.cursorY, 1);
      var hasWrappedLine = false;
      destination.buffer.lines.forEach((line) {
        hasWrappedLine = hasWrappedLine || line.isWrapped;
      });
      expect(hasWrappedLine, isTrue);
    });

    test('resets SGR before restoring the cursor position', () {
      final snapshot = DeviceLinkSnapshot(
        width: 3,
        height: 1,
        scrollbackLines: 0,
        cursorX: 1,
        cursorY: 0,
        cursorVisible: true,
        usingAlternateBuffer: false,
        modes: const DeviceLinkSnapshotModes(
          autoWrap: true,
          bracketedPaste: false,
          cursorKeys: false,
          mouseMode: MouseMode.none,
          mouseReportMode: MouseReportMode.normal,
        ),
        rows: const [
          DeviceLinkSnapshotRow(
            isWrapped: false,
            runs: [DeviceLinkAnsiRun(sgr: '\x1b[0;31m', text: 'red')],
          ),
        ],
      );

      expect(snapshot.toAnsi(), '\x1b[0;31mred\x1b[0m\x1b[1;2H');
    });

    test('omits trailing blank cells from serialized rows', () {
      final terminal = Terminal(maxLines: 32);
      terminal.resize(40, 2);
      terminal.write('short');

      final snapshot = DeviceLinkSnapshot.capture(terminal);
      final text = snapshot.rows
          .expand((row) => row.runs)
          .map((run) => run.text)
          .join();

      expect(text, 'short');
    });

    test('carries alternate buffer and input modes', () {
      final source = Terminal(maxLines: 32);
      source.resize(12, 3);
      source.write('main');
      source.useAltBuffer();
      source.write('alternate');
      source.setAutoWrapMode(false);
      source.setBracketedPasteMode(true);
      source.setCursorKeysMode(true);
      source.setMouseMode(MouseMode.upDownScrollDrag);
      source.setMouseReportMode(MouseReportMode.sgr);

      final snapshot = DeviceLinkSnapshot.capture(source);
      final destination = Terminal(maxLines: 32);
      snapshot.writeTo(destination);

      expect(destination.isUsingAltBuffer, isTrue);
      expect(destination.autoWrapMode, isFalse);
      expect(destination.bracketedPasteMode, isTrue);
      expect(destination.cursorKeysMode, isTrue);
      expect(destination.mouseMode, MouseMode.upDownScrollDrag);
      expect(destination.mouseReportMode, MouseReportMode.sgr);
      final destinationText = snapshot.rows
          .expand((row) => row.runs)
          .map((run) => run.text)
          .join();
      expect(destinationText, contains('alternate'));
    });

    test('round-trips JSON without losing runs or metadata', () {
      final terminal = Terminal(maxLines: 32);
      terminal.resize(16, 2);
      terminal.write('\x1b[4;38;2;1;2;3mjson\x1b[0m');

      final snapshot = DeviceLinkSnapshot.capture(terminal, scrollbackLines: 2);
      final decoded = DeviceLinkSnapshot.fromJson(
        jsonDecode(snapshot.toJsonString()) as Map<String, Object?>,
      );

      expect(decoded.toJson(), snapshot.toJson());
      expect(decoded.toAnsi(), snapshot.toAnsi());
    });

    test('rejects unsupported snapshot versions', () {
      expect(
        () => DeviceLinkSnapshot.fromJson(<String, Object?>{
          'version': 99,
          'rows': <Object?>[],
        }),
        throwsA(isA<FormatException>()),
      );
    });
  });
}
