import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../../shared/providers/workspace_provider.dart';
import '../theme/shellvibe_tokens.dart';

/// Sentinel value routing to the workspace manager instead of selecting one.
const kManageWorkspacesMenuValue = '__manage_workspaces__';

/// The `ws-switch` control from the wireframe's context column head.
///
/// It lives inside the module column rather than a global header, so the
/// skeleton stays rail → context → work with nothing above it.
class ShellVibeWorkspaceSwitcher extends ConsumerWidget {
  /// Drops the `WORKSPACE` caption so the control fits a mobile title bar.
  final bool compact;
  final VoidCallback onManageWorkspaces;

  const ShellVibeWorkspaceSwitcher({
    super.key,
    this.compact = false,
    required this.onManageWorkspaces,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = ShellVibeTokens.resolve(context);
    final activeWorkspaceId = ref.watch(activeWorkspaceIdProvider);
    final workspacesAsync = ref.watch(workspacesProvider);

    return Container(
      key: const Key('workspace_selector_dropdown'),
      // Compact lives in a Wrap inside the mobile title bar, which offers
      // unbounded width — the dropdown needs an explicit one.
      width: compact ? 170 : null,
      height: compact ? tokens.controlHeight : 42,
      padding: const EdgeInsets.only(left: 10, right: 4),
      decoration: BoxDecoration(
        color: tokens.surfaceRaised,
        borderRadius: BorderRadius.circular(tokens.radiusMedium),
        border: Border.all(color: tokens.border),
      ),
      child: workspacesAsync.when(
        loading: () => const Center(
          child: SizedBox(
            width: 14,
            height: 14,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        ),
        error: (_, _) => Align(
          alignment: Alignment.centerLeft,
          child: Text(
            'Workspace unavailable',
            style: Theme.of(
              context,
            ).textTheme.labelSmall?.copyWith(color: tokens.danger),
          ),
        ),
        data: (items) {
          final selectedId =
              items.any((workspace) => workspace.id == activeWorkspaceId)
              ? activeWorkspaceId
              : items.firstOrNull?.id;
          if (selectedId == null) return const SizedBox.shrink();

          return Row(
            children: [
              if (!compact) ...[
                Text(
                  'WORKSPACE',
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    fontSize: 9,
                    letterSpacing: 0.8,
                    color: tokens.textMuted,
                  ),
                ),
                const SizedBox(width: 8),
              ],
              Expanded(
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<String>(
                    value: selectedId,
                    isDense: true,
                    isExpanded: true,
                    dropdownColor: tokens.surfaceRaised,
                    icon: Icon(
                      LucideIcons.chevronsUpDown,
                      size: 13,
                      color: tokens.textMuted,
                    ),
                    style: Theme.of(context).textTheme.labelMedium?.copyWith(
                      color: tokens.textPrimary,
                    ),
                    onChanged: (value) {
                      if (value == kManageWorkspacesMenuValue) {
                        onManageWorkspaces();
                      } else if (value != null) {
                        ref
                            .read(activeWorkspaceIdProvider.notifier)
                            .select(value);
                      }
                    },
                    items: [
                      ...items.map(
                        (workspace) => DropdownMenuItem<String>(
                          value: workspace.id,
                          child: Text(
                            workspace.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ),
                      const DropdownMenuItem<String>(
                        value: kManageWorkspacesMenuValue,
                        child: Text('Manage Workspaces…'),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
