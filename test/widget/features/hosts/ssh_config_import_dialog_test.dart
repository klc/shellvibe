import 'package:cryptography/cryptography.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import 'package:shellvibe/core/crypto/encryption_engine.dart';
import 'package:shellvibe/features/hosts/data/services/ssh_config_import_service.dart';
import 'package:shellvibe/features/hosts/presentation/dialogs/ssh_config_import_dialog.dart';
import 'package:shellvibe/features/hosts/presentation/notifiers/host_groups_notifier.dart';
import 'package:shellvibe/features/hosts/presentation/providers/ssh_config_import_provider.dart';
import 'package:shellvibe/features/vault/presentation/notifiers/vault_notifier.dart';
import 'package:shellvibe/features/vault/data/vault_key_service.dart';
import 'package:shellvibe/features/vault/presentation/notifiers/identities_notifier.dart';
import 'package:shellvibe/shared/database/app_database.dart';
import 'package:shellvibe/shared/providers/database_providers.dart';
import 'package:shellvibe/shared/storage/secure_storage_service.dart';
import 'package:shellvibe/app/widgets/shellvibe_ui.dart';

class _UnlockedFakeVaultKeyService extends VaultKeyService {
  _UnlockedFakeVaultKeyService()
    : super(
        encryptionEngine: EncryptionEngine(),
        secureStorageService: SecureStorageService(),
      );

  @override
  Future<SecretKey> getDek() async => SecretKey(List<int>.filled(32, 7));
}

class _LockedFakeVaultKeyService extends VaultKeyService {
  _LockedFakeVaultKeyService()
    : super(
        encryptionEngine: EncryptionEngine(),
        secureStorageService: _MasterPasswordStorage(),
      );

  @override
  Future<SecretKey> getDek() async => throw const VaultLockedException();
}

/// Secure storage that reports a master password as configured, so the vault
/// notifier reports `locked` for the locked key service.
class _MasterPasswordStorage extends SecureStorageService {
  @override
  Future<bool> containsKey({required String key}) async =>
      key == SecureStorageKeys.masterSalt;

  @override
  Future<String?> read({required String key}) async =>
      key == SecureStorageKeys.masterSalt ? 'salt' : null;
}

