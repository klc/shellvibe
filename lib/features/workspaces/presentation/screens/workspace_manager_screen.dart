import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../../../../app/theme/shellvibe_tokens.dart';
import '../../../../app/widgets/adaptive_modal.dart';
import '../../../../app/widgets/shellvibe_ui.dart';
import '../../../../shared/database/models/workspace_usage.dart';
import '../../../../shared/providers/workspace_provider.dart';
import '../../domain/models/workspace_model.dart';
import '../dialogs/workspace_form_dialog.dart';
import '../notifiers/workspaces_notifier.dart';

class WorkspaceManagerScreen extends ConsumerWidget {
  const WorkspaceManagerScreen({super.key});

  void _openForm(BuildContext context, {WorkspaceModel? workspace}) {
    showDialog<bool>(
      context: context,
      builder: (_) => WorkspaceFormDialog(workspace: workspace),
    );
  }

  Future<void> _deleteWorkspace(
    BuildContext context,
    WidgetRef ref,
    WorkspaceModel workspace,
  ) async {
    if (workspace.id == 'default') return;

    final usage = await ref
        .read(workspaceManagerProvider.notifier)
        .getUsage(workspace.id);
    if (!context.mounted) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => ShadDialog.alert(
        title: Text('Delete ${workspace.name}?'),
        description: Text(
          'This permanently deletes the workspace and its ${_usageSummary(usage)}. '
          'This action cannot be undone.',
        ),
        actions: adaptiveDialogActions(context, [
          ShellVibeButton.secondary(
            label: 'Cancel',
            onPressed: () => Navigator.of(dialogContext).pop(false),
          ),
          ShellVibeButton.danger(
            key: const Key('workspace_confirm_delete_button'),
            label: 'Delete Workspace',
            onPressed: () => Navigator.of(dialogContext).pop(true),
          ),
        ]),
        actionsAxis: adaptiveDialogActionsAxis(context),
      ),
    );

    if (confirmed != true || !context.mounted) return;

    try {
      await ref.read(workspaceManagerProvider.notifier).delete(workspace.id);
      if (ref.read(activeWorkspaceIdProvider) == workspace.id) {
        await ref.read(activeWorkspaceIdProvider.notifier).select('default');
      }
      if (context.mounted) {
        ShadToaster.of(
          context,
        ).show(const ShadToast(description: Text('Workspace deleted.')));
      }
    } catch (error) {
      if (context.mounted) {
        ShadToaster.of(
          context,
        ).show(ShadToast.destructive(description: Text('$error')));
      }
    }
  }

  String _usageSummary(WorkspaceUsage usage) {
    final parts = <String>[];
    void add(int count, String label) {
      if (count > 0) parts.add('$count $label');
    }

    add(usage.hosts, usage.hosts == 1 ? 'host' : 'hosts');
    add(usage.groups, usage.groups == 1 ? 'group' : 'groups');
    add(usage.identities, usage.identities == 1 ? 'identity' : 'identities');
    add(usage.tunnels, usage.tunnels == 1 ? 'tunnel' : 'tunnels');
    add(usage.snippets, usage.snippets == 1 ? 'snippet' : 'snippets');
    add(usage.runbooks, usage.runbooks == 1 ? 'runbook' : 'runbooks');
    return parts.isEmpty ? 'no saved records' : parts.join(', ');
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = ShellVibeTokens.resolve(context);
    final workspacesAsync = ref.watch(workspacesProvider);
    final activeId = ref.watch(activeWorkspaceIdProvider);

    return Scaffold(
      body: Column(
        children: [
          ShellVibePageHeader(
            icon: LucideIcons.panelTop,
            title: 'Workspaces',
            description:
                'Organize hosts, credentials, tunnels and automation by context.',
            // Flexible, not a bare Text: a shadcn button shrink-wraps its
            // label, so at a large system text scale an unbounded one
            // overflows the button it sits in.
            actions: [
              ShellVibeButton(
                key: const Key('add_workspace_button'),
                label: 'Add Workspace',
                icon: LucideIcons.plus,
                onPressed: () => _openForm(context),
              ),
            ],
          ),
          Expanded(
            child: workspacesAsync.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (error, stack) => ShellVibeEmptyState(
                icon: LucideIcons.triangleAlert,
                title: 'Could not load workspaces',
                description: '$error',
                actions: [
                  ShellVibeButton.secondary(
                    label: 'Retry',
                    onPressed: () => ref.invalidate(workspacesProvider),
                  ),
                ],
              ),
              data: (workspaces) => ListView.separated(
                padding: EdgeInsets.fromLTRB(
                  tokens.pagePadding,
                  20,
                  tokens.pagePadding,
                  32,
                ),
                itemCount: workspaces.length,
                separatorBuilder: (_, _) => const SizedBox(height: 10),
                itemBuilder: (context, index) {
                  final workspace = workspaces[index];
                  final isActive = workspace.id == activeId;
                  final isDefault = workspace.id == 'default';

                  return ShellVibeSurface(
                    key: ValueKey('workspace_card_${workspace.id}'),
                    raised: isActive,
                    padding: const EdgeInsets.fromLTRB(16, 14, 8, 14),
                    child: Row(
                      children: [
                        Container(
                          width: 38,
                          height: 38,
                          decoration: BoxDecoration(
                            color: isActive
                                ? tokens.brand.withValues(alpha: 0.14)
                                : tokens.surfaceRaised,
                            borderRadius: BorderRadius.circular(
                              tokens.radiusMedium,
                            ),
                          ),
                          child: Icon(
                            isDefault
                                ? LucideIcons.house
                                : LucideIcons.panelTop,
                            size: 18,
                            color: isActive ? tokens.brand : tokens.textMuted,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Flexible(
                                    child: Text(
                                      workspace.name,
                                      overflow: TextOverflow.ellipsis,
                                      style: Theme.of(context)
                                          .textTheme
                                          .titleMedium
                                          ?.copyWith(
                                            fontWeight: FontWeight.w600,
                                          ),
                                    ),
                                  ),
                                  if (isActive) ...[
                                    const SizedBox(width: 8),
                                    const ShellVibeStatusChip(
                                      label: 'Active',
                                      icon: LucideIcons.check,
                                      tone: ShellVibeStatusTone.success,
                                    ),
                                  ],
                                ],
                              ),
                              const SizedBox(height: 4),
                              Text(
                                isDefault
                                    ? 'Protected default workspace'
                                    : 'Workspace for an independent operating context',
                                style: Theme.of(context).textTheme.bodySmall
                                    ?.copyWith(color: tokens.textMuted),
                              ),
                            ],
                          ),
                        ),
                        if (!isActive)
                          ShellVibeIconButton(
                            key: Key('workspace_select_${workspace.id}'),
                            icon: LucideIcons.radio,
                            tooltip: 'Use workspace',
                            onPressed: () => ref
                                .read(activeWorkspaceIdProvider.notifier)
                                .select(workspace.id),
                          ),
                        ShellVibeIconButton(
                          key: Key('workspace_edit_${workspace.id}'),
                          icon: LucideIcons.pencil,
                          tooltip: 'Rename workspace',
                          onPressed: () =>
                              _openForm(context, workspace: workspace),
                        ),
                        ShellVibeIconButton(
                          key: Key('workspace_delete_${workspace.id}'),
                          icon: LucideIcons.trash2,
                          tooltip: isDefault
                              ? 'Default Workspace cannot be deleted'
                              : 'Delete workspace',
                          onPressed: isDefault
                              ? null
                              : () => _deleteWorkspace(context, ref, workspace),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }
}
