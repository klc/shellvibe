import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import 'package:shellvibe/app/widgets/window_chrome_frame.dart';
import 'package:shellvibe/app/window/window_chrome.dart';
import 'package:shellvibe/features/sftp/presentation/screens/sftp_dual_pane_screen.dart';
import 'package:window_manager/window_manager.dart';

void main() {
  group('SftpDualPaneScreen Widget Tests', () {
    testWidgets('renders local workstation and remote sftp panes', (WidgetTester tester) async {
      await tester.pumpWidget(
        ProviderScope(
          child: ShadTheme(
            data: ShadThemeData(
              colorScheme: const ShadSlateColorScheme.light(),
              brightness: Brightness.light,
            ),
            child: const MaterialApp(
              home: SftpDualPaneScreen(hostLabel: 'Test Server'),
            ),
          ),
        ),
      );

      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      expect(find.text('Files · Test Server'), findsOneWidget);
      expect(find.text('LOCAL WORKSTATION'), findsOneWidget);
      // The remote pane names the connection so the target server is never
      // ambiguous, even while it is disconnected.
      expect(find.text('TEST SERVER (DISCONNECTED)'), findsOneWidget);
    });

    testWidgets('renders segmented tab control on narrow screens (< 600px)', (WidgetTester tester) async {
      tester.view.physicalSize = const Size(500, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      await tester.pumpWidget(
        ProviderScope(
          child: ShadTheme(
            data: ShadThemeData(
              colorScheme: const ShadSlateColorScheme.light(),
              brightness: Brightness.light,
            ),
            child: const MaterialApp(
              home: SftpDualPaneScreen(hostLabel: 'Test Server'),
            ),
          ),
        ),
      );

      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      expect(find.byType(SegmentedButton<int>), findsOneWidget);
    });

    testWidgets('window chrome frame keeps the toolbar clear of the traffic '
        'lights on macOS', (WidgetTester tester) async {
      // The screen is pushed over the navigation shell, so it does not inherit
      // the shell's strip: without its own frame the toolbar's back button and
      // title start at y=0, right underneath the window controls.
      debugWindowChromeOverride = TargetPlatform.macOS;
      addTearDown(() => debugWindowChromeOverride = null);
      tester.view.physicalSize = const Size(1440, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      await tester.pumpWidget(
        ProviderScope(
          child: ShadTheme(
            data: ShadThemeData(
              colorScheme: const ShadSlateColorScheme.light(),
              brightness: Brightness.light,
            ),
            child: const MaterialApp(
              home: WindowChromeFrame(
                child: SftpDualPaneScreen(hostLabel: 'Test Server'),
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      final strip = find.byType(DragToMoveArea);
      expect(strip, findsOneWidget);
      expect(tester.getSize(strip).height, kTrafficLightStripHeight);
      expect(tester.getTopLeft(strip).dy, 0);
      expect(
        tester.getTopLeft(find.text('Files · Test Server')).dy,
        greaterThanOrEqualTo(kTrafficLightStripHeight),
      );
    });

    testWidgets('window chrome frame draws no strip where the platform keeps '
        'its title bar', (WidgetTester tester) async {
      // Windows and Linux still get a native caption, so the strip would be a
      // second, empty title bar stacked under the real one.
      debugWindowChromeOverride = TargetPlatform.windows;
      addTearDown(() => debugWindowChromeOverride = null);
      tester.view.physicalSize = const Size(1440, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      await tester.pumpWidget(
        ProviderScope(
          child: ShadTheme(
            data: ShadThemeData(
              colorScheme: const ShadSlateColorScheme.light(),
              brightness: Brightness.light,
            ),
            child: const MaterialApp(
              home: WindowChromeFrame(
                child: SftpDualPaneScreen(hostLabel: 'Test Server'),
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      expect(find.byType(DragToMoveArea), findsNothing);
    });

    testWidgets('window chrome frame leaves the phone layout alone', (
      WidgetTester tester,
    ) async {
      // A phone has no window controls to keep clear of, and the frame's panel
      // gap would inset a layout that is meant to reach the screen edge.
      debugWindowChromeOverride = TargetPlatform.macOS;
      addTearDown(() => debugWindowChromeOverride = null);
      tester.view.physicalSize = const Size(500, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      await tester.pumpWidget(
        ProviderScope(
          child: ShadTheme(
            data: ShadThemeData(
              colorScheme: const ShadSlateColorScheme.light(),
              brightness: Brightness.light,
            ),
            child: const MaterialApp(
              home: WindowChromeFrame(
                child: SftpDualPaneScreen(hostLabel: 'Test Server'),
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      expect(find.byType(DragToMoveArea), findsNothing);
      expect(find.byType(SegmentedButton<int>), findsOneWidget);
    });

    testWidgets('transfer queue sheet header fits a phone width', (
      WidgetTester tester,
    ) async {
      tester.view.physicalSize = const Size(411, 915);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      await tester.pumpWidget(
        ProviderScope(
          child: ShadTheme(
            data: ShadThemeData(
              colorScheme: const ShadSlateColorScheme.light(),
              brightness: Brightness.light,
            ),
            child: const MaterialApp(
              home: SftpDualPaneScreen(hostLabel: 'Test Server'),
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));
      expect(tester.takeException(), isNull, reason: 'screen layout');

      await tester.tap(find.byTooltip('Transfer Queue'));
      // Not pumpAndSettle: the queue's loading indicator animates forever
      // while no worker stream is attached.
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      expect(find.text('SFTP Transfer Queue'), findsOneWidget);
      expect(tester.takeException(), isNull, reason: 'queue sheet header');
    });
  });
}
