import 'package:flutter_test/flutter_test.dart';
import 'package:shellvibe/app/window/start_hidden.dart';

void main() {
  group('shouldStartHidden', () {
    test('hides only a launch at login with the tray on', () {
      expect(
        shouldStartHidden(launchedAtLogin: true, trayEnabled: true),
        isTrue,
      );
      // No tray icon: hidden would be an app nobody can find.
      expect(
        shouldStartHidden(launchedAtLogin: true, trayEnabled: false),
        isFalse,
      );
      // A normal launch always shows the window.
      expect(
        shouldStartHidden(launchedAtLogin: false, trayEnabled: true),
        isFalse,
      );
    });
  });

  group('resolveStartHidden', () {
    Future<bool> resolve({
      List<String> args = const [],
      bool isMacOS = false,
      bool macLogin = false,
      bool tray = true,
      void Function()? onReadTray,
      bool throwOnTray = false,
    }) => resolveStartHidden(
      args: args,
      isMacOS: isMacOS,
      macOsLaunchedAtLogin: () async => macLogin,
      readTrayEnabled: () async {
        onReadTray?.call();
        if (throwOnTray) throw StateError('storage unavailable');
        return tray;
      },
    );

    test('the --hidden argument starts hidden on Windows and Linux', () async {
      expect(await resolve(args: [kStartHiddenArgument]), isTrue);
    });

    test('a normal launch shows the window and reads no settings', () async {
      var reads = 0;
      expect(await resolve(onReadTray: () => reads++), isFalse);
      expect(reads, 0);
    });

    test('a launch at login with the tray off shows the window', () async {
      expect(await resolve(args: [kStartHiddenArgument], tray: false), isFalse);
    });

    test('macOS goes by how the OS launched it, not by an argument', () async {
      expect(await resolve(isMacOS: true, macLogin: true), isTrue);
      expect(await resolve(isMacOS: true, macLogin: false), isFalse);
      expect(
        await resolve(isMacOS: true, args: [kStartHiddenArgument]),
        isFalse,
      );
    });

    test('a failure never produces an invisible app', () async {
      expect(
        await resolve(args: [kStartHiddenArgument], throwOnTray: true),
        isFalse,
      );
    });
  });
}
