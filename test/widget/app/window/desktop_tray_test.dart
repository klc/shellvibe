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
  late List<MethodCall> platformCalls;

  /// Tray and window calls in the order they were made, across both channels.
  late List<String> log;

  /// What the native side reports for `isPreventClose`: the last value the
  /// app set, which a test may overwrite to stage an intercepted close.
  late bool preventClose;
  late bool failSetIcon;

  setUp(() {
    FlutterSecureStorage.setMockInitialValues({});
    db = AppDatabase(NativeDatabase.memory());
    trayCalls = [];
    windowCalls = [];
    platformCalls = [];
    log = [];
    preventClose = false;
    failSetIcon = false;
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(const MethodChannel('tray_manager'), (
      call,
    ) async {
      trayCalls.add(call);
      log.add('tray.${call.method}');
      if (call.method == 'setIcon' && failSetIcon) {
        throw PlatformException(code: 'no_tray_host');
      }
      return null;
    });
    messenger.setMockMethodCallHandler(const MethodChannel('window_manager'), (
      call,
    ) async {
      windowCalls.add(call);
      switch (call.method) {
        case 'setPreventClose':
          preventClose = (call.arguments as Map)['isPreventClose'] as bool;
          log.add('window.setPreventClose($preventClose)');
        case 'isPreventClose':
          return preventClose;
      }
      return null;
    });
    messenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
      platformCalls.add(call);
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
    messenger.setMockMethodCallHandler(SystemChannels.platform, null);
    debugTrayInterceptsCloseOverride = null;
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

  Future<ProviderContainer> pumpTray(WidgetTester tester) async {
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
    return container;
  }

  Future<void> unpump(WidgetTester tester, ProviderContainer container) async {
    await tester.pumpWidget(const SizedBox.shrink());
    container.dispose();
    await tester.pumpAndSettle();
  }

  testWidgets('the tray shows what runs behind the window, and follows the '
      'setting', (tester) async {
    final container = await pumpTray(tester);

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

    // An intercepted close while the tray is on hides the window; nothing
    // quits.
    preventClose = true;
    final host = tester.state(find.byType(DesktopTrayHost)) as WindowListener;
    host.onWindowClose();
    await settle(tester);
    expect(windowCalls.map((c) => c.method), contains('hide'));
    expect(windowCalls.map((c) => c.method), isNot(contains('destroy')));

    await container.read(settingsProvider.notifier).setKeepRunningInTray(false);
    await settle(tester);
    expect(trayCalls.last.method, 'destroy');

    await unpump(tester, container);
  });

  // window_manager reports every close, including the ones nothing
  // intercepted: on macOS every close, and on Windows or Linux any close with
  // the tray off. Treating those as a request to quit ended the whole app
  // when the red traffic light was clicked.
  testWidgets('a close that was not intercepted is left alone', (tester) async {
    debugTrayInterceptsCloseOverride = true;
    final container = await pumpTray(tester);
    await container.read(settingsProvider.notifier).setKeepRunningInTray(false);
    await settle(tester);
    windowCalls.clear();
    trayCalls.clear();

    preventClose = false;
    final host = tester.state(find.byType(DesktopTrayHost)) as WindowListener;
    host.onWindowClose();
    await settle(tester);

    expect(windowCalls.map((c) => c.method), isNot(contains('hide')));
    expect(windowCalls.map((c) => c.method), isNot(contains('destroy')));
    expect(
      platformCalls.map((c) => c.method),
      isNot(contains('SystemNavigator.pop')),
    );

    await unpump(tester, container);
  });

  testWidgets('the close is intercepted only once the icon is up', (
    tester,
  ) async {
    debugTrayInterceptsCloseOverride = true;
    final container = await pumpTray(tester);

    expect(preventClose, isTrue);
    expect(
      log.indexOf('tray.setIcon'),
      lessThan(log.indexOf('window.setPreventClose(true)')),
    );

    await unpump(tester, container);
  });

  // A desktop with no tray host still has to be closable: hiding the window
  // there leaves nothing on screen to bring it back.
  testWidgets('a tray that cannot show an icon leaves the close alone', (
    tester,
  ) async {
    debugTrayInterceptsCloseOverride = true;
    failSetIcon = true;
    final container = await pumpTray(tester);

    expect(trayCalls.map((c) => c.method), contains('setIcon'));
    expect(preventClose, isFalse);
    expect(
      windowCalls.where(
        (c) =>
            c.method == 'setPreventClose' &&
            (c.arguments as Map)['isPreventClose'] == true,
      ),
      isEmpty,
    );

    await unpump(tester, container);
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
