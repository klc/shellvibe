import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import 'package:terly2/app/widgets/terly_ui.dart';
import '../../../../shared/providers/workspace_provider.dart';
import '../../../vault/data/vault_key_service.dart';
import '../../../vault/presentation/notifiers/vault_notifier.dart';
import '../../data/services/ssh_config_import_service.dart';
import '../../domain/models/ssh_config_models.dart';
import '../notifiers/host_groups_notifier.dart';
import '../providers/ssh_config_import_provider.dart';

/// Preview-and-confirm dialog for importing an OpenSSH `~/.ssh/config` file.
///
/// Resolves the file through [SshConfigImportService.previewConfig], lets the
/// user pick hosts, target group, conflict policy and which extras to import
/// (private keys, port forwards, missing jump hosts), then runs the import
/// and pops with the [SshConfigImportResult].
class SshConfigImportDialog extends ConsumerStatefulWidget {
  final String filePath;
  final String content;

  const SshConfigImportDialog({
    super.key,
    required this.filePath,
    required this.content,
  });

  @override
  ConsumerState<SshConfigImportDialog> createState() =>
      _SshConfigImportDialogState();
}

class _SshConfigImportDialogState extends ConsumerState<SshConfigImportDialog> {
  late final Future<SshConfigResolution> _resolutionFuture;
  final Set<String> _selectedAliases = {};
  String? _selectedGroupId;
  SshConfigConflictPolicy _conflictPolicy = SshConfigConflictPolicy.skip;
  bool _importKeys = true;
  bool _importTunnels = true;
  bool _createJumpHosts = true;
  bool _importing = false;

  @override
  void initState() {
    super.initState();
    // Select every discovered host by default. This needs a setState, not
    // just the FutureBuilder rebuild: the Import button lives in
    // ShadDialog.actions, outside the FutureBuilder subtree, and reads
    // _selectedAliases to decide whether it is enabled.
    _resolutionFuture = ref
        .read(sshConfigImportServiceProvider)
        .previewConfig(path: widget.filePath, content: widget.content)
        .then((resolution) {
          if (mounted) {
            setState(() {
              _selectedAliases
                ..clear()
                ..addAll(resolution.hosts.map((h) => h.alias));
            });
          }
          return resolution;
        });
  }

