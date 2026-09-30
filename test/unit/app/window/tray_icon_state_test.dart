import 'package:flutter_test/flutter_test.dart';
import 'package:shellvibe/app/window/tray_icon_state.dart';

void main() {
  group('deriveTrayIconState', () {
    test('is normal with nothing running and nothing wrong', () {
      expect(
        deriveTrayIconState(activeTunnelCount: 0, attention: false),
        TrayIconState.normal,
      );
    });

    test('shows a forward being up', () {
      expect(
        deriveTrayIconState(activeTunnelCount: 1, attention: false),
        TrayIconState.tunnelActive,
      );
      expect(
        deriveTrayIconState(activeTunnelCount: 7, attention: false),
        TrayIconState.tunnelActive,
      );
    });

    test(
      'an error outranks everything, and clears with the attention flag',
      () {
        expect(
          deriveTrayIconState(activeTunnelCount: 3, attention: true),
          TrayIconState.error,
        );
        expect(
          deriveTrayIconState(activeTunnelCount: 0, attention: true),
          TrayIconState.error,
        );
        expect(
          deriveTrayIconState(activeTunnelCount: 3, attention: false),
          TrayIconState.tunnelActive,
        );
      },
    );

    test('a count that changes without changing state is the same state', () {
      // What keeps the tray from re-setting the icon on every speed tick.
      expect(
        deriveTrayIconState(activeTunnelCount: 1, attention: false),
        deriveTrayIconState(activeTunnelCount: 2, attention: false),
      );
    });
  });

  group('trayIconAsset', () {
    test('macOS uses the template images, which differ by shape', () {
      expect(
        trayIconAsset(TrayIconState.normal, isMacOS: true, isWindows: false),
        'assets/brand/tray_macos.png',
      );
      expect(
        trayIconAsset(
          TrayIconState.tunnelActive,
          isMacOS: true,
          isWindows: false,
        ),
        'assets/brand/tray_macos_tunnel.png',
      );
      expect(
        trayIconAsset(TrayIconState.error, isMacOS: true, isWindows: false),
        'assets/brand/tray_macos_error.png',
      );
    });

    test('Windows takes .ico and Linux .png', () {
      expect(
        trayIconAsset(TrayIconState.error, isMacOS: false, isWindows: true),
        'assets/brand/tray_error.ico',
      );
      expect(
        trayIconAsset(
          TrayIconState.tunnelActive,
          isMacOS: false,
          isWindows: false,
        ),
        'assets/brand/tray_tunnel.png',
      );
      expect(
        trayIconAsset(TrayIconState.normal, isMacOS: false, isWindows: true),
        'assets/brand/tray.ico',
      );
    });
  });
}
