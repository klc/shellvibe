import 'package:drift/native.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shellvibe/app/app.dart';
import 'package:shellvibe/core/network/local_pty_manager.dart';
import 'package:shellvibe/core/network/providers/network_providers.dart';
import 'package:shellvibe/core/utils/platform_capabilities.dart';
import 'package:shellvibe/features/settings/presentation/notifiers/settings_notifier.dart';
import 'package:shellvibe/features/vault/presentation/notifiers/vault_notifier.dart';
import 'package:shellvibe/shared/database/app_database.dart';
import 'package:shellvibe/shared/providers/database_providers.dart';
import 'package:xterm3/xterm.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late DateTime now;
  late _RecordingVaultNotifier vault;

  setUp(() {
    FlutterSecureStorage.setMockInitialValues({});
    now = DateTime(2026, 1, 1, 12);
    debugAutoLockClockOverride = () => now;
    vault = _RecordingVaultNotifier();
  });

  tearDown(() => debugAutoLockClockOverride = null);

  Future<void> pumpApp(WidgetTester tester, {required int autoLock}) async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appDatabaseProvider.overrideWithValue(db),
          localPtyManagerProvider.overrideWithValue(_NullPtyManager()),
          vaultProvider.overrideWith(() => vault),
        ],
        child: const ShellVibeApp(),
      ),
    );
    await tester.pumpAndSettle();
    final container = ProviderScope.containerOf(
      tester.element(find.byType(ShellVibeApp)),
    );
    await container.read(settingsProvider.notifier).setAutoLockTimer(autoLock);
    await tester.pumpAndSettle();
  }

  void lifecycle(WidgetTester tester, List<AppLifecycleState> states) {
    for (final state in states) {
      tester.binding.handleAppLifecycleStateChanged(state);
    }
  }

  const leave = [
    AppLifecycleState.inactive,
    AppLifecycleState.hidden,
    AppLifecycleState.paused,
  ];
  const comeBack = [AppLifecycleState.hidden, AppLifecycleState.inactive];

  // A suspended phone runs no timers, and while it sleeps the monotonic clock
  // a Timer counts on stops too. The timer alone let the vault open unlocked
  // hours later.
  testWidgets('locks on return once the wall clock passes the delay, though '
      'the timer never fired', (tester) async {
    await pumpApp(tester, autoLock: 60);

    lifecycle(tester, leave);
    now = now.add(const Duration(hours: 3));
    lifecycle(tester, comeBack);

    // Before resumed: the vault closes before the app is looked at.
    expect(vault.locks, 1);

    lifecycle(tester, [AppLifecycleState.resumed]);
    await tester.pumpAndSettle();
  });

  testWidgets('a clock set backwards while away still locks', (tester) async {
    await pumpApp(tester, autoLock: 60);

    lifecycle(tester, leave);
    now = now.subtract(const Duration(days: 1));
    lifecycle(tester, [...comeBack, AppLifecycleState.resumed]);

    expect(vault.locks, 1);
    await tester.pumpAndSettle();
  });

  testWidgets('a short absence does not lock, and leaves no timer behind', (
    tester,
  ) async {
    await pumpApp(tester, autoLock: 60);

    lifecycle(tester, leave);
    now = now.add(const Duration(seconds: 20));
    await tester.pump(const Duration(seconds: 20));
    lifecycle(tester, [...comeBack, AppLifecycleState.resumed]);
    expect(vault.locks, 0);

    // The timer started on the way out was cancelled on the way back in.
    await tester.pump(const Duration(minutes: 2));
    expect(vault.locks, 0);
  });

  testWidgets('the timer still locks while a desktop process stays running', (
    tester,
  ) async {
    await pumpApp(tester, autoLock: 60);

    lifecycle(tester, leave);
    await tester.pump(const Duration(seconds: 61));
    expect(vault.locks, 1);

    lifecycle(tester, [...comeBack, AppLifecycleState.resumed]);
    await tester.pumpAndSettle();
  });

  // A desktop window flips between inactive and resumed on every focus
  // change. That is not an absence and must not start the auto-lock clock.
  testWidgets('a desktop focus change is not an absence', (tester) async {
    await pumpApp(tester, autoLock: 60);

    lifecycle(tester, [AppLifecycleState.inactive]);
    // Input keeps arriving, so only an absence clock could lock here.
    for (var i = 0; i < 4; i++) {
      now = now.add(const Duration(seconds: 30));
      await tester.pump(const Duration(seconds: 30));
      await tester.sendKeyEvent(LogicalKeyboardKey.shiftLeft);
    }
    lifecycle(tester, [AppLifecycleState.resumed]);

    expect(vault.locks, 0);
  });

  testWidgets('auto-lock off never locks', (tester) async {
    await pumpApp(tester, autoLock: 0);

    lifecycle(tester, leave);
    now = now.add(const Duration(hours: 3));
    lifecycle(tester, [...comeBack, AppLifecycleState.resumed]);

    expect(vault.locks, 0);
  });
  group('on a desktop', () {
    setUp(() => debugPlatformCapabilitiesOverride = TargetPlatform.macOS);
    tearDown(() => debugPlatformCapabilitiesOverride = null);

    Future<void> idle(WidgetTester tester, Duration duration) async {
      now = now.add(duration);
      await tester.pump(duration);
    }

    // A window can stay in plain view while its user walks away or the OS
    // session is locked; it is never hidden or paused for that.
    testWidgets('locks after the delay without input, window in view', (
      tester,
    ) async {
      await pumpApp(tester, autoLock: 60);

      await idle(tester, const Duration(seconds: 59));
      expect(vault.locks, 0);
      await idle(tester, const Duration(seconds: 2));
      expect(vault.locks, 1);
    });

    testWidgets('input pushes the lock back', (tester) async {
      await pumpApp(tester, autoLock: 60);

      await idle(tester, const Duration(seconds: 40));
      await tester.sendKeyEvent(LogicalKeyboardKey.shiftLeft);
      await idle(tester, const Duration(seconds: 40));
      final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await gesture.addPointer(location: const Offset(10, 10));
      await gesture.moveTo(const Offset(20, 20));
      await idle(tester, const Duration(seconds: 40));
      expect(vault.locks, 0);

      await idle(tester, const Duration(seconds: 21));
      expect(vault.locks, 1);
      await gesture.removePointer();
    });

    // The idle timer counts on the monotonic clock, which stops while the
    // machine sleeps.
    testWidgets('the first input after a sleep locks', (tester) async {
      await pumpApp(tester, autoLock: 60);

      now = now.add(const Duration(hours: 8));
      await tester.sendKeyEvent(LogicalKeyboardKey.shiftLeft);
      expect(vault.locks, 1);
    });

    testWidgets('auto-lock off runs no idle lock', (tester) async {
      await pumpApp(tester, autoLock: 0);

      await idle(tester, const Duration(hours: 3));
      await tester.sendKeyEvent(LogicalKeyboardKey.shiftLeft);
      expect(vault.locks, 0);
    });
  });

  group('on Android', () {
    const channel = MethodChannel('dev.shellvibe.app/secure_window');
    late List<Object?> secure;

    setUp(() {
      debugPlatformCapabilitiesOverride = TargetPlatform.android;
      secure = [];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            if (call.method == 'setSecure') secure.add(call.arguments);
            return null;
          });
    });
    tearDown(() {
      debugPlatformCapabilitiesOverride = null;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
    });

    // The thumbnail is taken on the way out; the auto-lock lands on the way
    // back in, after it.
    testWidgets('a master password keeps the window out of the recent-apps '
        'thumbnail and screenshots', (tester) async {
      await pumpApp(tester, autoLock: 60);

      expect(secure, [true]);
    });

    testWidgets('no master password leaves the window as it is', (
      tester,
    ) async {
      vault = _RecordingVaultNotifier(VaultStatus.unconfigured);
      await pumpApp(tester, autoLock: 60);

      expect(secure.last, isFalse);
    });
  });
}

/// An unlocked vault that counts the locks it is asked for.
class _RecordingVaultNotifier extends VaultNotifier {
  _RecordingVaultNotifier([this.initial = VaultStatus.unlocked]);

  final VaultStatus initial;
  int locks = 0;

  @override
  Future<VaultState> build() async => VaultState(status: initial);

  @override
  Future<void> lock() async {
    locks++;
    state = const AsyncData(VaultState(status: VaultStatus.locked));
  }
}

/// Widget tests must not start real shells.
class _NullPtyManager extends LocalPtyManager {
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
