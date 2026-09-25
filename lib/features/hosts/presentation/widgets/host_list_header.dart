import 'package:flutter/material.dart';

import '../../../../app/theme/shellvibe_tokens.dart';
import '../../../../app/widgets/shellvibe_ui.dart';
import '../../domain/models/host_group_model.dart';
import '../../domain/models/host_model.dart';
import 'host_list_filter.dart';

// ── list primitives ───────────────────────────────────────────────────────

/// Column widths shared by the header and every row so they stay aligned.
const List<int> kHostColumnFlex = [5, 5, 3, 2];

/// Rendered width of the row's trailing controls.
///
/// Measured, not guessed: the two [ShellVibeIconButton]s occupy one control
/// height each (34px under a pointer) and the [PopupMenuButton] 48px once
/// Material's minimum tap target is applied, plus the 12px the popup adds
/// around its icon, plus [kHostStarWidth] for the star.
const double kHostActionsWidth = 124 + kHostStarWidth;

/// The star's slot. Always reserved, even while the star is invisible: a
/// control that appears on hover must not push the row's other controls
/// sideways as the pointer crosses it.
const double kHostStarWidth = 34;

/// The same measurement for a phone row, which carries one icon action and the
/// overflow menu — never the spelled-out Open pill, which does not fit beside
/// an address on a 400px screen.
const double kHostActionsWidthCompact = 92;

class HostListHeader extends StatelessWidget {
  final ShellVibeTokens tokens;
  final bool compact;

  const HostListHeader({
    super.key,
    required this.tokens,
    required this.compact,
  });

  @override
  Widget build(BuildContext context) {
    final style = TextStyle(
      fontSize: 10,
      fontWeight: FontWeight.w600,
      letterSpacing: 1.4,
      color: tokens.textSubtle,
    );
    // No rule under the header: the rows below are pills with their own
    // spacing, so a line here would only cut the panel in half.
    // The list below pads 10px, each row another 10 (14 when compact), so the
    // header has to carry the sum or the labels sit off their columns.
    return Padding(
      padding: EdgeInsets.fromLTRB(compact ? 24 : 20, 0, compact ? 24 : 20, 6),
      child: Row(
        children: [
          SizedBox(width: compact ? 15 : 24),
          // A phone row stacks its name over its address, so there is no
          // second column for an ADDRESS label to head.
          Expanded(
            flex: kHostColumnFlex[0],
            child: Text('NAME', style: style, maxLines: 1),
          ),
          if (!compact)
            Expanded(
              flex: kHostColumnFlex[1],
              child: Text('ADDRESS', style: style, maxLines: 1),
            ),
          if (!compact) ...[
            Expanded(
              flex: kHostColumnFlex[2],
              child: Text('TAG', style: style, maxLines: 1),
            ),
            Expanded(
              flex: kHostColumnFlex[3],
              child: Text('LAST', style: style, maxLines: 1),
            ),
          ],
          SizedBox(
            width: compact ? kHostActionsWidthCompact : kHostActionsWidth,
          ),
        ],
      ),
    );
  }
}

class HostFilterChip extends StatelessWidget {
  final Key? chipKey;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const HostFilterChip({
    super.key,
    this.chipKey,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final tokens = ShellVibeTokens.resolve(context);
    return Padding(
      padding: const EdgeInsets.only(right: 7),
      child: InkWell(
        key: chipKey,
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            color: selected
                ? tokens.brand.withValues(alpha: 0.14)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: selected
                  ? tokens.brand.withValues(alpha: 0.26)
                  : tokens.textPrimary.withValues(alpha: 0.07),
            ),
          ),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 13,
              fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
              color: selected ? tokens.brandSoft : tokens.textMuted,
            ),
          ),
        ),
      ),
    );
  }
}

/// The narrow-width filter bar shown above the host list in place of the
/// context column, on widths too tight for the group rail.
class HostCompactFilterBar extends StatelessWidget {
  final List<HostGroupModel> groups;
  final List<HostModel> hosts;
  final String? selectedGroupId;
  final HostFilter filter;
  final ValueChanged<String> onSearchChanged;
  final ValueChanged<HostFilter> onSelectFilter;
  final ValueChanged<String> onSelectGroup;

  const HostCompactFilterBar({
    super.key,
    required this.groups,
    required this.hosts,
    required this.selectedGroupId,
    required this.filter,
    required this.onSearchChanged,
    required this.onSelectFilter,
    required this.onSelectGroup,
  });

  @override
  Widget build(BuildContext context) {
    final tokens = ShellVibeTokens.resolve(context);
    return Container(
      padding: EdgeInsets.fromLTRB(
        tokens.pagePadding,
        10,
        tokens.pagePadding,
        8,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ShellVibeSearchField(
            fieldKey: const Key('hosts_search_input'),
            hintText: 'Search hosts, addresses and protocols…',
            onChanged: onSearchChanged,
          ),
          const SizedBox(height: 10),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                HostFilterChip(
                  label: 'All',
                  selected: selectedGroupId == null && filter == HostFilter.all,
                  onTap: () => onSelectFilter(HostFilter.all),
                ),
                HostFilterChip(
                  label: 'Connected',
                  selected:
                      selectedGroupId == null && filter == HostFilter.connected,
                  onTap: () => onSelectFilter(HostFilter.connected),
                ),
                HostFilterChip(
                  chipKey: const Key('hosts_filter_favorites_chip'),
                  label: 'Favorites',
                  selected:
                      selectedGroupId == null && filter == HostFilter.favorites,
                  onTap: () => onSelectFilter(HostFilter.favorites),
                ),
                for (final group in groups)
                  HostFilterChip(
                    chipKey: Key('group_${group.id}'),
                    label: group.name,
                    selected: selectedGroupId == group.id,
                    onTap: () => onSelectGroup(group.id),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
