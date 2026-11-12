import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shellvibe/features/terminal/domain/models/terminal_palette_data.dart';

double _ratio(Color a, Color b) {
  final la = a.computeLuminance(), lb = b.computeLuminance();
  return (math.max(la, lb) + 0.05) / (math.min(la, lb) + 0.05);
}

/// The interface parts of a scheme — cursor, selection and search hits — are
/// ours to keep legible, whatever the scheme's own ANSI colours do. These are
/// floors, not targets: a scheme whose two hit colours sit at opposite ends of
/// the ramp cannot give one ink 4.5:1 on both.
void main() {
  for (final scheme in kTerminalPalettes) {
    final t = scheme.theme;
    final bg = t.background;

    test('${scheme.label}: cursor stands off the background', () {
      expect(_ratio(t.cursor, bg), greaterThanOrEqualTo(2.0));
    });

    test('${scheme.label}: a selection is visible', () {
      expect(
        _ratio(Color.alphaBlend(t.selection, bg), bg),
        greaterThanOrEqualTo(1.25),
      );
    });

    test('${scheme.label}: search hit text reads on both hit colours', () {
      for (final hit in [t.searchHitBackground, t.searchHitBackgroundCurrent]) {
        expect(
          _ratio(t.searchHitForeground, Color.alphaBlend(hit, bg)),
          greaterThanOrEqualTo(2.5),
        );
      }
    });
  }
}
