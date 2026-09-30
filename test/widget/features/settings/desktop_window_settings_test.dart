import 'dart:async';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import 'package:shellvibe/app/notifications/notification_policy.dart';
import 'package:shellvibe/app/notifications/notification_presenter.dart';
import 'package:shellvibe/app/notifications/notification_providers.dart';
import 'package:shellvibe/app/window/launch_at_login.dart';
import 'package:shellvibe/features/settings/presentation/notifiers/settings_notifier.dart';
import 'package:shellvibe/features/settings/presentation/screens/settings_screen.dart';
import 'package:shellvibe/shared/database/app_database.dart';
import 'package:shellvibe/shared/providers/database_providers.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase db;
  late _FakeLaunchAtLogin login;
  late _FakePresenter presenter;

  setUp(() {
    FlutterSecureStorage.setMockInitialValues({});
    db = AppDatabase(NativeDatabase.memory());
    login = _FakeLaunchAtLogin();
    presenter = _FakePresenter();
  });

  tearDown(() async {
    await db.close();
  });

  Future<ProviderContainer> pumpSettings(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1600, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() => tester.view.resetPhysicalSize());

    final container = ProviderContainer(
      overrides: [
        appDatabaseProvider.overrideWithValue(db),
        launchAtLoginProvider.overrideWithValue(login),
        notificationPresenterProvider.overrideWithValue(presenter),
      ],
    );
    addTearDown(container.dispose);
    await container.read(settingsProvider.future);

    final router = GoRouter(
      initialLocation: '/settings',
      routes: [
        GoRoute(
          path: '/settings',
          builder: (context, state) => const SettingsScreen(),
        ),
      ],
    );
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: ShadTheme(
          data: ShadThemeData(
            colorScheme: const ShadSlateColorScheme.light(),
            brightness: Brightness.light,
          ),
          child: MaterialApp.router(
            routerConfig: router,
            // The toasts the screen raises need a toaster above the router.
            builder: (context, child) => ShadToaster(child: child!),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return container;
  }

  bool switchValue(WidgetTester tester, String key) =>
      tester.widget<SwitchListTile>(find.byKey(Key(key))).value;

  Future<void> tapSwitch(WidgetTester tester, String key) async {
    await tester.ensureVisible(find.byKey(Key(key)));
    await tester.tap(find.byKey(Key(key)));
    await tester.pumpAndSettle();
  }

  group('Desktop Notifications switch', () {
    testWidgets('is on by default and turns off and on, persisted', (
      tester,
    ) async {
      final container = await pumpSettings(tester);
      const key = 'settings_desktop_notifications_switch';

      expect(switchValue(tester, key), isTrue);

      await tapSwitch(tester, key);
      expect(switchValue(tester, key), isFalse);
      expect(
        container.read(settingsProvider).value!.desktopNotifications,
        isFalse,
      );
      // Turning it off asks the OS for nothing.
      expect(presenter.permissionRequests, 0);

      await tapSwitch(tester, key);
      expect(switchValue(tester, key), isTrue);
      expect(
        container.read(settingsProvider).value!.desktopNotifications,
        isTrue,
      );
      // Turning it on is the moment macOS has to be asked.
      expect(presenter.permissionRequests, 1);
    });
  });

  group('Start at Login switch', () {
    const key = 'settings_launch_at_login_switch';

    testWidgets('reflects the OS and writes to it', (tester) async {
      await pumpSettings(tester);

      expect(switchValue(tester, key), isFalse);

      await tapSwitch(tester, key);
      expect(login.enabled, isTrue);
      expect(switchValue(tester, key), isTrue);

      await tapSwitch(tester, key);
      expect(login.enabled, isFalse);
      expect(switchValue(tester, key), isFalse);
    });

    testWidgets('starts out as the OS has it', (tester) async {
      login.enabled = true;
      await pumpSettings(tester);

      expect(switchValue(tester, key), isTrue);
    });

    testWidgets('cannot be turned on while the tray is off', (tester) async {
      final container = await pumpSettings(tester);

      await container
          .read(settingsProvider.notifier)
          .setKeepRunningInTray(false);
      await tester.pumpAndSettle();

      final tile = tester.widget<SwitchListTile>(find.byKey(const Key(key)));
      expect(tile.onChanged, isNull);
      expect(tile.value, isFalse);
      expect(
        find.textContaining('Turn on the tray icon first'),
        findsOneWidget,
      );
    });

    testWidgets('can still be turned off while the tray is off', (
      tester,
    ) async {
      login.enabled = true;
      final container = await pumpSettings(tester);

      await container
          .read(settingsProvider.notifier)
          .setKeepRunningInTray(false);
      await tester.pumpAndSettle();

      await tapSwitch(tester, key);
      expect(login.enabled, isFalse);
    });

    testWidgets('is hidden where login items are not supported', (
      tester,
    ) async {
      login.supported = false;
      await pumpSettings(tester);

      expect(find.byKey(const Key(key)), findsNothing);
      // The rest of the section is unaffected.
      expect(
        find.byKey(const Key('settings_keep_running_in_tray_switch')),
        findsOneWidget,
      );
    });

    testWidgets('a refused write is reported and the switch stays honest', (
      tester,
    ) async {
      login.failWrites = true;
      await pumpSettings(tester);

      await tapSwitch(tester, key);

      expect(switchValue(tester, key), isFalse);
      expect(find.text('Could not change start at login'), findsOneWidget);
    });
  });
}

class _FakeLaunchAtLogin implements LaunchAtLogin {
  bool enabled = false;
  bool supported = true;
  bool failWrites = false;

  @override
  Future<bool> isSupported() async => supported;

  @override
  Future<bool> isEnabled() async => enabled;

  @override
  Future<void> setEnabled(bool value) async {
    if (failWrites) throw StateError('refused');
    enabled = value;
  }
}

class _FakePresenter implements NotificationPresenter {
  int permissionRequests = 0;
  final shown = <NotificationRequest>[];

  @override
  Stream<String?> get clicks => const Stream.empty();

  @override
  Future<bool> ensurePermission() async {
    permissionRequests++;
    return true;
  }

  @override
  Future<void> show(NotificationRequest request) async => shown.add(request);

  @override
  Future<void> dispose() async {}
}
