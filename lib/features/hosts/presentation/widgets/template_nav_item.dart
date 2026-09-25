import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../../../../app/theme/shellvibe_tokens.dart';
import '../../../../app/widgets/shellvibe_ui.dart';
import '../../../templates/domain/models/template_model.dart';

/// Context-column entry for a saved layout.
///
/// Shaped like [ShellVibeNavItem] so it reads as part of the column, but it runs an
/// action rather than selecting a filter, and carries its own edit/delete
/// menu.
class TemplateNavItem extends StatelessWidget {
  final TemplateModel template;
  final VoidCallback onRun;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  const TemplateNavItem({
    super.key,
    required this.template,
    required this.onRun,
    required this.onEdit,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final tokens = ShellVibeTokens.resolve(context);
    return Semantics(
      button: true,
      label: 'Run template ${template.name}, ${templateSummary(template)}',
      child: Row(
        children: [
          Expanded(
            child: InkWell(
              key: Key('run_template_${template.id}'),
              onTap: onRun,
              borderRadius: BorderRadius.circular(tokens.radiusSmall),
              child: Container(
                height: 30,
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: Row(
                  children: [
                    Icon(
                      LucideIcons.layoutTemplate,
                      size: 15,
                      color: tokens.textMuted,
                    ),
                    const SizedBox(width: 9),
                    Expanded(
                      child: Text(
                        template.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.labelMedium
                            ?.copyWith(color: tokens.textMuted),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          PopupMenuButton<String>(
            key: Key('template_menu_${template.id}'),
            tooltip: 'Template actions',
            padding: EdgeInsets.zero,
            iconSize: 14,
            icon: const Icon(LucideIcons.ellipsis, size: 14),
            onSelected: (value) {
              if (value == 'edit') onEdit();
              if (value == 'delete') onDelete();
            },
            itemBuilder: (context) => [
              // Name, description and every pane: one place to look at what a
              // template opens and to change it.
              const PopupMenuItem(
                value: 'edit',
                child: Row(
                  children: [
                    Icon(LucideIcons.pencil, size: 16),
                    SizedBox(width: 8),
                    Flexible(
                      child: Text(
                        'View & edit template',
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
              PopupMenuItem(
                value: 'delete',
                child: Row(
                  children: [
                    Icon(LucideIcons.trash2, size: 16, color: tokens.danger),
                    const SizedBox(width: 8),
                    Text(
                      'Delete template',
                      style: TextStyle(color: tokens.danger),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
