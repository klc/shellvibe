import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shellvibe/features/tunnels/presentation/tunnel_availability.dart';

const _iPhone = Size(390, 844);
const _iPhoneLandscape = Size(844, 390);
const _iPad = Size(820, 1180);
const _iPadLandscape = Size(1180, 820);
const _iPadMini = Size(744, 1133);

bool _supported(TargetPlatform platform, Size size) =>
    tunnelsSupportedOnThisDevice(platform: platform, displaySize: size);

bool _hint(TargetPlatform platform, Size size) =>
    tunnelsNeedForegroundHint(platform: platform, displaySize: size);

void main() {
  group('tunnelsSupportedOnThisDevice', () {
    test('an iPhone has no tunnels, held either way up', () {
      expect(_supported(TargetPlatform.iOS, _iPhone), isFalse);
      expect(_supported(TargetPlatform.iOS, _iPhoneLandscape), isFalse);
    });

    test('an iPad keeps them, including the small one', () {
      expect(_supported(TargetPlatform.iOS, _iPad), isTrue);
      expect(_supported(TargetPlatform.iOS, _iPadLandscape), isTrue);
      expect(_supported(TargetPlatform.iOS, _iPadMini), isTrue);
    });

    test('the line is the shortest side against the compact breakpoint', () {
      expect(_supported(TargetPlatform.iOS, const Size(639, 2000)), isFalse);
      expect(_supported(TargetPlatform.iOS, const Size(640, 2000)), isTrue);
      expect(
        tunnelsSupportedOnThisDevice(
          platform: TargetPlatform.iOS,
          displaySize: const Size(700, 900),
          compactBreakpoint: 800,
        ),
        isFalse,
      );
    });

    test('Android and desktop are unchanged, phone-sized or not', () {
      for (final platform in [
        TargetPlatform.android,
        TargetPlatform.macOS,
        TargetPlatform.windows,
        TargetPlatform.linux,
      ]) {
        expect(_supported(platform, _iPhone), isTrue, reason: '$platform');
        expect(_supported(platform, _iPad), isTrue, reason: '$platform');
      }
    });
  });

  group('tunnelsNeedForegroundHint', () {
    test('only an iPad is told tunnels stop in the background', () {
      expect(_hint(TargetPlatform.iOS, _iPad), isTrue);
      expect(_hint(TargetPlatform.iOS, _iPadLandscape), isTrue);
      expect(_hint(TargetPlatform.iOS, _iPhone), isFalse);
      expect(_hint(TargetPlatform.android, _iPad), isFalse);
      expect(_hint(TargetPlatform.macOS, _iPadLandscape), isFalse);
    });

    test('never shown where the tunnels themselves are hidden', () {
      for (final platform in TargetPlatform.values) {
        for (final size in [_iPhone, _iPhoneLandscape, _iPad, _iPadMini]) {
          if (_hint(platform, size)) {
            expect(_supported(platform, size), isTrue);
          }
        }
      }
    });
  });
}
