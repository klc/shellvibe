import 'dart:convert';
import 'dart:io' show File, Platform;

import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:shadcn_ui/shadcn_ui.dart';

import '../../../../app/theme/shellvibe_tokens.dart';
import '../../../../app/widgets/shellvibe_ui.dart';
import '../../../../core/utils/platform_capabilities.dart';
import '../../data/mcp_agent_config.dart';
import '../notifiers/mcp_settings_notifier.dart';
import 'mcp_activity_panel.dart';

/// Settings surface for the MCP agent-access server: the master switch,
/// live server status, registered client tokens, and the numeric knobs a
/// running session obeys.
///
/// Mirrors [PairedDevicesSettingsSection] and [KnownHostsSettingsSection] —
/// same `ShadCard`/`ListTile` shape, same [ShellVibeTokens] palette, no colors
/// invented for this screen.
final class McpAccessSettingsSection extends ConsumerWidget {
  const McpAccessSettingsSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = ShellVibeTokens.resolve(context);
    final settingsAsync = ref.watch(mcpSettingsProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _ExperimentalBanner(tokens: tokens),
        const SizedBox(height: 12),
        Text(
          'Lets an AI agent (Claude Desktop, Claude Code, or another MCP '
          'client) reach your registered hosts through this app, under '
          'per-host approval and policy — never with direct access to a '
          'stored credential. Off by default for every workspace.',
          style: Theme.of(
            context,
          ).textTheme.bodyMedium?.copyWith(color: tokens.textMuted),
        ),
        const SizedBox(height: 12),
        settingsAsync.when(
          loading: () => const Padding(
            padding: EdgeInsets.all(16),
            child: Center(child: CircularProgressIndicator()),
          ),
          error: (error, _) => ShadCard(
            child: ListTile(
              key: const Key('mcp_settings_error'),
              leading: Icon(LucideIcons.circleAlert, color: tokens.danger),
              title: Text('Could not load AI Access settings: $error'),
            ),
          ),
          data: (settings) => _buildLoaded(context, ref, tokens, settings),
        ),
      ],
    );
  }

  Widget _buildLoaded(
    BuildContext context,
    WidgetRef ref,
    ShellVibeTokens tokens,
    McpSettingsState settings,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildMasterSwitchCard(context, ref, tokens, settings),
        const SizedBox(height: 16),
        _AgentAppsCard(
          bridge: _detectBridgeCommand(),
          serverEnabled: settings.masterEnabled,
        ),
        const SizedBox(height: 16),
        // The live panel sits with the switch that enables it: seeing what an
        // agent is doing right now is the same decision as deciding whether it
        // may act at all, and a panel reachable only from elsewhere is a panel
        // nobody opens.
        const McpActivityPanel(),
        const SizedBox(height: 16),
        _buildLimitsCard(context, ref, tokens, settings),
        const SizedBox(height: 16),
        _buildPanicCard(context, ref, tokens),
      ],
    );
  }

  Widget _buildMasterSwitchCard(
    BuildContext context,
    WidgetRef ref,
    ShellVibeTokens tokens,
    McpSettingsState settings,
  ) {
    final statusText = settings.serverRunning && settings.serverPort != null
        ? '127.0.0.1:${settings.serverPort} · running'
        : 'stopped';
    return ShadCard(
      child: Column(
        children: [
          Material(
            color: Colors.transparent,
            child: SwitchListTile(
              key: const Key('mcp_master_switch'),
              title: const Text('Allow AI agent access'),
              subtitle: const Text(
                'Starts a localhost-only MCP server that AI tools reach '
                'through the shellvibe-mcp bridge. Agents see this '
                'workspace\'s hosts.',
              ),
              value: settings.masterEnabled,
              onChanged: (value) => _setMasterEnabled(context, ref, value),
            ),
          ),
          const Divider(height: 1),
          ListTile(
            key: const Key('mcp_server_status'),
            leading: Icon(
              settings.serverRunning
                  ? LucideIcons.serverCog
                  : LucideIcons.serverOff,
              size: 18,
              color: settings.serverRunning ? tokens.brand : tokens.textMuted,
            ),
            title: const Text('Server status'),
            trailing: Text(
              statusText,
              style: shellvibeMono(
                context,
                size: 12,
                color: settings.serverRunning
                    ? tokens.textPrimary
                    : tokens.textMuted,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _setMasterEnabled(
    BuildContext context,
    WidgetRef ref,
    bool value,
  ) async {
    try {
      await ref.read(mcpSettingsProvider.notifier).setMasterEnabled(value);
    } catch (e) {
      if (context.mounted) {
        ShadToaster.of(context).show(
          ShadToast.destructive(
            description: Text('Could not start the MCP server: $e'),
          ),
        );
      }
    }
  }

  Widget _buildLimitsCard(
    BuildContext context,
    WidgetRef ref,
    ShellVibeTokens tokens,
    McpSettingsState settings,
  ) {
    final notifier = ref.read(mcpSettingsProvider.notifier);
    return ShadCard(
      child: Column(
        children: [
          const Align(alignment: Alignment.centerLeft, child: Text('Limits')),
          const Divider(),
          ListTile(
            title: const Text('Default command timeout'),
            subtitle: const Text(
              'How long run_command waits before interrupting and, if '
              'needed, resetting the shell.',
            ),
            trailing: ShadSelect<int>(
              key: const Key('mcp_command_timeout_dropdown'),
              initialValue: settings.defaultCommandTimeoutSeconds,
              selectedOptionBuilder: (context, value) =>
                  Text(_formatSeconds(value)),
              options: const [
                ShadOption(value: 30, child: Text('30 seconds')),
                ShadOption(value: 60, child: Text('60 seconds')),
                ShadOption(value: 120, child: Text('2 minutes')),
                ShadOption(value: 300, child: Text('5 minutes')),
                ShadOption(value: 600, child: Text('10 minutes')),
              ],
              onChanged: (seconds) {
                if (seconds != null) {
                  notifier.setDefaultCommandTimeoutSeconds(seconds);
                }
              },
            ),
          ),
          const Divider(),
          ListTile(
            title: const Text('Output cap'),
            subtitle: const Text(
              'Command output beyond this size is kept from both ends and '
              'truncated in the middle.',
            ),
            trailing: ShadSelect<int>(
              key: const Key('mcp_output_cap_dropdown'),
              initialValue: settings.outputCapBytes,
              selectedOptionBuilder: (context, value) =>
                  Text(_formatBytes(value)),
              options: const [
                ShadOption(value: 50 * 1024, child: Text('50 KB')),
                ShadOption(value: 100 * 1024, child: Text('100 KB')),
                ShadOption(value: 250 * 1024, child: Text('250 KB')),
                ShadOption(value: 500 * 1024, child: Text('500 KB')),
                ShadOption(value: 1024 * 1024, child: Text('1 MB')),
                ShadOption(value: 5 * 1024 * 1024, child: Text('5 MB')),
              ],
              onChanged: (bytes) {
                if (bytes != null) {
                  notifier.setOutputCapBytes(bytes);
                }
              },
            ),
          ),
          const Divider(),
          ListTile(
            title: const Text('Session idle timeout'),
            subtitle: const Text(
              'An open agent session with no activity for this long is '
              'closed automatically.',
            ),
            trailing: ShadSelect<int>(
              key: const Key('mcp_idle_timeout_dropdown'),
              initialValue: settings.sessionIdleTimeoutMinutes,
              selectedOptionBuilder: (context, value) =>
                  Text(_formatMinutes(value)),
              options: const [
                ShadOption(value: 5, child: Text('5 minutes')),
                ShadOption(value: 15, child: Text('15 minutes')),
                ShadOption(value: 30, child: Text('30 minutes')),
                ShadOption(value: 60, child: Text('1 hour')),
                ShadOption(value: 120, child: Text('2 hours')),
              ],
              onChanged: (minutes) {
                if (minutes != null) {
                  notifier.setSessionIdleTimeoutMinutes(minutes);
                }
              },
            ),
          ),
          const Divider(),
          ListTile(
            title: const Text('Audit log retention'),
            subtitle: const Text(
              'Tool calls older than this are purged. Records cannot be '
              'deleted individually — only the retention window changes.',
            ),
            trailing: ShadSelect<int>(
              key: const Key('mcp_audit_retention_dropdown'),
              initialValue: settings.auditRetentionDays,
              selectedOptionBuilder: (context, value) =>
                  Text(_formatDays(value)),
              options: const [
                ShadOption(value: 7, child: Text('7 days')),
                ShadOption(value: 30, child: Text('30 days')),
                ShadOption(value: 90, child: Text('90 days')),
                ShadOption(value: 180, child: Text('180 days')),
                ShadOption(value: 365, child: Text('365 days')),
              ],
              onChanged: (days) {
                if (days != null) {
                  notifier.setAuditRetentionDays(days);
                }
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPanicCard(
    BuildContext context,
    WidgetRef ref,
    ShellVibeTokens tokens,
  ) {
    return ShadCard(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Cut all agent access',
              style: TextStyle(
                color: tokens.danger,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'Immediately closes every open agent session, revokes every '
              'host grant and remembered approval, revokes every client '
              'token across every workspace, and stops the server. There is '
              'no confirmation step — this button does not ask twice.',
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: tokens.textMuted),
            ),
            const SizedBox(height: 12),
            ShellVibeButton.danger(
              key: const Key('mcp_panic_button'),
              label: 'CUT ALL AGENT ACCESS',
              icon: LucideIcons.power,
              onPressed: () => ref.read(mcpSettingsProvider.notifier).panic(),
            ),
          ],
        ),
      ),
    );
  }

  /// Locates the `shellvibe-mcp` stdio bridge binary next to this running
  /// install, at runtime — never hard-coded. `docs/mcp_plan.md`'s "Köprü
  /// binary'sinin dağıtımı" section is explicit that the path differs by
  /// platform and by how the app itself was installed, so the only value
  /// that is ever actually correct is one derived from
  /// [Platform.resolvedExecutable] at the moment this screen renders:
  ///
  /// - **macOS**: the bridge ships inside the same `.app` bundle, next to
  ///   the main executable (`Contents/MacOS/`).
  /// - **Windows**: the bridge sits in the same install directory as the
  ///   main `.exe`.
  /// - **Linux**: the resolved executable's own directory covers a normal
  ///   install; a packaged build (e.g. AppImage) that cannot be invoked from
  ///   outside its mount additionally falls back to `~/.local/bin`, which
  ///   is where the plan says a from-inside-AppImage bridge gets installed
  ///   separately.
  ///
  /// See [mcpBridgeCandidates] for the Microsoft Store build.
  ///
  /// If nothing exists at any candidate path, a clearly-marked placeholder
  /// is returned instead of guessing — see [_BridgeCommand.isPlaceholder].
  _BridgeCommand _detectBridgeCommand() {
    final candidates = mcpBridgeCandidates(
      resolvedExecutable: Platform.resolvedExecutable,
      environment: Platform.environment,
      isWindows: Platform.isWindows,
      isLinux: Platform.isLinux,
      isWindowsStorePackage: isWindowsStorePackage,
    );

    for (final candidate in candidates) {
      if (File(candidate).existsSync()) {
        return _BridgeCommand(command: candidate, isPlaceholder: false);
      }
    }
    return const _BridgeCommand(
      command: '<shellvibe-mcp not found — locate it manually>',
      isPlaceholder: true,
    );
  }

  String _formatSeconds(int seconds) =>
      seconds < 60 ? '$seconds seconds' : '${seconds ~/ 60} minute(s)';

  String _formatMinutes(int minutes) =>
      minutes < 60 ? '$minutes minutes' : '${minutes ~/ 60} hour(s)';

  String _formatDays(int days) => '$days days';

  String _formatBytes(int bytes) {
    if (bytes >= 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(bytes % (1024 * 1024) == 0 ? 0 : 1)} MB';
    }
    return '${bytes ~/ 1024} KB';
  }
}

/// Marks AI Access as experimental, so a rough edge reads as known rather than
/// as a broken feature.
class _ExperimentalBanner extends StatelessWidget {
  const _ExperimentalBanner({required this.tokens});

  final ShellVibeTokens tokens;

  @override
  Widget build(BuildContext context) {
    return Container(
      key: const Key('mcp_experimental_banner'),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: tokens.warning.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(tokens.radiusSmall),
        border: Border.all(color: tokens.warning.withValues(alpha: 0.5)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(LucideIcons.flaskConical, size: 16, color: tokens.warning),
          const SizedBox(width: 8),
          Expanded(
            child: Text.rich(
              TextSpan(
                children: [
                  const TextSpan(
                    text: 'Experimental. ',
                    style: TextStyle(fontWeight: FontWeight.w600),
                  ),
                  TextSpan(
                    text:
                        'AI Access is still being developed. Tools, approvals '
                        'and behavior may change between releases, and some '
                        'agent workflows may not work reliably yet.',
                    style: TextStyle(color: tokens.textMuted),
                  ),
                ],
              ),
              style: const TextStyle(fontSize: 13),
            ),
          ),
        ],
      ),
    );
  }
}

/// One-click setup for the AI tools whose config file ShellVibe knows: each
/// row says whether that tool already points at this install's bridge and, if
/// not, writes it in.
class _AgentAppsCard extends StatefulWidget {
  const _AgentAppsCard({required this.bridge, required this.serverEnabled});

  final _BridgeCommand bridge;
  final bool serverEnabled;

  @override
  State<_AgentAppsCard> createState() => _AgentAppsCardState();
}

class _AgentAppsCardState extends State<_AgentAppsCard> {
  final Map<McpAgentApp, String> _paths = {
    for (final app in McpAgentApp.values)
      app: ?mcpAgentConfigPath(
        app,
        environment: Platform.environment,
        isWindows: Platform.isWindows,
        isMacOS: Platform.isMacOS,
      ),
  };
  final Map<McpAgentApp, McpAgentConfigStatus> _statuses = {};

  @override
  void initState() {
    super.initState();
    if (!widget.bridge.isPlaceholder) _refresh();
  }

  Future<void> _refresh() async {
    for (final MapEntry(key: app, value: path) in _paths.entries) {
      final status = await readMcpAgentConfigStatus(
        app,
        path,
        widget.bridge.command,
      );
      if (!mounted) return;
      setState(() => _statuses[app] = status);
    }
  }

  Future<void> _install(McpAgentApp app) async {
    try {
      await installMcpAgentServer(app, _paths[app]!, widget.bridge.command);
    } on Exception catch (e) {
      if (mounted) {
        ShadToaster.of(context).show(
          ShadToast.destructive(
            description: Text('Could not update ${app.label}\'s config: $e'),
          ),
        );
      }
      return;
    }
    await _refresh();
    if (!mounted) return;
    ShadToaster.of(context).show(
      ShadToast(
        description: Text(
          'Added ShellVibe to ${app.label}. Restart ${app.label} to load it.'
          '${widget.serverEnabled ? '' : ' Turn on "Allow AI agent access" too.'}',
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final tokens = ShellVibeTokens.resolve(context);
    return ShadCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 14, 16, 8),
            child: Text('Connect an AI tool'),
          ),
          const Divider(),
          if (widget.bridge.isPlaceholder)
            ListTile(
              leading: Icon(LucideIcons.circleAlert, color: tokens.warning),
              title: Text(
                'The shellvibe-mcp bridge could not be located next to this '
                'install, so there is nothing to point an AI tool at.'
                '${kDebugMode ? ' Run tool/build_bridge.sh after flutter run.' : ''}',
              ),
            )
          else ...[
            for (final MapEntry(key: app, value: path) in _paths.entries) ...[
              if (app != _paths.keys.first) const Divider(height: 1),
              ListTile(
                key: Key('mcp_agent_app_${app.name}'),
                title: Text(app.label),
                subtitle: Text(
                  path,
                  style: shellvibeMono(
                    context,
                    size: 11.5,
                    color: tokens.textMuted,
                  ),
                ),
                trailing: switch (_statuses[app]) {
                  null => null,
                  McpAgentConfigStatus.installed => const ShadBadge.secondary(
                    child: Text('Connected'),
                  ),
                  McpAgentConfigStatus.unreadable => Text(
                    'Edit by hand',
                    style: TextStyle(color: tokens.warning),
                  ),
                  McpAgentConfigStatus.outdated => ShellVibeButton.secondary(
                    key: Key('mcp_agent_app_update_${app.name}'),
                    label: 'Update',
                    onPressed: () => _install(app),
                  ),
                  McpAgentConfigStatus.missing => ShellVibeButton.secondary(
                    key: Key('mcp_agent_app_add_${app.name}'),
                    label: 'Add',
                    onPressed: () => _install(app),
                  ),
                },
              ),
            ],
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Manual'),
                  const SizedBox(height: 2),
                  Text(
                    'For any other MCP client, or a file marked "Edit by '
                    'hand", add this to its MCP config:',
                    style: Theme.of(
                      context,
                    ).textTheme.bodySmall?.copyWith(color: tokens.textMuted),
                  ),
                  const SizedBox(height: 8),
                  _CopyableBlock(
                    key: const Key('mcp_manual_config_json'),
                    text: const JsonEncoder.withIndent('  ').convert({
                      'mcpServers': {
                        'shellvibe': {'command': widget.bridge.command},
                      },
                    }),
                    tokens: tokens,
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Result of [McpAccessSettingsSection._detectBridgeCommand]: the command to
/// show the user, and whether it is a real detected path or a placeholder
/// that needs manual replacement.
class _BridgeCommand {
  final String command;
  final bool isPlaceholder;

  const _BridgeCommand({required this.command, required this.isPlaceholder});
}

/// A monospace, selectable block of text with a one-tap copy button — the
/// manual config under "Connect an AI tool".
class _CopyableBlock extends StatelessWidget {
  const _CopyableBlock({super.key, required this.text, required this.tokens});

  final String text;
  final ShellVibeTokens tokens;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: tokens.canvas,
        borderRadius: BorderRadius.circular(tokens.radiusSmall),
        border: Border.all(color: tokens.border),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: SelectableText(
              text,
              style: shellvibeMono(
                context,
                size: 11.5,
                color: tokens.textPrimary,
              ),
            ),
          ),
          const SizedBox(width: 8),
          ShellVibeIconButton(
            icon: LucideIcons.copy,
            tooltip: 'Copy',
            onPressed: () => Clipboard.setData(ClipboardData(text: text)),
          ),
        ],
      ),
    );
  }
}

/// Where the `shellvibe-mcp` bridge may be, most likely first.
///
/// The Microsoft Store build installs into a directory named after the package
/// version, so a client configured with that path breaks on the next Store
/// update. Its manifest declares an execution alias instead, which Windows
/// keeps at one path across updates; that is what a client is given.
@visibleForTesting
List<String> mcpBridgeCandidates({
  required String resolvedExecutable,
  required Map<String, String> environment,
  required bool isWindows,
  required bool isLinux,
  required bool isWindowsStorePackage,
}) {
  final bridgeName = isWindows ? 'shellvibe-mcp.exe' : 'shellvibe-mcp';
  final path = isWindows ? p.windows : p.posix;
  final candidates = <String>[];
  if (isWindowsStorePackage) {
    final localAppData = environment['LOCALAPPDATA'];
    if (localAppData != null && localAppData.isNotEmpty) {
      candidates.add(
        path.join(localAppData, 'Microsoft', 'WindowsApps', bridgeName),
      );
    }
  }
  candidates.add(path.join(path.dirname(resolvedExecutable), bridgeName));
  if (isLinux) {
    final home = environment['HOME'];
    if (home != null && home.isNotEmpty) {
      candidates.add(path.join(home, '.local', 'bin', bridgeName));
    }
  }
  return candidates;
}