  Future<void> _runImport() async {
    setState(() => _importing = true);
    final vaultLocked =
        ref.read(vaultProvider).value?.status == VaultStatus.locked;
    final String? workspaceId;
    try {
      workspaceId = ref.read(activeWorkspaceIdProvider);
    } catch (e) {
      if (mounted) {
        setState(() => _importing = false);
        ShadToaster.of(context).show(
          ShadToast.destructive(
            title: const Text('Import Failed'),
            description: Text('No active workspace: $e'),
          ),
        );
      }
      return;
    }
    try {
      final result = await ref
          .read(sshConfigImportServiceProvider)
          .importConfig(
            path: widget.filePath,
            content: widget.content,
            options: SshConfigImportOptions(
              workspaceId: workspaceId!,
              groupId: _selectedGroupId,
              conflictPolicy: _conflictPolicy,
              importIdentityFiles: _importKeys && !vaultLocked,
              importTunnels: _importTunnels,
              createMissingJumpHosts: _createJumpHosts,
              onlyAliases: Set.of(_selectedAliases),
            ),
          );
      if (mounted) Navigator.of(context).pop(result);
    } on VaultLockedException {
      if (mounted) {
        setState(() => _importing = false);
        ShadToaster.of(context).show(
          ShadToast.destructive(
            title: const Text('Vault Locked'),
            description: const Text(
              'Unlock the vault to import private keys, or disable '
              '"Import private keys".',
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _importing = false);
        ShadToaster.of(context).show(
          ShadToast.destructive(
            title: const Text('Import Failed'),
            description: Text('$e'),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final groupsAsync = ref.watch(hostGroupsProvider);
    final vaultAsync = ref.watch(vaultProvider);
    final vaultLocked = vaultAsync.value?.status == VaultStatus.locked;

    return ShadDialog(
      title: Row(
        children: [
          const Icon(LucideIcons.fileInput, size: 20),
          const SizedBox(width: 8),
          const Text('Import SSH Config'),
        ],
      ),
      description: Text(widget.filePath),
      actions: [
        ShadButton.outline(
          onPressed: _importing ? null : () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        ShadButton(
          key: const Key('ssh_config_import_button'),
          onPressed: _importing || _selectedAliases.isEmpty ? null : _runImport,
          child: _importing
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Import'),
        ),
      ],
      child: SizedBox(
        width: 560,
        // Checkbox/Switch/InkWell need a Material ancestor; ShadDialog's
        // surface does not provide one.
        child: Material(
          type: MaterialType.transparency,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (_importing)
                const LinearProgressIndicator(minHeight: 2)
              else
                const SizedBox(height: 2),
              FutureBuilder<SshConfigResolution>(
                future: _resolutionFuture,
                builder: (context, snapshot) {
                  if (snapshot.connectionState != ConnectionState.done) {
                    return const Padding(
                      padding: EdgeInsets.all(32),
                      child: Center(
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    );
                  }
                  if (snapshot.hasError) {
                    return Padding(
                      padding: const EdgeInsets.all(16),
                      child: Text(
                        'Failed to parse the config file:\n${snapshot.error}',
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.error,
                        ),
                      ),
                    );
                  }
                  final resolution = snapshot.data!;
                  if (resolution.hosts.isEmpty) {
                    return Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(LucideIcons.searchX, size: 32),
                          const SizedBox(height: 8),
                          const Text(
                            'No importable hosts found in this config file.',
                          ),
                          if (resolution.warnings.isNotEmpty) ...[
                            const SizedBox(height: 8),
                            _WarningPanel(warnings: resolution.warnings),
                          ],
                        ],
                      ),
                    );
                  }
                  return SingleChildScrollView(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _HostChecklist(
                          resolution: resolution,
                          selected: _selectedAliases,
                          onToggle: (alias, selected) {
                            setState(() {
                              if (selected) {
                                _selectedAliases.add(alias);
                              } else {
                                _selectedAliases.remove(alias);
                              }
                            });
                          },
                        ),
                        const SizedBox(height: 16),
                        const TerlyFormSectionHeader(
                          icon: LucideIcons.slidersHorizontal,
                          title: 'Import Options',
                        ),
                        const SizedBox(height: 12),
                        groupsAsync.when(
                          data: (groups) => ShadSelectFormField<String?>(
                            key: const Key('import_group_dropdown'),
                            initialValue: _selectedGroupId,
                            label: const Text('Target Group'),
                            selectedOptionBuilder: (context, value) =>
                                Text(value ?? '(None - Ungrouped)'),
                            options: [
                              const ShadOption<String?>(
                                value: null,
                                child: Text('(None - Ungrouped)'),
                              ),
                              ...groups.map(
                                (g) => ShadOption<String?>(
                                  value: g.id,
                                  child: Text(g.name),
                                ),
                              ),
                            ],
                            onChanged: (val) =>
                                setState(() => _selectedGroupId = val),
                          ),
                          loading: () => const LinearProgressIndicator(),
                          error: (e, s) => const Text('Failed to load groups'),
                        ),
                        const SizedBox(height: 12),
                        ShadSelectFormField<SshConfigConflictPolicy>(
                          key: const Key('import_conflict_dropdown'),
                          initialValue: _conflictPolicy,
                          label: const Text('When a host name already exists'),
                          selectedOptionBuilder: (context, value) =>
                              Text(_conflictLabel(value)),
                          options: [
                            for (final policy in SshConfigConflictPolicy.values)
                              ShadOption(
                                value: policy,
                                child: Text(_conflictLabel(policy)),
                              ),
                          ],
                          onChanged: (val) {
                            if (val != null) {
                              setState(() => _conflictPolicy = val);
                            }
                          },
                        ),
                        const SizedBox(height: 8),
                        _ToggleRow(
                          key: const Key('import_keys_toggle'),
                          icon: LucideIcons.keyRound,
                          title: 'Import private keys into the vault',
                          subtitle: vaultLocked
                              ? 'Vault is locked — unlock it to enable.'
                              : null,
                          value: _importKeys && !vaultLocked,
                          onChanged: vaultLocked
                              ? null
                              : (v) => setState(() => _importKeys = v),
                        ),
                        _ToggleRow(
                          key: const Key('import_tunnels_toggle'),
                          icon: LucideIcons.arrowLeftRight,
                          title: 'Import port forwarding rules',
                          value: _importTunnels,
                          onChanged: (v) => setState(() => _importTunnels = v),
                        ),
                        _ToggleRow(
                          key: const Key('import_jumps_toggle'),
                          icon: LucideIcons.network,
                          title: 'Create missing jump hosts',
                          value: _createJumpHosts,
                          onChanged: (v) =>
                              setState(() => _createJumpHosts = v),
                        ),
                        if (resolution.warnings.isNotEmpty) ...[
                          const SizedBox(height: 8),
                          _WarningPanel(warnings: resolution.warnings),
                        ],
                      ],
                    ),
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _conflictLabel(SshConfigConflictPolicy policy) {
    switch (policy) {
      case SshConfigConflictPolicy.skip:
        return 'Skip existing';
      case SshConfigConflictPolicy.overwrite:
        return 'Overwrite existing';
      case SshConfigConflictPolicy.duplicate:
        return 'Import as copy (2)';
    }
  }
}

/// Checkbox list of discovered hosts with their connection summary.
class _HostChecklist extends StatelessWidget {
  final SshConfigResolution resolution;
  final Set<String> selected;
  final void Function(String alias, bool selected) onToggle;

  const _HostChecklist({
    required this.resolution,
    required this.selected,
    required this.onToggle,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hosts = resolution.hosts;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '${selected.length} of ${hosts.length} hosts selected',
          style: theme.textTheme.labelMedium?.copyWith(
            color: theme.colorScheme.primary,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 8),
        ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: 240),
          child: Container(
            decoration: BoxDecoration(
              border: Border.all(color: theme.colorScheme.outlineVariant),
              borderRadius: BorderRadius.circular(8),
            ),
            child: ListView.builder(
              shrinkWrap: true,
              itemCount: hosts.length,
              itemBuilder: (context, index) {
                final host = hosts[index];
                final isSelected = selected.contains(host.alias);
                return InkWell(
                  key: Key('import_host_${host.alias}'),
                  onTap: () => onToggle(host.alias, !isSelected),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 6,
                    ),
                    child: Row(
                      children: [
                        Checkbox(
                          value: isSelected,
                          onChanged: (v) => onToggle(host.alias, v ?? false),
                        ),
                        const SizedBox(width: 4),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                host.alias,
                                style: theme.textTheme.bodyMedium?.copyWith(
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              Text(
                                _hostSummary(host),
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: theme.colorScheme.outline,
                                ),
                              ),
                            ],
                          ),
                        ),
                        ..._badges(host, theme),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ),
      ],
    );
  }

  String _hostSummary(ResolvedSshConfig host) {
    final user = host.username == null ? '' : '${host.username}@';
    return '$user${host.hostname}:${host.port}';
  }

  List<Widget> _badges(ResolvedSshConfig host, ThemeData theme) {
    final badges = <Widget>[];
    if (host.identityFiles.isNotEmpty) {
      badges.add(_Badge(icon: LucideIcons.keyRound, label: 'key'));
    }
    if (host.jumpHost != null) {
      badges.add(_Badge(icon: LucideIcons.network, label: 'jump'));
    }
    if (host.forwards.isNotEmpty) {
      badges.add(
        _Badge(
          icon: LucideIcons.arrowLeftRight,
          label: '${host.forwards.length}',
        ),
      );
    }
    return badges;
  }
}

class _Badge extends StatelessWidget {
  final IconData icon;
  final String label;

  const _Badge({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      margin: const EdgeInsets.only(left: 4),
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 11, color: theme.colorScheme.outline),
          const SizedBox(width: 3),
          Text(
            label,
            style: theme.textTheme.labelSmall?.copyWith(
              color: theme.colorScheme.outline,
            ),
          ),
        ],
      ),
    );
  }
}

class _ToggleRow extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? subtitle;
  final bool value;
  final ValueChanged<bool>? onChanged;

  const _ToggleRow({
    super.key,
    required this.icon,
    required this.title,
    this.subtitle,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Icon(icon, size: 15, color: theme.colorScheme.outline),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: theme.textTheme.bodyMedium),
                if (subtitle != null)
                  Text(
                    subtitle!,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.outline,
                    ),
                  ),
              ],
            ),
          ),
          Switch(value: value, onChanged: onChanged),
        ],
      ),
    );
  }
}

