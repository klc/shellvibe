import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:shellvibe/app/theme/app_theme.dart';
import 'package:shellvibe/app/widgets/adaptive_modal.dart';
import 'package:shellvibe/core/utils/platform_capabilities.dart';
import 'package:shellvibe/features/settings/domain/models/app_settings_model.dart';

/// Which shape a modal takes on which host.
///
/// A bottom sheet is a thumb affordance. On a 1440px desktop window the same
/// sheet slides up from the bottom of the screen, a long way from the pointer
/// that opened it, and reads as a phone control that wandered in.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  tearDown(() {
    debugPlatformCapabilitiesOverride = null;
  });

  Widget host(void Function(BuildContext context) onPressed) {
    return MaterialApp(
      theme: AppTheme.buildTheme(const AppSettingsModel()),
      home: Scaffold(
        body: Center(
          child: Builder(
            builder: (context) => ElevatedButton(
              key: const Key('opener'),
              onPressed: () => onPressed(context),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> pumpAt(WidgetTester tester, Widget widget, Size size) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(widget);
    await tester.pump();
  }

  group('showAdaptiveActionMenu', () {
    Widget menuHost() => host(
      (context) => showAdaptiveActionMenu<String>(
        context: context,
        actions: const [
          AdaptiveMenuAction(
            value: 'local',
            itemKey: Key('menu_local'),
            icon: Icons.terminal,
            label: 'Local Shell',
          ),
        ],
      ),
    );

    testWidgets('is a dropdown on a desktop window', (tester) async {
      await pumpAt(tester, menuHost(), const Size(1440, 900));
      await tester.tap(find.byKey(const Key('opener')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('menu_local')), findsOneWidget);
      expect(find.byType(PopupMenuItem<String>), findsOneWidget);
      expect(find.byType(BottomSheet), findsNothing);
    });

    testWidgets('is a bottom sheet on a phone', (tester) async {
      debugPlatformCapabilitiesOverride = TargetPlatform.iOS;
      await pumpAt(tester, menuHost(), const Size(393, 852));
      await tester.tap(find.byKey(const Key('opener')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('menu_local')), findsOneWidget);
      expect(find.byType(BottomSheet), findsOneWidget);
      expect(find.byType(PopupMenuItem<String>), findsNothing);
    });

    testWidgets('a phone in landscape still gets the sheet', (tester) async {
      debugPlatformCapabilitiesOverride = TargetPlatform.iOS;
      await pumpAt(tester, menuHost(), const Size(852, 393));
      await tester.tap(find.byKey(const Key('opener')));
      await tester.pumpAndSettle();

      expect(find.byType(BottomSheet), findsOneWidget);
    });
  });

  group('showAdaptivePanel', () {
    Widget panelHost() => host(
      (context) => showAdaptivePanel<void>(
        context: context,
        title: 'Connect to Host',
        builder: (_) => const SizedBox(
          key: Key('panel_body'),
          height: 120,
          child: Text('body'),
        ),
      ),
    );

    testWidgets('is a titled dialog on a desktop window', (tester) async {
      await pumpAt(tester, panelHost(), const Size(1440, 900));
      await tester.tap(find.byKey(const Key('opener')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('panel_body')), findsOneWidget);
      expect(find.text('Connect to Host'), findsOneWidget);
      expect(find.byType(BottomSheet), findsNothing);

      // The dialog closes from its own header, so a pointer never has to hunt
      // for the barrier.
      await tester.tap(find.byTooltip('Close'));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('panel_body')), findsNothing);
    });

    testWidgets('is a bottom sheet on a phone, with no header', (tester) async {
      debugPlatformCapabilitiesOverride = TargetPlatform.iOS;
      await pumpAt(tester, panelHost(), const Size(393, 852));
      await tester.tap(find.byKey(const Key('opener')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('panel_body')), findsOneWidget);
      expect(find.byType(BottomSheet), findsOneWidget);
      // The sheet's drag handle is the dismissal; a second close control in a
      // header would be redundant.
      expect(find.text('Connect to Host'), findsNothing);
    });
  });
}
