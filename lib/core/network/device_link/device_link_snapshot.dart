import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:xterm3/xterm.dart';

/// A terminal snapshot encoded as rows of ANSI text and complete SGR runs.
///
/// The snapshot intentionally uses the public xterm3 buffer API. It does not
/// retain xterm3's private buffer implementation, so it can be sent to a
/// second [Terminal] instance without coupling Device Link to xterm3 internals.
final class DeviceLinkSnapshot {
  static const int formatVersion = 1;

  DeviceLinkSnapshot({
    required this.width,
    required this.height,
    required this.scrollbackLines,
    required this.cursorX,
    required this.cursorY,
    required this.cursorVisible,
    required this.usingAlternateBuffer,
    required this.modes,
    required this.rows,
  }) {
    if (width <= 0) throw ArgumentError.value(width, 'width');
    if (height <= 0) throw ArgumentError.value(height, 'height');
    if (scrollbackLines < 0) {
      throw ArgumentError.value(scrollbackLines, 'scrollbackLines');
    }
    if (cursorX < 0 || cursorX >= width) {
      throw ArgumentError.value(cursorX, 'cursorX');
    }
    if (cursorY < 0 || cursorY >= height) {
      throw ArgumentError.value(cursorY, 'cursorY');
    }
    if (rows.isEmpty) throw ArgumentError.value(rows, 'rows');
  }

  factory DeviceLinkSnapshot.capture(
    Terminal terminal, {
    int scrollbackLines = 400,
  }) {
    if (scrollbackLines < 0) {
      throw ArgumentError.value(scrollbackLines, 'scrollbackLines');
    }

    final buffer = terminal.buffer;
    final firstLine = math.max(
      0,
      buffer.lines.length - (scrollbackLines + terminal.viewHeight),
    );
    final rows = <DeviceLinkSnapshotRow>[];
    for (var index = firstLine; index < buffer.lines.length; index++) {
      final line = buffer.lines[index];
      // A row whose successor is a continuation has to be emitted at full
      // width: the replay relies on the terminal wrapping naturally instead of
      // writing a newline, and trailing blanks are trimmed away otherwise. A
      // wide glyph that did not fit at the right edge leaves exactly such a
      // blank behind (xterm3 writes a code-point-0 filler cell before it
      // wraps), so without the padding every CJK or emoji line break would
      // pull the rest of the snapshot one column to the left.
      final continues =
          index + 1 < buffer.lines.length && buffer.lines[index + 1].isWrapped;
      rows.add(
        DeviceLinkSnapshotRow(
          isWrapped: line.isWrapped && index != firstLine,
          runs: _serializeLine(
            line,
            terminal.viewWidth,
            padToWidth: continues,
          ),
        ),
      );
    }

    return DeviceLinkSnapshot(
      width: terminal.viewWidth,
      height: terminal.viewHeight,
      scrollbackLines: math.min(scrollbackLines, buffer.scrollBack),
      cursorX: buffer.cursorX,
      cursorY: buffer.cursorY,
      cursorVisible: terminal.cursorVisibleMode,
      usingAlternateBuffer: terminal.isUsingAltBuffer,
      modes: DeviceLinkSnapshotModes(
        autoWrap: terminal.autoWrapMode,
        bracketedPaste: terminal.bracketedPasteMode,
        cursorKeys: terminal.cursorKeysMode,
        mouseMode: terminal.mouseMode,
        mouseReportMode: terminal.mouseReportMode,
      ),
      rows: rows,
    );
  }

