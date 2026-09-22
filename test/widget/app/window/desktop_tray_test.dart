import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shellvibe/app/window/desktop_tray.dart';
import 'package:shellvibe/core/network/local_pty_manager.dart';
import 'package:shellvibe/core/network/providers/network_providers.dart';
import 'package:shellvibe/features/settings/presentation/notifiers/settings_notifier.dart';
import 'package:shellvibe/features/terminal/presentation/notifiers/terminal_tabs_notifier.dart';
import 'package:shellvibe/shared/database/app_database.dart';
import 'package:shellvibe/shared/providers/database_providers.dart';
import 'package:window_manager/window_manager.dart';
import 'package:xterm3/xterm.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase db;
  late List<MethodCall> trayCalls;
  late List<MethodCall> windowCalls;

  setUp(() {
    FlutterSecureStorage.setMockInitialValues({});
    db = AppDatabase(NativeDatabase.memory());
    trayCalls = [];
    windowCalls = [];
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(const MethodChannel('tray_manager'), (
      call,
    ) async {
      trayCalls.add(call);
      return null;
    });
    messenger.setMockMethodCallHandler(const MethodChannel('window_manager'), (
      call,
    ) async {
      windowCalls.add(call);
      return null;
    });
  });

  tearDown(() async {
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(
      const MethodChannel('tray_manager'),
      null,
    );
    messenger.setMockMethodCallHandler(
      const MethodChannel('window_manager'),
      null,
    );
    await db.close();
  });

  /// Labels of the most recent tray menu, separators left out.
  List<String> lastMenu() {
    final call = trayCalls.lastWhere((c) => c.method == 'setContextMenu');
    final menu = (call.arguments as Map)['menu'] as Map;
    return [
      for (final item in menu['items'] as List)
        if ((item as Map)['type'] != 'separator') item['label'] as String,
    ];
  }

  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
  }

  testWidgets('the tray shows what runs behind the window, and follows the '
      'setting', (tester) async {
    final container = ProviderContainer(
      overrides: [
        appDatabaseProvider.overrideWithValue(db),
        localPtyManagerProvider.overrideWithValue(_NoShellPtyManager()),
      ],
    );
    await container.read(settingsProvider.future);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(
          home: DesktopTrayHost(child: SizedBox.shrink()),
        ),
      ),
    );
    await settle(tester);

    expect(trayCalls.map((c) => c.method), contains('setIcon'));
    expect(lastMenu(), [
      'Show ShellVibe',
      '0 active tunnels',
      '0 open tabs',
      'Quit ShellVibe',
    ]);

    container.read(terminalTabsProvider.notifier).openLocalTab();
    await settle(tester);
    expect(lastMenu(), contains('1 open tab'));

    // Closing the window while the tray is on hides it; nothing quits.
    final host = tester.state(find.byType(DesktopTrayHost)) as WindowListener;
    host.onWindowClose();
    await settle(tester);
    expect(windowCalls.map((c) => c.method), contains('hide'));
    expect(windowCalls.map((c) => c.method), isNot(contains('destroy')));

    await container.read(settingsProvider.notifier).setKeepRunningInTray(false);
    await settle(tester);
    expect(trayCalls.last.method, 'destroy');

    await tester.pumpWidget(const SizedBox.shrink());
    container.dispose();
    await tester.pumpAndSettle();
  });
}

/// Widget tests must not start real shells.
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
