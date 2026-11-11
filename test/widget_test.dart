import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shellvibe/app/app.dart';
import 'package:shellvibe/core/network/local_pty_manager.dart';
import 'package:shellvibe/core/network/providers/network_providers.dart';
import 'package:shellvibe/core/utils/platform_capabilities.dart';
import 'package:shellvibe/features/terminal/presentation/notifiers/terminal_tabs_notifier.dart';
import 'package:shellvibe/features/vault/data/vault_key_service.dart';
import 'package:shellvibe/features/vault/presentation/notifiers/identities_notifier.dart';
import 'package:shellvibe/features/vault/presentation/notifiers/vault_notifier.dart';
import 'package:shellvibe/shared/database/app_database.dart';
import 'package:shellvibe/shared/providers/database_providers.dart';
import 'package:shellvibe/shared/storage/secure_storage_service.dart';
import 'package:xterm3/xterm.dart';

/// Test double that never spawns a real PTY, keeping the app-level startup
/// tests hermetic instead of launching the host's shell.
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

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    // The launch shell waits for the vault status to resolve (it must not
    // spawn a shell behind a locked vault), and the vault reads secure
    // storage — without the mock it never resolves in tests.
    FlutterSecureStorage.setMockInitialValues({});
  });

  testWidgets(
    'ShellVibeApp lands on the terminal screen with a local shell open '
    'at startup on desktop',
    (WidgetTester tester) async {
      final db = AppDatabase(NativeDatabase.memory());
      addTearDown(() => db.close());

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            appDatabaseProvider.overrideWithValue(db),
            localPtyManagerProvider.overrideWithValue(_NullPtyManager()),
          ],
          child: const ShellVibeApp(),
        ),
      );

      await tester.pumpAndSettle();

      final container = ProviderScope.containerOf(
        tester.element(find.byType(ShellVibeApp)),
      );

      // The rail is icon-only, so the brand is a mark rather than a wordmark.
      expect(find.byKey(const Key('header_brand_logo')), findsOneWidget);

      // The app launches into the terminal screen with a local shell tab open
      // (tab header and pane title both carry the label).
      expect(find.text('Local Shell'), findsWidgets);
      expect(container.read(terminalTabsProvider).tabs.length, equals(1));
    },
  );

  testWidgets('ShellVibeApp does not open a local shell on mobile', (
    WidgetTester tester,
  ) async {
    debugPlatformCapabilitiesOverride = TargetPlatform.android;
    addTearDown(() => debugPlatformCapabilitiesOverride = null);

    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(() => db.close());

    await tester.pumpWidget(
      ProviderScope(
        overrides: [appDatabaseProvider.overrideWithValue(db)],
        child: const ShellVibeApp(),
      ),
    );

    await tester.pumpAndSettle();

    final container = ProviderScope.containerOf(
      tester.element(find.byType(ShellVibeApp)),
    );

    // Terminal screen shows, but no local shell is started — mobile connects
    // via SSH only.
    expect(container.read(terminalTabsProvider).tabs, isEmpty);
    expect(find.text('No open sessions'), findsOneWidget);
  });

  testWidgets(
    'ShellVibeApp does not open the launch shell behind a locked vault',
    (WidgetTester tester) async {
      // A configured master password that has not been unlocked in memory is a
      // locked vault, without paying for an Argon2id derivation here.
      FlutterSecureStorage.setMockInitialValues({
        SecureStorageKeys.masterSalt: base64.encode(List.filled(16, 7)),
      });

      final db = AppDatabase(NativeDatabase.memory());
      addTearDown(() => db.close());

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            appDatabaseProvider.overrideWithValue(db),
            localPtyManagerProvider.overrideWithValue(_NullPtyManager()),
          ],
          child: const ShellVibeApp(),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      final container = ProviderScope.containerOf(
        tester.element(find.byType(ShellVibeApp)),
      );

      expect(container.read(vaultProvider).value?.status, VaultStatus.locked);
      // The unlock screen is up; the user's login shell must not be spawned
      // behind it.
      expect(container.read(terminalTabsProvider).tabs, isEmpty);
    },
  );

  testWidgets('ShellVibeApp fails closed when the vault fails to load, and '
      'opens once a retry reads it', (WidgetTester tester) async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(() => db.close());
    late _FailingVaultKeyService keyService;

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appDatabaseProvider.overrideWithValue(db),
          localPtyManagerProvider.overrideWithValue(_NullPtyManager()),
          vaultKeyServiceProvider.overrideWith(
            (ref) => keyService = _FailingVaultKeyService(
              encryptionEngine: ref.watch(encryptionEngineProvider),
              secureStorageService: ref.watch(secureStorageServiceProvider),
            ),
          ),
        ],
        child: const ShellVibeApp(),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));

    final container = ProviderScope.containerOf(
      tester.element(find.byType(ShellVibeApp)),
    );

    expect(container.read(vaultProvider).hasError, isTrue);
    // The vault might be locked: no hosts behind it, no login shell, no LAN
    // listener, only the error and a way to try again.
    expect(find.text('Vault Unavailable'), findsOneWidget);
    expect(find.text('Local Shell'), findsNothing);
    expect(container.read(terminalTabsProvider).tabs, isEmpty);
    expect(
      container.read(terminalTabsProvider.notifier).isDeviceLinkServerRunning,
      isFalse,
    );

    keyService.fail = false;
    await tester.tap(find.byKey(const Key('vault_retry_button')));
    await tester.pumpAndSettle();

    expect(
      container.read(vaultProvider).value?.status,
      VaultStatus.unconfigured,
    );
    expect(container.read(terminalTabsProvider).tabs.length, equals(1));
  });
}

/// Vault key service whose configuration probe fails, which is what puts
/// [vaultProvider] into an error state.
class _FailingVaultKeyService extends VaultKeyService {
  _FailingVaultKeyService({
    required super.encryptionEngine,
    required super.secureStorageService,
  });

  var fail = true;

  @override
  Future<bool> isMasterPasswordConfigured() async {
    if (fail) throw const FileSystemException('keychain unavailable');
    return false;
  }
}
