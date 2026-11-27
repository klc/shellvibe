import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import 'package:shellvibe/features/mcp/data/mcp_agent_config.dart';
import 'package:shellvibe/features/mcp/domain/models/mcp_enums.dart';
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

/// Records the tool switches instead of writing them to secure storage.
class _RecordingSettings extends _Settings {
  final changes = <(McpToolGroup, bool)>[];

  @override
  Future<void> setToolGroupEnabled(McpToolGroup group, bool enabled) async {
    changes.add((group, enabled));
  }
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
    // The card reads and writes real files, one await at a time, so a slow
    // runner needs more turns than a fast one: wait for [done] when given.
    Future<void> settle([bool Function()? done]) async {
      for (var i = 0; i < (done == null ? 40 : 400); i++) {
        if (done?.call() ?? false) return;
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

    bool switchIs(bool value) =>
        tester.widget<ShadSwitch>(hookSwitch).value == value;

    await tester.tap(hookSwitch);
    await settle(() => switchIs(true));
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
    await settle(() => switchIs(false));
    expect(jsonDecode(settings.readAsStringSync()), <String, dynamic>{});
    expect(tester.widget<ShadSwitch>(hookSwitch).value, isFalse);
  });

  testWidgets('Agent tools shows one switch per group and flips it', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 4000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final settings = _RecordingSettings();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          mcpSettingsProvider.overrideWith(() => settings),
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
    for (var i = 0; i < 40; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 10)),
      );
      await tester.pump();
    }

    for (final group in McpToolGroup.values) {
      final tile = find.byKey(Key('mcp_tool_group_${group.name}'));
      expect(tile, findsOneWidget);
      expect(tester.widget<SwitchListTile>(tile).value, isTrue);
    }

    await tester.tap(find.byKey(const Key('mcp_tool_group_fileTransfer')));
    await tester.pump();
    expect(settings.changes, [(McpToolGroup.fileTransfer, false)]);
  });
}
