import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import 'package:shellvibe/app/theme/app_theme.dart';
import 'package:shellvibe/features/hosts/presentation/dialogs/host_form_dialog.dart';
import 'package:shellvibe/features/hosts/presentation/dialogs/host_group_form_dialog.dart';
import 'package:shellvibe/features/hosts/presentation/dialogs/ssh_config_import_dialog.dart';
import 'package:shellvibe/features/hosts/presentation/screens/hosts_screen.dart';
import 'package:shellvibe/features/settings/presentation/screens/settings_screen.dart';
import 'package:shellvibe/features/sftp/presentation/screens/sftp_dual_pane_screen.dart';
import 'package:shellvibe/features/snippets/presentation/screens/runbooks_screen.dart';
import 'package:shellvibe/features/snippets/presentation/screens/snippets_screen.dart';
import 'package:shellvibe/features/snippets/presentation/widgets/runbook_editor_dialog.dart';
import 'package:shellvibe/features/snippets/presentation/widgets/snippet_form_dialog.dart';
import 'package:shellvibe/features/snippets/presentation/widgets/variable_input_dialog.dart';
import 'package:shellvibe/features/templates/presentation/dialogs/save_template_dialog.dart';
import 'package:shellvibe/features/terminal/presentation/views/terminal_tab_view.dart';
import 'package:shellvibe/features/tunnels/presentation/screens/tunnels_screen.dart';
import 'package:shellvibe/features/tunnels/presentation/widgets/tunnel_form_dialog.dart';
import 'package:shellvibe/features/vault/presentation/dialogs/identity_form_dialog.dart';
import 'package:shellvibe/features/vault/presentation/dialogs/vault_unlock_dialog.dart';
import 'package:shellvibe/features/vault/presentation/screens/vault_screen.dart';
import 'package:shellvibe/features/workspaces/presentation/screens/workspace_manager_screen.dart';
import 'package:shellvibe/shared/database/app_database.dart';
import 'package:shellvibe/shared/providers/database_providers.dart';

/// Every module and every dialog, laid out at the sizes real devices hand them.
///
/// Overflow is a layout *error*, not a cosmetic one: Flutter reports it through
/// the same channel as an exception, so pumping each surface and asserting the
/// error channel is empty is enough to catch the whole class. The sizes are the
/// ones that used to break — a small phone, a phone held sideways (which is
/// wide and very short), and a system text scale turned up.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase db;

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    await db.workspacesDao.insertWorkspace(
      WorkspacesCompanion.insert(
        id: 'default',
        name: 'Default Workspace',
        createdAt: DateTime.now(),
      ),
    );
  });

  tearDown(() async => db.close());

  Future<void> pumpAt(
    WidgetTester tester,
    Size size,
    Widget surface, {
    double textScale = 1.0,
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [appDatabaseProvider.overrideWithValue(db)],
        child: ShadTheme(
          data: AppTheme.darkShadTheme,
          child: MaterialApp(
            theme: AppTheme.darkTheme,
            builder: (context, child) => MediaQuery.withClampedTextScaling(
              minScaleFactor: textScale,
              maxScaleFactor: textScale,
              child: child!,
            ),
            home: Scaffold(body: surface),
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 300));
  }

  const sizes = <String, Size>{
    // iPhone 15-class portrait.
    'phone-390x844': Size(390, 844),
    // The smallest screen still shipping — iPhone SE 1st gen.
    'small-320x568': Size(320, 568),
    // Wide and short: the width tier alone would call this a desktop.
    'landscape-852x393': Size(852, 393),
    'tablet-834x1194': Size(834, 1194),
    'desktop-1440x900': Size(1440, 900),
  };

  final modules = <String, Widget Function()>{
    'HostsScreen': () => const HostsScreen(),
    'SettingsScreen': () => const SettingsScreen(),
    'VaultScreen': () => const VaultScreen(),
    'TunnelsScreen': () => const TunnelsScreen(),
    'SnippetsScreen': () => const SnippetsScreen(workspaceId: 'default'),
    'RunbooksScreen': () => const RunbooksScreen(workspaceId: 'default'),
    'WorkspaceManagerScreen': () => const WorkspaceManagerScreen(),
    'SftpDualPaneScreen': () => const SftpDualPaneScreen(),
    'TerminalTabView': () => const TerminalTabView(),
  };

  final dialogs = <String, Widget Function()>{
    'HostFormDialog': () => const HostFormDialog(workspaceId: 'default'),
    'HostGroupFormDialog': () =>
        const HostGroupFormDialog(workspaceId: 'default'),
    'IdentityFormDialog': () =>
        const IdentityFormDialog(workspaceId: 'default'),
    'VaultUnlockDialog': () => const VaultUnlockDialog(),
    'TunnelFormDialog': () => const TunnelFormDialog(),
    'SnippetFormDialog': () => const SnippetFormDialog(workspaceId: 'default'),
    'RunbookEditorDialog': () =>
        const RunbookEditorDialog(workspaceId: 'default'),
    'SaveTemplateDialog': () => const SaveTemplateDialog(),
    'VariableInputDialog': () =>
        const VariableInputDialog(variables: ['HOST', 'PORT']),
    'SshConfigImportDialog': () => const SshConfigImportDialog(
      filePath: '/tmp/config',
      content: 'Host web\n  HostName 10.0.0.1\n  User root\n',
    ),
  };

  group('modules lay out without overflow', () {
    for (final module in modules.entries) {
      for (final size in sizes.entries) {
        testWidgets('${module.key} @ ${size.key}', (tester) async {
          await pumpAt(tester, size.value, module.value());
          expect(tester.takeException(), isNull);
        });
      }
    }
  });

  group('dialogs lay out without overflow', () {
    for (final dialog in dialogs.entries) {
      for (final size in sizes.entries) {
        testWidgets('${dialog.key} @ ${size.key}', (tester) async {
          await pumpAt(tester, size.value, dialog.value());
          expect(tester.takeException(), isNull);
        });
      }
    }
  });

  group('modules survive an enlarged system text scale', () {
    for (final module in modules.entries) {
      for (final scale in [1.3, 2.0]) {
        testWidgets('${module.key} @ ${scale}x', (tester) async {
          await pumpAt(
            tester,
            const Size(390, 844),
            module.value(),
            textScale: scale,
          );
          expect(tester.takeException(), isNull);
        });
      }
    }
  });
}
