import 'dart:convert';
import 'dart:io' show File, Platform;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:shadcn_ui/shadcn_ui.dart';

import '../../../../app/theme/shellvibe_tokens.dart';
import '../../../../app/widgets/adaptive_modal.dart';
import '../../../../app/widgets/shellvibe_ui.dart';
import '../../../../shared/database/app_database.dart';
import '../../data/mcp_server_controller.dart';
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
        _buildClientsCard(context, ref, tokens, settings),
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
                'Starts a localhost-only MCP server this workspace\'s '
                'registered clients can connect to.',
              ),
              value: settings.masterEnabled,
              onChanged: (value) => ref
                  .read(mcpSettingsProvider.notifier)
                  .setMasterEnabled(value),
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

  Widget _buildClientsCard(
    BuildContext context,
    WidgetRef ref,
    ShellVibeTokens tokens,
    McpSettingsState settings,
  ) {
    return ShadCard(
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 8, 8),
            child: Row(
              children: [
                const Expanded(
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Text('Clients'),
                  ),
                ),
                ShellVibeButton.secondary(
                  key: const Key('mcp_add_client_button'),
                  label: 'Add client',
                  icon: LucideIcons.plus,
                  onPressed: () => _showAddClientFlow(context, ref),
                ),
              ],
            ),
          ),
          const Divider(),
          // The server mints its own client row on every start for the stdio
          // bridge to authenticate with. It is infrastructure, not something
          // the user registered, and it is replaced on every restart — so it
          // is kept out of this list entirely. Showing it would invite
          // revoking it, which kills the bridge while `mcp-endpoint.json`
          // still points at its now-dead token, and every agent request
          // fails with an unexplained "token is invalid".
          if (_userClients(settings).isEmpty)
            const ListTile(
              key: Key('mcp_clients_empty'),
              leading: Icon(LucideIcons.bot),
              title: Text('No clients registered for this workspace yet.'),
            )
          else
            for (final client in _userClients(settings)) ...[
              if (client != _userClients(settings).first)
                const Divider(height: 1),
              _buildClientRow(context, ref, tokens, client),
            ],
        ],
      ),
    );
  }

  /// The clients the user actually registered.
  ///
  /// Excludes [McpServerController.systemClientName] — see the comment at the
  /// call site for why that row must never be presented as revocable.
  List<McpClient> _userClients(McpSettingsState settings) => settings.clients
      .where((c) => c.name != McpServerController.systemClientName)
      .toList(growable: false);

  Widget _buildClientRow(
    BuildContext context,
    WidgetRef ref,
    ShellVibeTokens tokens,
    McpClient client,
  ) {
    final revoked = client.revokedAt != null;
    return ListTile(
      key: Key('mcp_client_${client.id}'),
      leading: Icon(
        LucideIcons.bot,
        color: revoked ? tokens.textSubtle : tokens.brand,
      ),
      title: Text(
        client.name,
        style: revoked ? TextStyle(color: tokens.textSubtle) : null,
      ),
      subtitle: Text(
        'created ${_formatDate(client.createdAt)} · '
        'last seen ${_formatDateOrNever(client.lastSeenAt)} · '
        'expires ${_formatDateOrNever(client.expiresAt)}',
        style: Theme.of(
          context,
        ).textTheme.bodySmall?.copyWith(color: tokens.textMuted),
      ),
      trailing: revoked
          ? const ShadBadge.secondary(child: Text('Revoked'))
          : ShellVibeButton.danger(
              key: Key('mcp_revoke_client_${client.id}'),
              label: 'Revoke',
              onPressed: () => ref
                  .read(mcpSettingsProvider.notifier)
                  .revokeClient(client.id),
            ),
    );
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
          crossAxisAlignment: CrossAxisAlignment.stretch,
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

  Future<void> _showAddClientFlow(BuildContext context, WidgetRef ref) async {
    final nameController = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (dialogContext) => ShadDialog.alert(
        title: const Text('Add Client'),
        description: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Name this client the way you\'ll recognize it later, e.g. '
              '"Claude Desktop" or "Claude Code — laptop".',
            ),
            const SizedBox(height: 12),
            ShadInput(
              key: const Key('mcp_add_client_name_field'),
              controller: nameController,
              placeholder: const Text('Client name'),
              autofocus: true,
            ),
          ],
        ),
        actions: adaptiveDialogActions(context, [
          ShellVibeButton.secondary(
            key: const Key('mcp_add_client_cancel_button'),
            label: 'Cancel',
            onPressed: () => Navigator.of(dialogContext).pop(),
          ),
          ShellVibeButton(
            key: const Key('mcp_add_client_create_button'),
            label: 'Create',
            onPressed: () =>
                Navigator.of(dialogContext).pop(nameController.text.trim()),
          ),
        ]),
        actionsAxis: adaptiveDialogActionsAxis(context),
      ),
    );
    nameController.dispose();

    if (name == null || name.isEmpty || !context.mounted) return;

    final String rawToken;
    try {
      rawToken = await ref.read(mcpSettingsProvider.notifier).addClient(name);
    } catch (e) {
      if (context.mounted) {
        ShadToaster.of(context).show(
          ShadToast.destructive(
            description: Text('Could not create client: $e'),
          ),
        );
      }
      return;
    }

    if (!context.mounted) return;
    await _showTokenRevealDialog(context, rawToken);
  }

  Future<void> _showTokenRevealDialog(
    BuildContext context,
    String rawToken,
  ) async {
    final bridge = _detectBridgeCommand();
    final configJson = _buildClientConfigJson(bridge.command);

    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        final tokens = ShellVibeTokens.resolve(dialogContext);
        return ShadDialog.alert(
          title: const Text('Client Created'),
          description: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'This token is shown once and cannot be retrieved again. '
                'Copy it now — if it\'s lost, revoke this client and add a '
                'new one.',
                style: Theme.of(
                  dialogContext,
                ).textTheme.bodySmall?.copyWith(color: tokens.danger),
              ),
              const SizedBox(height: 10),
              _CopyableBlock(
                key: const Key('mcp_new_client_token'),
                text: rawToken,
                tokens: tokens,
              ),
              const SizedBox(height: 16),
              Text(
                'Paste this into the MCP client\'s config:',
                style: Theme.of(dialogContext).textTheme.bodySmall,
              ),
              if (bridge.isPlaceholder) ...[
                const SizedBox(height: 6),
                Text(
                  'The shellvibe-mcp bridge binary could not be located '
                  'next to this install. Replace the placeholder below with '
                  'its actual path.',
                  style: Theme.of(
                    dialogContext,
                  ).textTheme.bodySmall?.copyWith(color: tokens.warning),
                ),
              ],
              const SizedBox(height: 8),
              _CopyableBlock(
                key: const Key('mcp_new_client_config_json'),
                text: configJson,
                tokens: tokens,
                maxLines: 6,
              ),
            ],
          ),
          actions: adaptiveDialogActions(context, [
            ShellVibeButton(
              key: const Key('mcp_token_reveal_done_button'),
              label: 'Done',
              onPressed: () => Navigator.of(dialogContext).pop(),
            ),
          ]),
          actionsAxis: adaptiveDialogActionsAxis(context),
        );
      },
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
  /// If nothing exists at any candidate path, a clearly-marked placeholder
  /// is returned instead of guessing — see [_BridgeCommand.isPlaceholder].
  _BridgeCommand _detectBridgeCommand() {
    final bridgeName = Platform.isWindows
        ? 'shellvibe-mcp.exe'
        : 'shellvibe-mcp';
    final candidates = <String>[
      p.join(p.dirname(Platform.resolvedExecutable), bridgeName),
    ];
    if (Platform.isLinux) {
      final home = Platform.environment['HOME'];
      if (home != null && home.isNotEmpty) {
        candidates.add(p.join(home, '.local', 'bin', bridgeName));
      }
    }

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

  String _buildClientConfigJson(String command) {
    const encoder = JsonEncoder.withIndent('  ');
    return encoder.convert({
      'mcpServers': {
        'shellvibe': {'command': command},
      },
    });
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

  String _formatDate(DateTime date) {
    final local = date.toLocal();
    return '${local.year}-${local.month.toString().padLeft(2, '0')}-'
        '${local.day.toString().padLeft(2, '0')}';
  }

  String _formatDateOrNever(DateTime? date) =>
      date == null ? 'never' : _formatDate(date);
}

/// Result of [McpAccessSettingsSection._detectBridgeCommand]: the command to
/// show the user, and whether it is a real detected path or a placeholder
/// that needs manual replacement.
class _BridgeCommand {
  final String command;
  final bool isPlaceholder;

  const _BridgeCommand({required this.command, required this.isPlaceholder});
}

/// A monospace, selectable block of text with a one-tap copy button — used
/// for both the one-time token and the client config JSON in the "Add
/// client" reveal dialog.
class _CopyableBlock extends StatelessWidget {
  const _CopyableBlock({
    super.key,
    required this.text,
    required this.tokens,
    this.maxLines,
  });

  final String text;
  final ShellVibeTokens tokens;
  final int? maxLines;

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
              maxLines: maxLines,
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