void main() {
  late AppDatabase db;
  late Map<String, String> fs;

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    await db.workspacesDao.insertWorkspace(
      WorkspacesCompanion.insert(
        id: 'default',
        name: 'Default Workspace',
        createdAt: DateTime.now(),
      ),
    );
    fs = {
      '/home/user/.ssh/id_ed25519':
          '-----BEGIN OPENSSH PRIVATE KEY-----\nabc\n-----END OPENSSH PRIVATE KEY-----\n',
    };
  });

  tearDown(() async {
    await db.close();
  });

  SshConfigImportService buildService(VaultKeyService vaultKeyService) {
    return SshConfigImportService(
      db: db,
      vaultKeyService: vaultKeyService,
      encryptionEngine: EncryptionEngine(),
      homePath: '/home/user',
      environment: const {},
      readFile: (p) => fs[p],
      listDir: (d) => null,
    );
  }

  /// Host widget that opens the import dialog through showDialog, so the pop
  /// on success can be observed.
  Widget buildHost(VaultKeyService vaultKeyService) {
    return ProviderScope(
      overrides: [
        appDatabaseProvider.overrideWithValue(db),
        vaultKeyServiceProvider.overrideWithValue(vaultKeyService),
        sshConfigImportServiceProvider.overrideWithValue(
          buildService(vaultKeyService),
        ),
      ],
      child: ShadTheme(
        data: ShadThemeData(
          colorScheme: const ShadSlateColorScheme.light(),
          brightness: Brightness.light,
        ),
        child: MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: Center(
                child: ElevatedButton(
                  key: const Key('open_import'),
                  onPressed: () => showDialog<SshConfigImportResult>(
                    context: context,
                    builder: (_) => const SshConfigImportDialog(
                      filePath: 'config',
                      content: 'Host web\n'
                          '  HostName web.example.com\n'
                          '  User deploy\n'
                          '  Port 2222\n'
                          '  IdentityFile ~/.ssh/id_ed25519\n',
                    ),
                  ),
                  child: const Text('Open'),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  testWidgets('preview lists discovered hosts and import persists them',
      (tester) async {
    await tester.pumpWidget(buildHost(_UnlockedFakeVaultKeyService()));
    await tester.tap(find.byKey(const Key('open_import')));
    await tester.pumpAndSettle();

    // Preview content.
    expect(find.text('Import SSH Config'), findsOneWidget);
    expect(find.text('web'), findsOneWidget);
    expect(find.text('deploy@web.example.com:2222'), findsOneWidget);
    expect(find.text('1 of 1 hosts selected'), findsOneWidget);
    expect(find.byKey(const Key('import_host_web')), findsOneWidget);

    // Import.
    await tester.tap(find.byKey(const Key('ssh_config_import_button')));
    await tester.pumpAndSettle();

    // Dialog closed and the host persisted with its identity.
    expect(find.byKey(const Key('open_import')), findsOneWidget);
    final rows = await db.hostsDao.getHostsByWorkspace('default');
    expect(rows, hasLength(1));
    expect(rows.single.label, 'web');
    expect(rows.single.hostname, 'web.example.com');
    expect(rows.single.username, 'deploy');
    expect(rows.single.port, 2222);
    expect(rows.single.identityId, isNotNull);
    expect(
      (await db.identitiesDao.getIdentitiesByWorkspace('default')).single
          .privateKeyEncrypted,
      isNotNull,
    );
  });

  testWidgets('import stays enabled when the surrounding providers are warm',
      (tester) async {
    // Regression: the default selection was applied without setState, so the
    // Import button — which lives in ShadDialog.actions, outside the
    // FutureBuilder subtree — only became enabled if some *other* rebuild
    // happened to follow the resolution. In the real app hostGroupsProvider
    // and vaultProvider are already warm (the hosts screen watches them), so
    // no such rebuild arrives and the button stayed dead.
    final vks = _UnlockedFakeVaultKeyService();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appDatabaseProvider.overrideWithValue(db),
          vaultKeyServiceProvider.overrideWithValue(vks),
          sshConfigImportServiceProvider.overrideWithValue(buildService(vks)),
        ],
        child: ShadTheme(
          data: ShadThemeData(
            colorScheme: const ShadSlateColorScheme.light(),
            brightness: Brightness.light,
          ),
          child: MaterialApp(
            home: Consumer(
              builder: (context, ref, _) {
                ref.watch(hostGroupsProvider);
                ref.watch(vaultProvider);
                return Scaffold(
                  body: Center(
                    child: ElevatedButton(
                      key: const Key('open_import'),
                      onPressed: () => showDialog<SshConfigImportResult>(
                        context: context,
                        builder: (_) => const SshConfigImportDialog(
                          filePath: 'config',
                          content: 'Host web\n  HostName web.example.com\n',
                        ),
                      ),
                      child: const Text('Open'),
                    ),
                  ),
                );
              },
            ),
          ),
        ),
      ),
    );
    // Let both providers settle *before* the dialog is opened.
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('open_import')));
    await tester.pumpAndSettle();

    expect(find.text('1 of 1 hosts selected'), findsOneWidget);
    final button = tester.widget<ShellVibeButton>(
      find.byKey(const Key('ssh_config_import_button')),
    );
    expect(button.onPressed, isNotNull, reason: 'Import must be tappable');

    await tester.tap(find.byKey(const Key('ssh_config_import_button')));
    await tester.pumpAndSettle();
    expect(await db.hostsDao.getHostsByWorkspace('default'), hasLength(1));
  });

  testWidgets('locked vault disables the private key import toggle',
      (tester) async {
    final locked = _LockedFakeVaultKeyService();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appDatabaseProvider.overrideWithValue(db),
          vaultKeyServiceProvider.overrideWithValue(locked),
          secureStorageServiceProvider.overrideWithValue(
            _MasterPasswordStorage(),
          ),
          sshConfigImportServiceProvider.overrideWithValue(buildService(locked)),
        ],
        child: ShadTheme(
          data: ShadThemeData(
            colorScheme: const ShadSlateColorScheme.light(),
            brightness: Brightness.light,
          ),
          child: MaterialApp(
            home: Builder(
              builder: (context) => Scaffold(
                body: Center(
                  child: ElevatedButton(
                    key: const Key('open_import'),
                    onPressed: () => showDialog<SshConfigImportResult>(
                      context: context,
                      builder: (_) => const SshConfigImportDialog(
                        filePath: 'config',
                        content: 'Host web\n  HostName web.example.com\n',
                      ),
                    ),
                    child: const Text('Open'),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.byKey(const Key('open_import')));
    await tester.pumpAndSettle();

    expect(
      find.text('Vault is locked — unlock it to enable.'),
      findsOneWidget,
    );
    final toggle = tester.widget<Switch>(
      find.descendant(
        of: find.byKey(const Key('import_keys_toggle')),
        matching: find.byType(Switch),
      ),
    );
    expect(toggle.onChanged, isNull, reason: 'toggle must be disabled');
    expect(toggle.value, isFalse);
  });
}
