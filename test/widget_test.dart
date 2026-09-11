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

  testWidgets('ShellVibeApp opens the launch shell but no Device Link listener '
      'when the vault fails to load', (WidgetTester tester) async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(() => db.close());

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appDatabaseProvider.overrideWithValue(db),
          localPtyManagerProvider.overrideWithValue(_NullPtyManager()),
          vaultKeyServiceProvider.overrideWith(
            (ref) => _FailingVaultKeyService(
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
    // A vault that fails to load is not a lock — the router lets the app
    // through, so leaving the user without a terminal would strand them.
    expect(container.read(terminalTabsProvider).tabs.length, equals(1));
    // Device Link is gated harder than the shell: an unresolved vault opens
    // no LAN listener.
    expect(
      container.read(terminalTabsProvider.notifier).isDeviceLinkServerRunning,
      isFalse,
    );
  });
}

/// Vault key service whose configuration probe fails, which is what puts
/// [vaultProvider] into an error state.
class _FailingVaultKeyService extends VaultKeyService {
  _FailingVaultKeyService({
    required super.encryptionEngine,
    required super.secureStorageService,
  });

  @override
  Future<bool> isMasterPasswordConfigured() async {
    throw const FileSystemException('keychain unavailable');
  }
}
