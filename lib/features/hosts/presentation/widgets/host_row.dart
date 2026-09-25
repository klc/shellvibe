import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../../../../app/theme/shellvibe_tokens.dart';
import '../../../../app/widgets/shellvibe_ui.dart';
import '../../domain/models/host_group_model.dart';
import '../../domain/models/host_model.dart';
import 'host_list_header.dart';
import 'host_list_filter.dart';

/// Single-line dense host row.
///
/// The wireframe replaces the card grid with this so ~9 hosts fit where 6 did,
/// and status reads as dot + text rather than colour alone.
class HostRow extends StatefulWidget {
  final HostModel host;
  final List<HostGroupModel> groups;
  final bool connected;
  final bool isConnecting;
  final bool selected;
  final bool compact;
  final bool isFavorite;
  final VoidCallback onSelect;
  final VoidCallback onConnect;
  final VoidCallback onOpenSftp;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  final VoidCallback onToggleFavorite;

  const HostRow({
    super.key,
    required this.host,
    required this.groups,
    required this.connected,
    required this.isConnecting,
    required this.selected,
    required this.compact,
    required this.isFavorite,
    required this.onSelect,
    required this.onConnect,
    required this.onOpenSftp,
    required this.onEdit,
    required this.onDelete,
    required this.onToggleFavorite,
  });

  @override
  State<HostRow> createState() => _HostRowState();
}

class _HostRowState extends State<HostRow> {
  /// Whether the pointer is over the row, which is what reveals the star.
  ///
  /// A star on every row would be a column of them down a list where most
  /// hosts are not starred; showing it under the pointer keeps the list as it
  /// was and still puts the control where the hand already is. A starred row
  /// shows it always — that one is state, not an offer.
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final host = widget.host;
    final connected = widget.connected;
    final selected = widget.selected;
    final compact = widget.compact;
    final isConnecting = widget.isConnecting;
    final groups = widget.groups;
    final onSelect = widget.onSelect;
    final onConnect = widget.onConnect;
    final onOpenSftp = widget.onOpenSftp;
    final onEdit = widget.onEdit;
    final onDelete = widget.onDelete;
    final tokens = ShellVibeTokens.resolve(context);
    final address =
        '${host.username != null && host.username!.isNotEmpty ? '${host.username}@' : ''}'
        '${host.hostname}:${host.port}';
    final groupName = groups
        .where((group) => group.id == host.groupId)
        .firstOrNull
        ?.name;
    final monoStyle = shellvibeMono(
      context,
      color: selected ? tokens.textSecondary : tokens.textMuted,
    );

