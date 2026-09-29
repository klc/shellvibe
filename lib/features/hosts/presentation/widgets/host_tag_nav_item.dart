import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../../../../app/theme/shellvibe_tokens.dart';
import '../../../../app/widgets/shellvibe_ui.dart';
import '../../domain/models/host_group_model.dart';

/// Context-column entry for a host tag.
///
/// A plain [ShellVibeNavItem] filter with its own edit/delete menu beside it,
/// the way `TemplateNavItem` carries one: the column is where a tag is seen,
/// so it is also where it is renamed or removed.
class HostTagNavItem extends StatelessWidget {
  final HostGroupModel tag;
  final int count;
  final bool selected;
  final VoidCallback onSelect;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  const HostTagNavItem({
    super.key,
    required this.tag,
    required this.count,
    required this.selected,
    required this.onSelect,
    required this.onEdit,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final tokens = ShellVibeTokens.resolve(context);
    return Row(
      children: [
        Expanded(
          child: ShellVibeNavItem(
            itemKey: Key('group_${tag.id}'),
            icon: LucideIcons.hash,
            label: tag.name,
            count: count,
            selected: selected,
            onTap: onSelect,
          ),
        ),
        PopupMenuButton<String>(
          key: Key('tag_menu_${tag.id}'),
          tooltip: 'Tag actions',
          padding: EdgeInsets.zero,
          iconSize: 14,
          icon: const Icon(LucideIcons.ellipsis, size: 14),
          onSelected: (value) {
            if (value == 'edit') onEdit();
            if (value == 'delete') onDelete();
          },
          itemBuilder: (context) => [
            const PopupMenuItem(
              key: Key('tag_menu_edit'),
              value: 'edit',
              child: Row(
                children: [
                  Icon(LucideIcons.pencil, size: 16),
                  SizedBox(width: 8),
                  Text('Edit tag'),
                ],
              ),
            ),
            PopupMenuItem(
              key: const Key('tag_menu_delete'),
              value: 'delete',
              child: Row(
                children: [
                  Icon(LucideIcons.trash2, size: 16, color: tokens.danger),
                  const SizedBox(width: 8),
                  Text('Delete tag', style: TextStyle(color: tokens.danger)),
                ],
              ),
            ),
          ],
        ),
      ],
    );
  }
}