  factory DeviceLinkSnapshot.fromJson(Map<String, Object?> json) {
    final version = _requiredInt(json, 'version');
    if (version != formatVersion) {
      throw FormatException(
        'Unsupported Device Link snapshot version: $version',
      );
    }

    final rawRows = json['rows'];
    if (rawRows is! List) throw const FormatException('rows must be a list');

    return DeviceLinkSnapshot(
      width: _requiredInt(json, 'width'),
      height: _requiredInt(json, 'height'),
      scrollbackLines: _requiredInt(json, 'scrollbackLines'),
      cursorX: _requiredInt(json, 'cursorX'),
      cursorY: _requiredInt(json, 'cursorY'),
      cursorVisible: _requiredBool(json, 'cursorVisible'),
      usingAlternateBuffer: _requiredBool(json, 'usingAlternateBuffer'),
      modes: DeviceLinkSnapshotModes.fromJson(_requiredObject(json, 'modes')),
      rows: rawRows
          .map((row) => DeviceLinkSnapshotRow.fromJson(_asObject(row, 'row')))
          .toList(growable: false),
    );
  }

  final int width;
  final int height;
  final int scrollbackLines;
  final int cursorX;
  final int cursorY;
  final bool cursorVisible;
  final bool usingAlternateBuffer;
  final DeviceLinkSnapshotModes modes;
  final List<DeviceLinkSnapshotRow> rows;

  /// Returns a JSON-safe representation suitable for Device Link control data.
  Map<String, Object?> toJson() => <String, Object?>{
    'version': formatVersion,
    'width': width,
    'height': height,
    'scrollbackLines': scrollbackLines,
    'cursorX': cursorX,
    'cursorY': cursorY,
    'cursorVisible': cursorVisible,
    'usingAlternateBuffer': usingAlternateBuffer,
    'modes': modes.toJson(),
    'rows': rows.map((row) => row.toJson()).toList(growable: false),
  };

  String toJsonString() => jsonEncode(toJson());

  /// UTF-8 JSON payload for the `0x03` Device Link binary snapshot frame.
  ///
  /// The one-time attach snapshot must carry buffer metadata (alternate
  /// screen, wrapping and input modes) in addition to visible ANSI text.
  /// Sending the JSON representation lets the receiving terminal restore that
  /// state before live PTY bytes arrive; the high-frequency output path stays
  /// raw bytes.
  Uint8List toUtf8Bytes() => Uint8List.fromList(utf8.encode(toJsonString()));

  /// ANSI/SGR stream that reconstructs this snapshot when written to a
  /// terminal with matching dimensions.
  String toAnsi() {
    final output = StringBuffer();
    for (var index = 0; index < rows.length; index++) {
      final row = rows[index];
      if (index > 0 && !row.isWrapped) output.write('\r\n');
      for (final run in row.runs) {
        output
          ..write(run.sgr)
          ..write(run.text);
      }
    }
    // Do not let the final cell style leak into live PTY bytes written after
    // the snapshot. CUP itself does not reset SGR state.
    output.write('\x1b[0m\x1b[${cursorY + 1};${cursorX + 1}H');
    return output.toString();
  }

  /// Applies the snapshot through xterm3's public [Terminal.write] and mode
  /// APIs. Existing main/alternate buffers are cleared before reconstruction.
  void applyTo(Terminal terminal) {
    terminal.resize(width, height);

    terminal.useMainBuffer();
    terminal.clear();
    if (usingAlternateBuffer) {
      terminal.useAltBuffer();
      terminal.clear();
    }

    // Re-enable wrapping while writing rows so a row marked as wrapped keeps
    // xterm3's native wrapped-line semantics. The recorded mode is restored
    // immediately after the stream has been written.
    terminal.setAutoWrapMode(true);
    terminal.write(toAnsi());

    terminal.setAutoWrapMode(modes.autoWrap);
    terminal.setBracketedPasteMode(modes.bracketedPaste);
    terminal.setCursorKeysMode(modes.cursorKeys);
    terminal.setMouseMode(modes.mouseMode);
    terminal.setMouseReportMode(modes.mouseReportMode);
    terminal.setCursorVisibleMode(cursorVisible);
    terminal.setCursor(cursorX, cursorY);
  }

  /// Alias for call sites that use stream-oriented terminology.
  void writeTo(Terminal terminal) => applyTo(terminal);