    return Semantics(
      button: true,
      selected: selected,
      label:
          '${host.label}, ${host.protocol} host at ${host.hostname}, '
          '${connected ? 'connected' : 'not connected'}'
          '${widget.isFavorite ? ', favorite' : ''}',
      child: Padding(
        padding: const EdgeInsets.only(bottom: 2),
        child: MouseRegion(
          onEnter: (_) => setState(() => _hovered = true),
          onExit: (_) => setState(() => _hovered = false),
          child: InkWell(
            onTap: onSelect,
            borderRadius: BorderRadius.circular(tokens.radiusMedium),
            child: Container(
              padding: EdgeInsets.symmetric(horizontal: compact ? 14 : 10),
              // Phone rows trade density for a 44px hit target on the row action.
              height: compact ? 62 : tokens.rowHeight,
              decoration: BoxDecoration(
                color: selected
                    ? tokens.brand.withValues(alpha: 0.10)
                    : Colors.transparent,
                borderRadius: BorderRadius.circular(tokens.radiusMedium),
                border: Border.all(
                  color: selected
                      ? tokens.brand.withValues(alpha: 0.22)
                      : Colors.transparent,
                ),
              ),
              child: Row(
                children: [
                  // A lit bar rather than a dot: read down a column of nine hosts
                  // it separates live from idle at a glance, and it doubles as
                  // the row's left margin.
                  SizedBox(
                    width: compact ? 15 : 24,
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: ShellVibeRowIndicator(
                        live: connected,
                        height: compact ? 26 : 20,
                      ),
                    ),
                  ),
                  // Side by side the two columns split about 250px on a phone,
                  // and `ubuntu@152.70.22.207:22` wants 160 of them on its own.
                  // Stacked, each line gets the row's whole width.
                  if (compact)
                    Expanded(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Flexible(
                                child: Text(
                                  host.label,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: Theme.of(context).textTheme.titleSmall
                                      ?.copyWith(
                                        color: selected
                                            ? tokens.textPrimary
                                            : tokens.textSecondary,
                                      ),
                                ),
                              ),
                              // A phone has no pointer to hover with, so the
                              // star is shown there only as the state it
                              // already is; the detail sheet carries the
                              // toggle. It rides on the label line because the
                              // actions slot is measured for two controls.
                              if (widget.isFavorite) ...[
                                const SizedBox(width: 6),
                                Icon(
                                  LucideIcons.star,
                                  size: 12,
                                  color: tokens.brand,
                                ),
                              ],
                            ],
                          ),
                          const SizedBox(height: 2),
                          Text(
                            // Compact drops the last-seen column, so the state
                            // text that pairs with the bar moves onto the
                            // address line.
                            connected ? '$address · connected' : address,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: monoStyle,
                          ),
                        ],
                      ),
                    )
                  else ...[
                    Expanded(
                      flex: kHostColumnFlex[0],
                      child: Text(
                        host.label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          color: selected
                              ? tokens.textPrimary
                              : tokens.textSecondary,
                        ),
                      ),
                    ),
                    Expanded(
                      flex: kHostColumnFlex[1],
                      child: Text(
                        address,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: monoStyle,
                      ),
                    ),
                    Expanded(
                      flex: kHostColumnFlex[2],
                      child: groupName == null
                          ? const SizedBox.shrink()
                          : Align(
                              alignment: Alignment.centerLeft,
                              child: HostTagChip(label: groupName),
                            ),
                    ),
                    Expanded(
                      flex: kHostColumnFlex[3],
                      child: Text(
                        // Status is never carried by colour alone: the bar is
                        // paired with this text so the row reads without hue.
                        connected ? 'connected' : host.protocol,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: shellvibeMono(
                          context,
                          size: 11,
                          color: connected ? tokens.brand : tokens.textSubtle,
                        ),
                      ),
                    ),
                  ],
                  SizedBox(
                    width: compact
                        ? kHostActionsWidthCompact
                        : kHostActionsWidth,
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        // A phone row shows its star on the label line.
                        if (!compact)
                          SizedBox(
                            width: kHostStarWidth,
                            child: (_hovered || widget.isFavorite)
                                ? ShellVibeIconButton(
                                    buttonKey: Key('favorite_host_${host.id}'),
                                    icon: LucideIcons.star,
                                    tooltip: widget.isFavorite
                                        ? 'Remove from favorites'
                                        : 'Add to favorites',
                                    onPressed: widget.onToggleFavorite,
                                    active: widget.isFavorite,
                                  )
                                : const SizedBox.shrink(),
                          ),
                        if (isConnecting)
                          const Padding(
                            padding: EdgeInsets.all(8),
                            child: SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            ),
                          )
                        // The selected row is the only one that spells its
                        // primary action out; the rest keep quiet icons so a full
                        // list stays dense without turning into a wall of buttons.
                        // A phone row never spells it out — the pill plus the
                        // menu overflowed the row, and selecting a host there
                        // opens the detail sheet, which carries Connect anyway.
                        else if (selected && !compact)
                          ShellVibeButton.secondary(
                            buttonKey: Key('connect_host_${host.id}'),
                            label: 'Open',
                            icon: LucideIcons.terminal,
                            onPressed: onConnect,
                          )
                        else
                          ShellVibeIconButton(
                            buttonKey: Key('connect_host_${host.id}'),
                            icon: LucideIcons.play,
                            tooltip: 'Connect Terminal',
                            onPressed: onConnect,
                          ),
                        // Transfer only makes sense over SSH; a local host has
                        // no SFTP subsystem to talk to. On phones it drops out
                        // entirely — the row has one action there, and transfer
                        // lives in the detail sheet.
                        if (hostSupportsFileTransfer(host) &&
                            !selected &&
                            !compact)
                          ShellVibeIconButton(
                            buttonKey: Key('sftp_host_${host.id}'),
                            icon: LucideIcons.folderSync,
                            tooltip: 'File Transfer (SFTP)',
                            onPressed: onOpenSftp,
                          ),
                        PopupMenuButton<String>(
                          tooltip: 'Host actions',
                          // No `constraints` here: that property sizes the popup
                          // menu, not the button, and pinning it clipped the menu
                          // items.
                          padding: EdgeInsets.zero,
                          iconSize: 16,
                          icon: const Icon(LucideIcons.ellipsis, size: 16),
                          onSelected: (value) {
                            if (value == 'edit') onEdit();
                            if (value == 'delete') onDelete();
                          },
                          itemBuilder: (context) => [
                            const PopupMenuItem(
                              value: 'edit',
                              child: Row(
                                children: [
                                  Icon(LucideIcons.pencil, size: 16),
                                  SizedBox(width: 8),
                                  Text('Edit host'),
                                ],
                              ),
                            ),
                            PopupMenuItem(
                              value: 'delete',
                              child: Row(
                                children: [
                                  Icon(
                                    LucideIcons.trash2,
                                    size: 16,
                                    color: tokens.danger,
                                  ),
                                  const SizedBox(width: 8),
                                  Text(
                                    'Delete host',
                                    style: TextStyle(color: tokens.danger),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Neutral tag pill on a host row.
///
/// Deliberately not a [ShellVibeStatusChip]: a group name is a label, not a state,
/// so it never borrows a status hue.
class HostTagChip extends StatelessWidget {
  final String label;

  const HostTagChip({super.key, required this.label});

  @override
  Widget build(BuildContext context) {
    final tokens = ShellVibeTokens.resolve(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: tokens.textPrimary.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(tokens.radiusSmall),
      ),
      child: Text(
        label,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: tokens.textMuted,
        ),
      ),
    );
  }
}
