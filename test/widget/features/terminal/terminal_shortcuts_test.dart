import 'package:drift/native.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import 'package:shellvibe/app/keyboard/app_keymap.dart';
import 'package:shellvibe/core/network/local_pty_manager.dart';
import 'package:shellvibe/core/network/providers/network_providers.dart';
import 'package:shellvibe/core/utils/platform_capabilities.dart';
import 'package:shellvibe/features/settings/presentation/notifiers/settings_notifier.dart';
import 'package:shellvibe/features/snippets/presentation/widgets/snippet_picker_sheet.dart';
import 'package:shellvibe/features/terminal/presentation/notifiers/terminal_tabs_notifier.dart';
import 'package:shellvibe/features/terminal/presentation/views/terminal_tab_view.dart';
import 'package:shellvibe/shared/database/app_database.dart';
import 'package:shellvibe/shared/providers/database_providers.dart';
import 'package:xterm3/xterm.dart';

/// The app's shortcuts with a terminal focused.
///
/// A focused terminal encodes Ctrl chords for the PTY and reports them
/// handled, so nothing it sees bubbles up to the app — which is how Ctrl+K
/// came to do nothing on Windows. These tests press the chords at a real
/// terminal pane and check both sides: the app command runs, and the shell
/// still gets the plain Ctrl keys that are its own.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase db;
  late int paletteOpened;
  late List<String> ptyInput;

  setUp(() {
    FlutterSecureStorage.setMockInitialValues({});
    db = AppDatabase(NativeDatabase.memory());
    paletteOpened = 0;
    ptyInput = [];
  });

  tearDown(() async {
    debugPlatformCapabilitiesOverride = null;
    await db.close();
  });

  /// The terminal module under the app's keymap, with one local tab open and
  /// focused. The palette lives in the shell, so a stand-in action counts it.
  Future<ProviderContainer> openTerminal(WidgetTester tester) async {
    debugPlatformCapabilitiesOverride = defaultTargetPlatform;
    final container = ProviderContainer(
      overrides: [
        appDatabaseProvider.overrideWithValue(db),
        localPtyManagerProvider.overrideWithValue(_NoShellPtyManager()),
      ],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: ShadTheme(
          data: ShadThemeData(
            colorScheme: const ShadSlateColorScheme.dark(),
            brightness: Brightness.dark,
          ),
          child: MaterialApp(
            home: Actions(
              actions: {
                OpenCommandPaletteIntent:
                    CallbackAction<OpenCommandPaletteIntent>(
                      onInvoke: (_) => paletteOpened++,
                    ),
              },
              child: const AppKeymapShortcuts(child: TerminalTabView()),
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    container.read(terminalTabsProvider.notifier).openLocalTab();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));

    container.read(terminalTabsProvider).tabs.single.terminal.onOutput =
        ptyInput.add;
    return container;
  }

  Future<void> chord(
    WidgetTester tester,
    LogicalKeyboardKey key, {
    bool control = false,
    bool shift = false,
    bool meta = false,
  }) async {
    if (control) await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    if (meta) await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
    if (shift) await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyEvent(key);
    if (shift) await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    if (meta) await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
    if (control) await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
  }

  final ctrlPlatforms = TargetPlatformVariant({
    TargetPlatform.windows,
    TargetPlatform.linux,
  });

  group('Ctrl keyboards', () {
    testWidgets('Ctrl+Shift+K opens the palette; Ctrl+K stays the shell\'s', (
      tester,
    ) async {
      await openTerminal(tester);

      await chord(tester, LogicalKeyboardKey.keyK, control: true, shift: true);
      expect(paletteOpened, 1);
      expect(ptyInput, isEmpty, reason: 'the chord must not reach the PTY');

      await chord(tester, LogicalKeyboardKey.keyK, control: true);
      expect(paletteOpened, 1);
      expect(ptyInput.join(), '\x0b', reason: 'readline kill-line');
    }, variant: ctrlPlatforms);

    testWidgets('Ctrl+W is werase; Ctrl+Shift+W closes the tab', (
      tester,
    ) async {
      final container = await openTerminal(tester);

      await chord(tester, LogicalKeyboardKey.keyW, control: true);
      expect(ptyInput.join(), '\x17');
      expect(container.read(terminalTabsProvider).tabs, hasLength(1));

      await chord(tester, LogicalKeyboardKey.keyW, control: true, shift: true);
      expect(container.read(terminalTabsProvider).tabs, isEmpty);
    }, variant: ctrlPlatforms);

    testWidgets('Ctrl+Shift+T opens a tab; Ctrl+T is transpose', (
      tester,
    ) async {
      final container = await openTerminal(tester);

      await chord(tester, LogicalKeyboardKey.keyT, control: true);
      expect(ptyInput.join(), '\x14');
      expect(container.read(terminalTabsProvider).tabs, hasLength(1));

      await chord(tester, LogicalKeyboardKey.keyT, control: true, shift: true);
      expect(container.read(terminalTabsProvider).tabs, hasLength(2));
    }, variant: ctrlPlatforms);

    testWidgets('Ctrl+Shift+S opens the snippet picker without sending XOFF', (
      tester,
    ) async {
      await openTerminal(tester);

      await chord(tester, LogicalKeyboardKey.keyS, control: true, shift: true);
      await tester.pumpAndSettle();

      expect(find.byType(SnippetPickerSheet), findsOneWidget);
      expect(ptyInput, isEmpty, reason: '0x13 would freeze the output');
    }, variant: ctrlPlatforms);

    testWidgets('Ctrl+Shift+F opens the find bar', (tester) async {
      await openTerminal(tester);

      await chord(tester, LogicalKeyboardKey.keyF, control: true, shift: true);

      expect(find.byKey(const Key('terminal_search_field')), findsOneWidget);
      expect(ptyInput, isEmpty);
    }, variant: ctrlPlatforms);
  });

  group('Tabs and zoom', () {
    String? activeRoot(ProviderContainer container) =>
        container.read(terminalTabsProvider).activeTabId;

    testWidgets(
      'Ctrl+Tab and Ctrl+Shift+Tab walk the tabs, wrapping, PTY untouched',
      (tester) async {
        final container = await openTerminal(tester);
        container.read(terminalTabsProvider.notifier).openLocalTab();
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 200));
        final ids = [
          for (final tab in container.read(terminalTabsProvider).tabs) tab.id,
        ];
        expect(ids, hasLength(2));
        expect(activeRoot(container), ids[1]);

        await chord(tester, LogicalKeyboardKey.tab, control: true);
        expect(activeRoot(container), ids[0], reason: 'wraps past the end');

        await chord(tester, LogicalKeyboardKey.tab, control: true, shift: true);
        expect(activeRoot(container), ids[1]);

        if (!usesCommandKey()) {
          await chord(tester, LogicalKeyboardKey.pageDown, control: true);
          expect(activeRoot(container), ids[0]);
          await chord(tester, LogicalKeyboardKey.pageUp, control: true);
          expect(activeRoot(container), ids[1]);
        }
        expect(ptyInput, isEmpty);
      },
      variant: TargetPlatformVariant({
        TargetPlatform.windows,
        TargetPlatform.linux,
        TargetPlatform.macOS,
      }),
    );

    testWidgets(
      'Ctrl+Shift+= / - / 0 and the keypad keys zoom the terminal font',
      (tester) async {
        final container = await openTerminal(tester);
        double fontSize() => container.read(settingsProvider).value!.fontSize;
        await tester.runAsync(() => container.read(settingsProvider.future));
        final start = fontSize();

        Future<void> press(LogicalKeyboardKey key, {bool shift = true}) async {
          await chord(tester, key, control: true, shift: shift);
          await tester.runAsync(() async {});
          await tester.pump();
        }

        await press(LogicalKeyboardKey.equal);
        expect(fontSize(), start + 1);
        await press(LogicalKeyboardKey.numpadAdd, shift: false);
        expect(fontSize(), start + 2);
        await press(LogicalKeyboardKey.minus);
        expect(fontSize(), start + 1);
        await press(LogicalKeyboardKey.digit0);
        expect(fontSize(), start);
        expect(ptyInput, isEmpty);
      },
      variant: ctrlPlatforms,
    );
  });

  group('Command keyboards', () {
    testWidgets('⌘K opens the palette and ⌘W closes the tab', (tester) async {
      final container = await openTerminal(tester);

      await chord(tester, LogicalKeyboardKey.keyK, meta: true);
      expect(paletteOpened, 1);

      await chord(tester, LogicalKeyboardKey.keyW, meta: true);
      expect(container.read(terminalTabsProvider).tabs, isEmpty);
      expect(ptyInput, isEmpty);
    }, variant: TargetPlatformVariant.only(TargetPlatform.macOS));

    testWidgets('Ctrl+K reaches the shell on a Mac too', (tester) async {
      await openTerminal(tester);

      await chord(tester, LogicalKeyboardKey.keyK, control: true);
      expect(paletteOpened, 0);
      expect(ptyInput.join(), '\x0b');
    }, variant: TargetPlatformVariant.only(TargetPlatform.macOS));
  });
}

class _NoShellPtyManager extends LocalPtyManager {
  @override
  Future<TerminalLocalPtyBridge?> startAndBridge(
    Terminal terminal, {
    String? executable,
    List<String> arguments = const [],
    String? workingDirectory,
    Map<String, String>? environment,
    int rows = 24,
    int columns = 80,
    void Function(Uint8List bytes)? outputTap,
  }) async => null;
}
