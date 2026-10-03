import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../../../../app/theme/shellvibe_tokens.dart';
import '../../../../app/widgets/adaptive_modal.dart';
import '../../../../app/widgets/shellvibe_ui.dart';
import '../../../../core/utils/platform_capabilities.dart';
import '../../../hosts/domain/models/host_model.dart';
import '../../../hosts/presentation/notifiers/host_groups_notifier.dart';
import '../../../hosts/presentation/notifiers/hosts_notifier.dart';
import '../../../terminal/presentation/notifiers/terminal_tabs_notifier.dart';
import '../../domain/models/run_target.dart';

/// Asks where a snippet or runbook should run.
///
/// Hosts are a multi-select with search and a group filter, because the common
/// case is "this on every host in the `web` group". Open terminal sessions are
/// offered only for snippets ([allowTerminal]): a runbook needs the exit codes
/// a background run can read and a typed-in command cannot.
///
/// Resolves to the chosen targets — either one [HostRunTarget] per host, or a
/// single terminal target — or null when dismissed.
class RunTargetSheet extends ConsumerStatefulWidget {
  final bool allowTerminal;

  const RunTargetSheet({super.key, this.allowTerminal = false});

  static Future<List<RunTarget>?> show(
    BuildContext context, {
    required String subject,
    bool allowTerminal = false,
  }) {
    return showAdaptivePanel<List<RunTarget>>(
      context: context,
      title: 'Run "$subject"',
      desktopHeight: 560,
      desktopWidth: 520,
      isScrollControlled: true,
      builder: (ctx) => RunTargetSheet(allowTerminal: allowTerminal),
    );
  }

  @override
  ConsumerState<RunTargetSheet> createState() => _RunTargetSheetState();
}

class _RunTargetSheetState extends ConsumerState<RunTargetSheet> {
  final Set<String> _selectedIds = {};
  String _query = '';
  String? _groupId;

  /// Local shells cannot take a background connection yet.
  static bool _selectable(HostModel host) => host.protocol != 'local';

  List<HostModel> _visible(List<HostModel> hosts) => hosts
      .where((h) => _groupId == null || h.groupIds.contains(_groupId))
      .where((h) => hostMatchesQuery(h, _query))
      .toList();

