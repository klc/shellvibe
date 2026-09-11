import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../../app/theme/shellvibe_tokens.dart';
import '../../../../app/widgets/shellvibe_ui.dart';

/// The find bar that floats over the top-right of a terminal pane.
///
/// It is an overlay rather than a row in the pane's column on purpose: taking
/// height away from the terminal would resize the PTY, and a remote program
/// redrawing itself because someone opened a find bar is a worse outcome than
/// covering three rows of scrollback.
class TerminalSearchBar extends StatelessWidget {
  const TerminalSearchBar({
    super.key,
    required this.controller,
    required this.focusNode,
    required this.matchCount,
    required this.currentMatch,
    required this.caseSensitive,
    required this.onQueryChanged,
    required this.onNext,
    required this.onPrevious,
    required this.onToggleCaseSensitive,
    required this.onClose,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final int matchCount;

  /// 0-based index of the highlighted match, or -1 when there is none.
  final int currentMatch;
  final bool caseSensitive;
  final ValueChanged<String> onQueryChanged;
  final VoidCallback onNext;
  final VoidCallback onPrevious;
  final VoidCallback onToggleCaseSensitive;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final tokens = ShellVibeTokens.resolve(context);
    final hasQuery = controller.text.isNotEmpty;
    final noHits = hasQuery && matchCount == 0;

    return Container(
      height: 36,
      padding: const EdgeInsets.only(left: 10, right: 4),
      decoration: BoxDecoration(
        color: tokens.surfaceRaised,
        borderRadius: BorderRadius.circular(tokens.radiusMedium),
        border: Border.all(color: tokens.border),
        boxShadow: tokens.shadowOverlay,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(LucideIcons.search, size: 14, color: tokens.textMuted),
          const SizedBox(width: 8),
          SizedBox(
            width: 180,
            // Enter walks the hits, Shift+Enter walks them backwards and Esc
            // gives the keyboard back to the shell. The field has focus while
            // the bar is open, so the terminal never sees these keys and the
            // handling has to live here.
            child: Focus(
              onKeyEvent: (node, event) {
                if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
                  return KeyEventResult.ignored;
                }
                if (event.logicalKey == LogicalKeyboardKey.escape) {
                  onClose();
                  return KeyEventResult.handled;
                }
                if (event.logicalKey == LogicalKeyboardKey.enter ||
                    event.logicalKey == LogicalKeyboardKey.numpadEnter) {
                  HardwareKeyboard.instance.isShiftPressed
                      ? onPrevious()
                      : onNext();
                  return KeyEventResult.handled;
                }
                return KeyEventResult.ignored;
              },
              child: TextField(
                key: const Key('terminal_search_field'),
                controller: controller,
                focusNode: focusNode,
                autofocus: true,
                cursorColor: tokens.brand,
                style: shellvibeMono(
                  context,
                  size: 12,
                  color: noHits ? tokens.danger : tokens.textPrimary,
                ),
                decoration: InputDecoration(
                  isDense: true,
                  border: InputBorder.none,
                  contentPadding: EdgeInsets.zero,
                  hintText: 'Find in terminal',
                  hintStyle: shellvibeMono(
                    context,
                    size: 12,
                    color: tokens.textSubtle,
                  ),
                ),
                onChanged: onQueryChanged,
              ),
            ),
          ),
          const SizedBox(width: 8),
          // The counter keeps its slot whether or not there is a query, so the
          // bar does not resize under the pointer as someone types.
          SizedBox(
            width: 56,
            child: Text(
              switch ((hasQuery, matchCount)) {
                (false, _) => '',
                (true, 0) => 'no hits',
                _ => '${currentMatch + 1}/$matchCount',
              },
              textAlign: TextAlign.right,
              style: shellvibeMono(
                context,
                size: 11,
                color: noHits ? tokens.danger : tokens.textMuted,
              ),
            ),
          ),
          const SizedBox(width: 4),
          ShellVibeIconButton(
            buttonKey: const Key('terminal_search_case'),
            icon: LucideIcons.caseSensitive,
            tooltip: caseSensitive
                ? 'Case sensitive: on'
                : 'Case sensitive: off',
            active: caseSensitive,
            onPressed: onToggleCaseSensitive,
          ),
          ShellVibeIconButton(
            buttonKey: const Key('terminal_search_previous'),
            icon: LucideIcons.chevronUp,
            tooltip: 'Previous match (Shift+Enter)',
            onPressed: matchCount == 0 ? null : onPrevious,
          ),
          ShellVibeIconButton(
            buttonKey: const Key('terminal_search_next'),
            icon: LucideIcons.chevronDown,
            tooltip: 'Next match (Enter)',
            onPressed: matchCount == 0 ? null : onNext,
          ),
          ShellVibeIconButton(
            buttonKey: const Key('terminal_search_close'),
            icon: LucideIcons.x,
            tooltip: 'Close (Esc)',
            onPressed: onClose,
          ),
        ],
      ),
    );
  }
}
