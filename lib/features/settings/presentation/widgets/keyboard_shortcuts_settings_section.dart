import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../../../../app/keyboard/app_keymap.dart';
import '../../../../app/theme/shellvibe_tokens.dart';
import '../../../../app/widgets/shellvibe_ui.dart';
import '../../../../core/utils/platform_capabilities.dart';

/// Every shortcut, as this platform's keyboard writes it.
///
/// Read-only: the list is generated from the same keymap the bindings are, so
/// it cannot advertise a chord that does nothing, and a binding cannot change
/// without the list changing with it.
class KeyboardShortcutsSettingsSection extends StatelessWidget {
  const KeyboardShortcutsSettingsSection({super.key});

  @override
  Widget build(BuildContext context) {
    final tokens = ShellVibeTokens.resolve(context);
    final groups = shortcutReference(includeLocalTab: supportsLocalShell);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // The one rule worth knowing, since it is what makes a key that works
        // on the Hosts screen do something else inside a terminal.
        if (!usesCommandKey())
          const Padding(
            padding: EdgeInsets.only(bottom: 4),
            child: ShellVibeInfoNote(
              message:
                  'Inside a terminal, plain Ctrl keys belong to the program '
                  'running there (Ctrl+K, Ctrl+W, Ctrl+T…). App shortcuts '
                  'add Shift, so they work everywhere.',
              icon: LucideIcons.keyboard,
            ),
          ),
        for (final (group, rows) in groups)
          if (rows.isNotEmpty) ...[
            ShellVibeSectionLabel(label: group),
            ShadCard(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
              child: Column(
                children: [
                  for (final (index, row) in rows.indexed) ...[
                    if (index > 0) Divider(height: 1, color: tokens.border),
                    _ShortcutRow(entry: row),
                  ],
                ],
              ),
            ),
          ],
      ],
    );
  }
}

class _ShortcutRow extends StatelessWidget {
  final ShortcutReferenceEntry entry;

  const _ShortcutRow({required this.entry});

  @override
  Widget build(BuildContext context) {
    final tokens = ShellVibeTokens.resolve(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        children: [
          Expanded(
            child: Text(
              entry.label,
              style: TextStyle(fontSize: 13, color: tokens.textPrimary),
            ),
          ),
          const SizedBox(width: 12),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: tokens.textPrimary.withValues(alpha: 0.06),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(
              entry.keys,
              style: shellvibeMono(
                context,
                size: 11.5,
                color: tokens.textSecondary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