/// Collapsible list of parse/resolve warnings.
class _WarningPanel extends StatelessWidget {
  final List<SshConfigWarning> warnings;

  const _WarningPanel({required this.warnings});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final errors = warnings
        .where((w) => w.severity == SshConfigWarningSeverity.error)
        .length;
    return Container(
      decoration: BoxDecoration(
        border: Border.all(color: theme.colorScheme.outlineVariant),
        borderRadius: BorderRadius.circular(8),
      ),
      child: ExpansionTile(
        tilePadding: const EdgeInsets.symmetric(horizontal: 12),
        leading: Icon(
          errors > 0 ? LucideIcons.triangleAlert : LucideIcons.info,
          size: 16,
          color: errors > 0
              ? theme.colorScheme.error
              : theme.colorScheme.outline,
        ),
        title: Text(
          '${warnings.length} note${warnings.length == 1 ? '' : 's'}',
          style: theme.textTheme.labelMedium,
        ),
        children: [
          for (final warning in warnings)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 2, 12, 6),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    warning.location.isEmpty ? '' : '${warning.location}: ',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.outline,
                    ),
                  ),
                  Expanded(
                    child: Text(
                      warning.message,
                      style: theme.textTheme.bodySmall,
                    ),
                  ),
                ],
              ),
            ),
          const SizedBox(height: 6),
        ],
      ),
    );
  }
}