  void _toggleAllVisible(List<HostModel> visible) {
    final ids = visible.where(_selectable).map((h) => h.id).toSet();
    setState(() {
      if (ids.isNotEmpty && ids.every(_selectedIds.contains)) {
        _selectedIds.removeAll(ids);
      } else {
        _selectedIds.addAll(ids);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final tokens = ShellVibeTokens.resolve(context);
    final hostsAsync = ref.watch(hostsProvider);
    final groups = ref.watch(hostGroupsProvider).value ?? const [];
    final tabs = widget.allowTerminal ? ref.watch(terminalTabsProvider) : null;
    final hasTerminal = tabs != null && tabs.tabs.isNotEmpty;

    final body = hostsAsync.when(
      loading: () => const Padding(
        padding: EdgeInsets.all(24),
        child: Center(child: CircularProgressIndicator()),
      ),
      error: (e, _) => Padding(
        padding: const EdgeInsets.all(24),
        child: Text('Hosts could not be loaded: $e'),
      ),
      data: (hosts) {
        final visible = _visible(hosts);
        final selectable = visible.where(_selectable).toList();
        final allSelected =
            selectable.isNotEmpty &&
            selectable.every((h) => _selectedIds.contains(h.id));
        final count = _selectedIds.length;

        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (hasTerminal) ...[
              const ShellVibeSectionLabel(label: 'Open terminal'),
              ListTile(
                key: const Key('run_target_active_pane'),
                dense: true,
                leading: const Icon(LucideIcons.squareTerminal, size: 18),
                title: const Text('Active pane'),
                subtitle: const Text(
                  'Types it in and presses Enter. Unverified.',
                ),
                onTap: () => Navigator.of(
                  context,
                ).pop(<RunTarget>[const ActivePaneRunTarget()]),
              ),
              if (tabs.isBroadcasting)
                ListTile(
                  key: const Key('run_target_selected_panes'),
                  dense: true,
                  leading: const Icon(LucideIcons.radio, size: 18),
                  title: Text(
                    'Selected panes (${tabs.selectedPaneIds.length})',
                  ),
                  subtitle: const Text('Broadcasts to every selected pane.'),
                  onTap: () => Navigator.of(
                    context,
                  ).pop(<RunTarget>[const SelectedPanesRunTarget()]),
                ),
              const ShellVibeSectionLabel(label: 'Background on hosts'),
            ],
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
              child: ShellVibeSearchField(
                fieldKey: const Key('run_target_search'),
                hintText: 'Search hosts…',
                autofocus: !isMobilePlatform && !hasTerminal,
                onChanged: (value) => setState(() => _query = value),
              ),
            ),
            if (groups.isNotEmpty)
              SizedBox(
                height: 34,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  children: [
                    _GroupChip(
                      chipKey: const Key('run_target_group_all'),
                      label: 'All',
                      selected: _groupId == null,
                      onTap: () => setState(() => _groupId = null),
                    ),
                    for (final group in groups)
                      _GroupChip(
                        chipKey: Key('run_target_group_${group.id}'),
                        label: group.name,
                        selected: _groupId == group.id,
                        onTap: () => setState(() => _groupId = group.id),
                      ),
                  ],
                ),
              ),
            CheckboxListTile(
              key: const Key('run_target_select_all'),
              dense: true,
              controlAffinity: ListTileControlAffinity.leading,
              value: allSelected,
              onChanged: selectable.isEmpty
                  ? null
                  : (_) => _toggleAllVisible(visible),
              title: Text('Select all visible (${selectable.length})'),
            ),
            Divider(height: 1, color: tokens.border),
            Flexible(
              child: visible.isEmpty
                  ? Padding(
                      padding: const EdgeInsets.all(24),
                      child: Text(
                        hosts.isEmpty
                            ? 'No hosts yet.'
                            : 'No hosts match that filter.',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: tokens.textSubtle),
                      ),
                    )
                  : ListView(
                      shrinkWrap: true,
                      children: [
                        for (final host in visible)
                          CheckboxListTile(
                            key: Key('run_target_host_${host.id}'),
                            dense: true,
                            controlAffinity: ListTileControlAffinity.leading,
                            value: _selectedIds.contains(host.id),
                            onChanged: _selectable(host)
                                ? (on) => setState(() {
                                    on == true
                                        ? _selectedIds.add(host.id)
                                        : _selectedIds.remove(host.id);
                                  })
                                : null,
                            title: Text(host.label),
                            subtitle: Text(
                              _selectable(host)
                                  ? '${host.hostname}:${host.port}'
                                  : 'Local shell — background runs need an '
                                        'SSH host',
                            ),
                          ),
                      ],
                    ),
            ),
            Divider(height: 1, color: tokens.border),
            Padding(
              padding: const EdgeInsets.all(12),
              child: ShellVibeButton(
                key: const Key('run_target_confirm'),
                label: count == 0
                    ? 'Choose hosts'
                    : 'Run on $count ${count == 1 ? 'host' : 'hosts'}',
                icon: LucideIcons.play,
                expand: true,
                onPressed: count == 0
                    ? null
                    : () {
                        final chosen = [
                          for (final host in hosts)
                            if (_selectedIds.contains(host.id))
                              HostRunTarget(host),
                        ];
                        Navigator.of(context).pop(<RunTarget>[...chosen]);
                      },
              ),
            ),
          ],
        );
      },
    );

    // A sheet has no height of its own to give the list: cap it, and lift it
    // above the keyboard that the search field raises.
    if (usesDesktopModals(context)) return body;
    return AnimatedPadding(
      duration: const Duration(milliseconds: 100),
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SafeArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.sizeOf(context).height * 0.8,
          ),
          child: body,
        ),
      ),
    );
  }
}

class _GroupChip extends StatelessWidget {
  final Key chipKey;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _GroupChip({
    required this.chipKey,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final tokens = ShellVibeTokens.resolve(context);
    return Padding(
      padding: const EdgeInsets.only(right: 6),
      child: InkWell(
        key: chipKey,
        onTap: onTap,
        borderRadius: BorderRadius.circular(tokens.radiusPill),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
          decoration: BoxDecoration(
            color: selected
                ? tokens.brand.withValues(alpha: 0.12)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(tokens.radiusPill),
            border: Border.all(
              color: selected
                  ? tokens.brand.withValues(alpha: 0.34)
                  : tokens.border,
            ),
          ),
          child: Text(
            label,
            style: Theme.of(context).textTheme.labelMedium?.copyWith(
              color: selected ? tokens.brand : tokens.textMuted,
            ),
          ),
        ),
      ),
    );
  }
}