  static List<DeviceLinkAnsiRun> _serializeLine(
    BufferLine line,
    int width, {
    bool padToWidth = false,
  }) {
    final runs = <DeviceLinkAnsiRun>[];
    final text = StringBuffer();
    _AnsiStyle? currentStyle;

    void flush() {
      if (currentStyle == null || text.isEmpty) return;
      runs.add(currentStyle.run(text.toString()));
      text.clear();
    }

    final trimmedLength = padToWidth
        ? width
        : math.min(width, line.getTrimmedLength(width));
    for (var index = 0; index < trimmedLength; index++) {
      // xterm3 represents the second half of a wide glyph as width 0, and the
      // lead cell already emitted the glyph — but an erased or never-written
      // cell is width 0 as well, and that one still occupies a column. Only
      // the cell *following a wide glyph* may be dropped; treating every
      // zero-width cell as skippable silently shortens the row.
      if (line.getWidth(index) == 0 &&
          index > 0 &&
          line.getWidth(index - 1) == 2) {
        continue;
      }

      final style = _AnsiStyle(
        line.getForeground(index),
        line.getBackground(index),
        line.getUnderlineColor(index),
        line.getAttributes(index) & CellAttr.visualMask,
      );
      if (style != currentStyle) {
        flush();
        currentStyle = style;
      }

      final codePoint = line.getCodePoint(index);
      text.write(codePoint == 0 ? ' ' : String.fromCharCode(codePoint));
      final combining = line.getCombiningCharacters(index);
      if (combining != null) text.write(combining);
    }
    flush();
    return runs;
  }
}

final class DeviceLinkSnapshotModes {
  const DeviceLinkSnapshotModes({
    required this.autoWrap,
    required this.bracketedPaste,
    required this.cursorKeys,
    required this.mouseMode,
    required this.mouseReportMode,
  });

  factory DeviceLinkSnapshotModes.fromJson(Map<String, Object?> json) {
    return DeviceLinkSnapshotModes(
      autoWrap: _requiredBool(json, 'autoWrap'),
      bracketedPaste: _requiredBool(json, 'bracketedPaste'),
      cursorKeys: _requiredBool(json, 'cursorKeys'),
      mouseMode: _enumValue(MouseMode.values, json['mouseMode'], 'mouseMode'),
      mouseReportMode: _enumValue(
        MouseReportMode.values,
        json['mouseReportMode'],
        'mouseReportMode',
      ),
    );
  }

  final bool autoWrap;
  final bool bracketedPaste;
  final bool cursorKeys;
  final MouseMode mouseMode;
  final MouseReportMode mouseReportMode;

  Map<String, Object?> toJson() => <String, Object?>{
    'autoWrap': autoWrap,
    'bracketedPaste': bracketedPaste,
    'cursorKeys': cursorKeys,
    'mouseMode': mouseMode.name,
    'mouseReportMode': mouseReportMode.name,
  };
}

final class DeviceLinkSnapshotRow {
  const DeviceLinkSnapshotRow({required this.isWrapped, required this.runs});

  factory DeviceLinkSnapshotRow.fromJson(Map<String, Object?> json) {
    final rawRuns = json['runs'];
    if (rawRuns is! List) throw const FormatException('runs must be a list');
    return DeviceLinkSnapshotRow(
      isWrapped: _requiredBool(json, 'isWrapped'),
      runs: rawRuns
          .map((run) => DeviceLinkAnsiRun.fromJson(_asObject(run, 'run')))
          .toList(growable: false),
    );
  }

  final bool isWrapped;
  final List<DeviceLinkAnsiRun> runs;

  Map<String, Object?> toJson() => <String, Object?>{
    'isWrapped': isWrapped,
    'runs': runs.map((run) => run.toJson()).toList(growable: false),
  };
}

/// One contiguous text segment with one complete SGR prefix.
final class DeviceLinkAnsiRun {
  const DeviceLinkAnsiRun({required this.sgr, required this.text});

  factory DeviceLinkAnsiRun.fromJson(Map<String, Object?> json) {
    final sgr = json['sgr'];
    final text = json['text'];
    if (sgr is! String || text is! String) {
      throw const FormatException('ANSI run requires string sgr and text');
    }
    return DeviceLinkAnsiRun(sgr: sgr, text: text);
  }

