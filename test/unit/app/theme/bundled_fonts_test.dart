@TestOn('vm')
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shellvibe/app/theme/ui_font.dart';
import 'package:shellvibe/features/terminal/domain/models/terminal_font.dart';

/// Family name → the weights pubspec registers for it, with the asset paths.
Map<String, Map<int, String>> _registeredFonts() {
  // A Windows checkout can carry CRLF line endings.
  final pubspec = File(
    'pubspec.yaml',
  ).readAsStringSync().replaceAll('\r\n', '\n');
  final section = pubspec.substring(pubspec.indexOf('\n  fonts:\n'));
  final fonts = <String, Map<int, String>>{};
  Map<int, String>? current;
  String? pendingAsset;
  for (final line in section.split('\n')) {
    final family = RegExp(r'^    - family: (.+)$').firstMatch(line);
    final asset = RegExp(r'^        - asset: (.+)$').firstMatch(line);
    final weight = RegExp(r'^          weight: (\d+)$').firstMatch(line);
    if (family != null) {
      if (pendingAsset != null) current![400] = pendingAsset;
      pendingAsset = null;
      current = fonts.putIfAbsent(family.group(1)!.trim(), () => {});
    } else if (asset != null) {
      if (pendingAsset != null) current![400] = pendingAsset;
      pendingAsset = asset.group(1)!.trim();
    } else if (weight != null && pendingAsset != null) {
      current![int.parse(weight.group(1)!)] = pendingAsset;
      pendingAsset = null;
    }
  }
  if (pendingAsset != null) current![400] = pendingAsset;
  return fonts;
}

void main() {
  final registered = _registeredFonts();

  // Nothing may be fetched at runtime (PRIVACY.md), so a face offered in
  // Settings that pubspec does not register would draw in the fallback.
  test('every interface font is registered at the weights the theme sets', () {
    for (final font in kUiFonts) {
      final weights = registered[font.family]?.keys.toSet();
      expect(weights, isNotNull, reason: '${font.family} is not in pubspec');
      // Lato publishes no 500 or 600; those resolve to its nearest weight.
      final expected = font.family == 'Lato'
          ? {400, 700}
          : {400, 500, 600, 700};
      expect(weights, containsAll(expected), reason: font.family);
    }
  });

  test('every non-system terminal font is registered', () {
    for (final font in kTerminalFonts) {
      if (font.source == TerminalFontSource.system) continue;
      expect(
        registered[font.familyName]?.containsKey(400),
        isTrue,
        reason: '${font.familyName} has no regular face in pubspec',
      );
    }
  });

  test('every registered font file exists', () {
    for (final entry in registered.entries) {
      for (final asset in entry.value.values) {
        expect(File(asset).existsSync(), isTrue, reason: asset);
      }
    }
  });
}
