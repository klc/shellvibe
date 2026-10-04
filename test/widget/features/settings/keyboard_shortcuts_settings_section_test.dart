import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import 'package:shellvibe/core/utils/platform_capabilities.dart';
import 'package:shellvibe/features/settings/presentation/widgets/keyboard_shortcuts_settings_section.dart';

void main() {
  tearDown(() => debugPlatformCapabilitiesOverride = null);

  Future<void> pumpSection(WidgetTester tester, TargetPlatform platform) async {
    debugPlatformCapabilitiesOverride = platform;
    tester.view.physicalSize = const Size(1080, 1920);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() => tester.view.resetPhysicalSize());

    await tester.pumpWidget(
      ShadTheme(
        data: ShadThemeData(
          colorScheme: const ShadSlateColorScheme.light(),
          brightness: Brightness.light,
        ),
        child: const MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: KeyboardShortcutsSettingsSection(),
            ),
          ),
        ),
      ),
    );
  }

  testWidgets('Windows: Ctrl+Shift chords, and the rule that explains them', (
    tester,
  ) async {
    await pumpSection(tester, TargetPlatform.windows);

    expect(find.text('Ctrl+Shift+K'), findsOneWidget);
    expect(find.text('Ctrl+Shift+1…7'), findsOneWidget);
    expect(find.text('Ctrl+Tab'), findsOneWidget);
    expect(find.text('Alt+F4'), findsOneWidget);
    expect(find.text('Ctrl+Shift+C'), findsOneWidget);
    expect(find.textContaining('plain Ctrl keys belong'), findsOneWidget);
  });

  testWidgets('macOS: ⌘ chords, no Ctrl note', (tester) async {
    await pumpSection(tester, TargetPlatform.macOS);

    expect(find.text('⌘K'), findsOneWidget);
    expect(find.text('⇧⌘W'), findsOneWidget);
    expect(find.text('⌘,'), findsOneWidget);
    expect(find.textContaining('plain Ctrl keys belong'), findsNothing);
  });

  testWidgets('iPad: no window to close and no local tab to open', (
    tester,
  ) async {
    await pumpSection(tester, TargetPlatform.iOS);

    expect(find.text('Close window'), findsNothing);
    expect(find.text('New local tab'), findsNothing);
    expect(find.text('⌘K'), findsOneWidget);
  });
}
