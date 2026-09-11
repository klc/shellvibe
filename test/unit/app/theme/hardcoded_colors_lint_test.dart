import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Scans every presentation file for colours written by hand rather than taken
/// from [ShellVibeTokens], so a literal cannot re-enter the codebase unnoticed.
///
/// The earlier version of this test listed ten files and nine specific hex
/// values. That pinned the colours we had already removed and nothing else — a
/// new `Color(0xFF123456)`, or an old one in an eleventh file, walked straight
/// past it. This one inverts that: everything is a violation, and [_exempt]
/// names the ones we have accepted, with the reason. The list is meant to
/// shrink; adding to it is a decision, not a formality.
void main() {
  /// Where the app's own chrome is defined. Literals are the point here.
  const themeLayer = {
    'lib/app/theme/shellvibe_tokens.dart',
    'lib/app/theme/app_palette_definitions.dart',
    'lib/app/theme/app_theme.dart',
  };

  /// Colours that are deliberately not themed, with the reason they are not.
  const exempt = <String, String>{
    'lib/features/device_link/presentation/screens/pairing_qr_screen.dart':
        'QR codes need a white quiet zone to scan, in any theme',
    'lib/features/device_link/presentation/screens/scan_pair_screen.dart':
        'the viewfinder overlay sits on the camera feed, not on a themed surface',
    'lib/core/perf/perf_overlay.dart':
        'the benchmark HUD is mounted above MaterialApp, so no theme reaches '
        'it; it also has to stay legible over whatever is being measured, and '
        'it is compiled out unless SHELLVIBE_PERF is defined',
  };

  /// Terminal ANSI schemes are a separate contract from the app chrome, and are
  /// meant to be literal.
  bool isTerminalPalette(String path) =>
      path.contains('terminal_palette') || path.contains('terminal_font');

  /// `File.path` uses the host separator, so on Windows every path above
  /// arrives as `lib\app\theme\...` and matches nothing — which silently turned
  /// the theme layer itself into a wall of violations on that runner alone. The
  /// lists are written in posix form because that is how the repository is
  /// discussed; normalise the filesystem to them rather than the reverse.
  String posix(String path) => path.replaceAll(r'\', '/');

  final hexLiteral = RegExp(r'Color\(0x[0-9a-fA-F]{8}\)');
  // Named Material colours. `transparent` carries no hue, so it is not a theme
  // decision and stays allowed.
  final namedMaterial = RegExp(r'\bColors\.(?!transparent\b)[a-zA-Z]+');

  List<File> presentationFiles() {
    return Directory('lib')
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => f.path.endsWith('.dart'))
        .where((f) => !themeLayer.contains(posix(f.path)))
        .where((f) => !isTerminalPalette(posix(f.path)))
        .toList()
      ..sort((a, b) => posix(a.path).compareTo(posix(b.path)));
  }

  test('No hand-written colours outside the theme layer', () {
    final violations = <String>[];

    for (final file in presentationFiles()) {
      if (exempt.containsKey(posix(file.path))) continue;
      final content = file.readAsStringSync();
      final found = [
        ...hexLiteral.allMatches(content),
        ...namedMaterial.allMatches(content),
      ];
      if (found.isEmpty) continue;

      // Report with line numbers so the fix is a jump, not a hunt.
      final lines = content.split('\n');
      for (var i = 0; i < lines.length; i++) {
        for (final match in [
          ...hexLiteral.allMatches(lines[i]),
          ...namedMaterial.allMatches(lines[i]),
        ]) {
          violations.add('${posix(file.path)}:${i + 1}  ${match.group(0)}');
        }
      }
    }

    expect(
      violations,
      isEmpty,
      reason:
          'Use a ShellVibeTokens colour, or add the file to the exemption list with '
          'a reason:\n${violations.join('\n')}',
    );
  });

  test('Every exemption names a file that still exists', () {
    for (final path in exempt.keys) {
      expect(
        File(path).existsSync(),
        isTrue,
        reason: 'Exemption for $path is stale — remove it',
      );
    }
  });

  test('Every exemption is still earning its place', () {
    for (final entry in exempt.entries) {
      final content = File(entry.key).readAsStringSync();
      final stillViolates =
          hexLiteral.hasMatch(content) || namedMaterial.hasMatch(content);
      expect(
        stillViolates,
        isTrue,
        reason:
            '${entry.key} no longer has a hand-written colour, so its exemption '
            '("${entry.value}") should be removed',
      );
    }
  });
}
