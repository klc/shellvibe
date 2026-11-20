import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import 'package:shellvibe/features/mcp/data/mcp_agent_config.dart';
import 'package:shellvibe/features/mcp/presentation/notifiers/mcp_activity_notifier.dart';
import 'package:shellvibe/features/mcp/presentation/notifiers/mcp_settings_notifier.dart';
import 'package:shellvibe/features/mcp/presentation/widgets/mcp_access_settings_section.dart';

class _Settings extends McpSettingsNotifier {
  @override
  Future<McpSettingsState> build() async => const McpSettingsState(
    masterEnabled: true,
    serverRunning: true,
    serverPort: 1,
    defaultCommandTimeoutSeconds: 60,
    outputCapBytes: 1 << 20,
    sessionIdleTimeoutMinutes: 30,
    auditRetentionDays: 30,
  );
}

class _Activity extends McpActivityNotifier {
  @override
  Future<McpActivityState> build() async => McpActivityState.empty;
}

void main() {
  late Directory home;
  late String bridge;

  setUp(() {
    home = Directory.systemTemp.createTempSync('mcp_hook_home');
    final bin = Directory('${home.path}/app')..createSync();
    bridge = '${bin.path}/shellvibe-mcp';
    File(bridge).writeAsStringSync('');
    // Claude Code already has the MCP entry; nothing else is set up.
    File('${home.path}/.claude.json').writeAsStringSync(
      jsonEncode({
        'mcpServers': {
          'shellvibe': {'command': bridge},
        },
      }),
    );
    debugMcpAgentEnvironmentOverride = {'HOME': home.path};
    debugMcpResolvedExecutableOverride = '${bin.path}/ShellVibe';
  });

  tearDown(() {
    debugMcpAgentEnvironmentOverride = null;
    debugMcpResolvedExecutableOverride = null;
    home.deleteSync(recursive: true);
  });

  testWidgets('the switch adds and removes the hook, only for a tool whose '
      'MCP entry is in', (tester) async {
    tester.view.physicalSize = const Size(1200, 3000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          mcpSettingsProvider.overrideWith(_Settings.new),
          mcpActivityProvider.overrideWith(_Activity.new),
        ],
        child: ShadTheme(
          data: ShadThemeData(
            colorScheme: const ShadSlateColorScheme.light(),
            brightness: Brightness.light,
          ),
          child: MaterialApp(
            builder: (context, child) => ShadToaster(child: child!),
            home: const Scaffold(
              body: SingleChildScrollView(child: McpAccessSettingsSection()),
            ),
          ),
        ),
      ),
    );
    // The card reads and writes real files, one await at a time.
    Future<void> settle() async {
      for (var i = 0; i < 40; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 10)),
        );
        await tester.pump();
      }
    }

    await settle();

    final settings = File('${home.path}/.claude/settings.json');
    final hookSwitch = find.byKey(
      const Key('mcp_agent_hook_switch_claudeCode'),
    );
    expect(hookSwitch, findsOneWidget);
    // Cursor and Codex have no MCP entry, so no hook is offered for them.
    expect(find.byKey(const Key('mcp_agent_hook_cursor')), findsNothing);
    expect(find.byKey(const Key('mcp_agent_hook_codex')), findsNothing);

    await tester.tap(hookSwitch);
    await settle();
    expect(
      mcpHookStatus(
        McpAgentApp.claudeCode,
        settings.readAsStringSync(),
        mcpHookCommand(McpAgentApp.claudeCode, bridge),
      ),
      McpAgentConfigStatus.installed,
    );
    expect(tester.widget<ShadSwitch>(hookSwitch).value, isTrue);

    await tester.tap(hookSwitch);
    await settle();
    expect(jsonDecode(settings.readAsStringSync()), <String, dynamic>{});
    expect(tester.widget<ShadSwitch>(hookSwitch).value, isFalse);
  });
}
