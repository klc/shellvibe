import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:terly2/app/app.dart';
import 'package:terly2/core/network/local_pty_manager.dart';
import 'package:terly2/core/network/providers/network_providers.dart';
import 'package:terly2/core/utils/platform_capabilities.dart';
import 'package:terly2/features/terminal/presentation/notifiers/terminal_tabs_notifier.dart';
import 'package:terly2/shared/database/app_database.dart';
import 'package:terly2/shared/providers/database_providers.dart';
import 'package:xterm2/xterm.dart';

/// Test double that never spawns a real PTY, keeping the app-level startup
/// tests hermetic instead of launching the host's shell.
class _NullPtyManager extends LocalPtyManager {
  @override
  TerminalLocalPtyBridge? startAndBridge(
    Terminal terminal, {
    String? executable,
    List<String> arguments = const [],
    String? workingDirectory,
    Map<String, String>? environment,
    int rows = 24,
    int columns = 80,
  }) =>
      null;
}

void main() {
  testWidgets('TerlyApp lands on the terminal screen with a local shell open '
      'at startup on desktop', (WidgetTester tester) async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(() => db.close());

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appDatabaseProvider.overrideWithValue(db),
          localPtyManagerProvider.overrideWithValue(_NullPtyManager()),
        ],
        child: const TerlyApp(),
      ),
    );

    await tester.pumpAndSettle();

    final container = ProviderScope.containerOf(
      tester.element(find.byType(TerlyApp)),
    );

    // The rail is icon-only, so the brand is a mark rather than a wordmark.
    expect(find.byKey(const Key('header_brand_logo')), findsOneWidget);

    // The app launches into the terminal screen with a local shell tab open
    // (tab header and pane title both carry the label).
    expect(find.text('Local Shell'), findsWidgets);
    expect(container.read(terminalTabsProvider).tabs.length, equals(1));
  });

  testWidgets('TerlyApp does not open a local shell on mobile', (
    WidgetTester tester,
  ) async {
    debugPlatformCapabilitiesOverride = TargetPlatform.android;
    addTearDown(() => debugPlatformCapabilitiesOverride = null);

    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(() => db.close());

    await tester.pumpWidget(
      ProviderScope(
        overrides: [appDatabaseProvider.overrideWithValue(db)],
        child: const TerlyApp(),
      ),
    );

    await tester.pumpAndSettle();

    final container = ProviderScope.containerOf(
      tester.element(find.byType(TerlyApp)),
    );

    // Terminal screen shows, but no local shell is started — mobile connects
    // via SSH only.
    expect(container.read(terminalTabsProvider).tabs, isEmpty);
    expect(find.text('No Active Terminal Sessions'), findsOneWidget);
  });
}