  final String sgr;
  final String text;

  Map<String, Object?> toJson() => <String, Object?>{'sgr': sgr, 'text': text};
}

final class _AnsiStyle {
  const _AnsiStyle(
    this.foreground,
    this.background,
    this.underline,
    this.attrs,
  );

  final int foreground;
  final int background;
  final int underline;
  final int attrs;

  @override
  bool operator ==(Object other) {
    return other is _AnsiStyle &&
        other.foreground == foreground &&
        other.background == background &&
        other.underline == underline &&
        other.attrs == attrs;
  }

  @override
  int get hashCode => Object.hash(foreground, background, underline, attrs);

  DeviceLinkAnsiRun run(String text) =>
      DeviceLinkAnsiRun(sgr: _sgr, text: text);

  String get _sgr {
    final codes = <String>['0'];
    if ((attrs & CellAttr.bold) != 0) codes.add('1');
    if ((attrs & CellAttr.faint) != 0) codes.add('2');
    if ((attrs & CellAttr.italic) != 0) codes.add('3');
    if ((attrs & CellAttr.underline) != 0) codes.add('4');
    if ((attrs & CellAttr.blink) != 0) codes.add('5');
    if ((attrs & CellAttr.inverse) != 0) codes.add('7');
    if ((attrs & CellAttr.invisible) != 0) codes.add('8');
    if ((attrs & CellAttr.strikethrough) != 0) codes.add('9');
    if ((attrs & CellAttr.doubleUnderline) != 0) codes.add('21');
    if ((attrs & CellAttr.undercurl) != 0) codes.add('4:3');
    if ((attrs & CellAttr.dottedUnderline) != 0) codes.add('4:4');
    if ((attrs & CellAttr.dashedUnderline) != 0) codes.add('4:5');
    if ((attrs & CellAttr.overline) != 0) codes.add('53');
    if ((attrs & CellAttr.framed) != 0) codes.add('51');
    if ((attrs & CellAttr.encircled) != 0) codes.add('52');
    _appendColor(codes, foreground, foregroundBase: 30, extended: 38);
    _appendColor(codes, background, foregroundBase: 40, extended: 48);
    _appendColor(codes, underline, foregroundBase: 0, extended: 58);
    return '\x1b[${codes.join(';')}m';
  }

  static void _appendColor(
    List<String> codes,
    int color, {
    required int foregroundBase,
    required int extended,
  }) {
    if (color == 0) return;
    final type = color & CellColor.typeMask;
    final value = color & CellColor.valueMask;
    switch (type) {
      case CellColor.named:
        if (foregroundBase == 0) {
          codes.add('$extended;5;$value');
          break;
        }
        if (value < 8) {
          codes.add('${foregroundBase + value}');
        } else {
          codes.add('${foregroundBase + 60 + value - 8}');
        }
      case CellColor.palette:
        codes.add('$extended;5;$value');
      case CellColor.rgb:
        final red = (value >> 16) & 0xff;
        final green = (value >> 8) & 0xff;
        final blue = value & 0xff;
        codes.add('$extended;2;$red;$green;$blue');
    }
  }
}

int _requiredInt(Map<String, Object?> json, String key) {
  final value = json[key];
  if (value is! int) throw FormatException('$key must be an integer');
  return value;
}

bool _requiredBool(Map<String, Object?> json, String key) {
  final value = json[key];
  if (value is! bool) throw FormatException('$key must be a boolean');
  return value;
}

Map<String, Object?> _requiredObject(Map<String, Object?> json, String key) {
  return _asObject(json[key], key);
}

Map<String, Object?> _asObject(Object? value, String name) {
  if (value is Map<String, Object?>) return value;
  if (value is Map) return Map<String, Object?>.from(value);
  throw FormatException('$name must be an object');
}

T _enumValue<T extends Enum>(List<T> values, Object? value, String name) {
  if (value is! String) throw FormatException('$name must be a string');
  for (final candidate in values) {
    if (candidate.name == value) return candidate;
  }
  throw FormatException('Unknown $name: $value');
}
