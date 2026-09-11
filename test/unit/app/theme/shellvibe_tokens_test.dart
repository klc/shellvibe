import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shellvibe/app/theme/shellvibe_tokens.dart';

void main() {
  group('ShellVibeTokens Unit Tests', () {
    test('ShellVibeTokens.dark contains valid semantic color extensions', () {
      const tokens = ShellVibeTokens.dark;

      expect(tokens.brandBright, const Color(0xFFA8AEFF));
      expect(tokens.brandSoft, const Color(0xFFC6CAFF));
      expect(tokens.dangerMutedSurface, const Color(0xFF2A0710));
      expect(tokens.dangerMutedText, const Color(0xFFFFC2CC));
      expect(tokens.dangerMutedBorder, const Color(0xFFC09AA3));
    });

    test('ShellVibeTokens.light contains valid semantic color extensions', () {
      const tokens = ShellVibeTokens.light;

      expect(tokens.brandBright, isNotNull);
      expect(tokens.brandSoft, isNotNull);
      expect(tokens.dangerMutedSurface, isNotNull);
      expect(tokens.dangerMutedText, isNotNull);
      expect(tokens.dangerMutedBorder, isNotNull);
    });

    test('copyWith properly overrides new semantic tokens', () {
      const tokens = ShellVibeTokens.dark;
      final modified = tokens.copyWith(
        brandBright: const Color(0xFF112233),
        brandSoft: const Color(0xFF445566),
        dangerMutedSurface: const Color(0xFF778899),
        dangerMutedText: const Color(0xFFAABBCC),
        dangerMutedBorder: const Color(0xFFDDEEFF),
      );

      expect(modified.brandBright, const Color(0xFF112233));
      expect(modified.brandSoft, const Color(0xFF445566));
      expect(modified.dangerMutedSurface, const Color(0xFF778899));
      expect(modified.dangerMutedText, const Color(0xFFAABBCC));
      expect(modified.dangerMutedBorder, const Color(0xFFDDEEFF));
    });

    test('lerp interpolates new semantic tokens smoothly', () {
      const dark = ShellVibeTokens.dark;
      const light = ShellVibeTokens.light;

      final lerped = dark.lerp(light, 0.5);

      expect(
        lerped.brandBright,
        Color.lerp(dark.brandBright, light.brandBright, 0.5),
      );
      expect(
        lerped.brandSoft,
        Color.lerp(dark.brandSoft, light.brandSoft, 0.5),
      );
    });
  });
}
