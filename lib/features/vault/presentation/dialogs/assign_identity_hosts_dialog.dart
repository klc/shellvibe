import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../../../../app/theme/shellvibe_tokens.dart';
import '../../../../app/widgets/adaptive_modal.dart';
import '../../../../app/widgets/shellvibe_ui.dart';
import '../../../hosts/domain/models/host_model.dart';
import '../../../hosts/presentation/notifiers/hosts_notifier.dart';
import '../../domain/models/identity_model.dart';

/// Binds or unbinds many hosts to one identity in a single pass.
///
/// Editing hosts one at a time is the only other way to re-point them, which
/// does not scale past a handful — and a vault key that has to be replaced
/// tends to affect every host at once.
class AssignIdentityHostsDialog extends ConsumerStatefulWidget {
  final IdentityModel identity;

  const AssignIdentityHostsDialog({super.key, required this.identity});

  @override
  ConsumerState<AssignIdentityHostsDialog> createState() =>
      _AssignIdentityHostsDialogState();
}

class _AssignIdentityHostsDialogState
    extends ConsumerState<AssignIdentityHostsDialog> {
  /// Host ids ticked in the list. Seeded from the current bindings on first
  /// build, so an unchanged dialog saves nothing.
  Set<String>? _selected;

  String _searchQuery = '';
  bool _onlyUnbound = false;
  bool _isSaving = false;

  Set<String> _initialSelection(List<HostModel> hosts) => hosts
      .where((host) => host.identityId == widget.identity.id)
      .map((host) => host.id)
      .toSet();

  @override
  Widget build(BuildContext context) {
    final tokens = ShellVibeTokens.resolve(context);
    final hosts = ref.watch(hostsProvider).value ?? const <HostModel>[];
    final selected = _selected ??= _initialSelection(hosts);

    final visible =
        hosts.where((host) {
          // A host already bound to this identity stays visible under the
          // "unassigned only" filter: hiding it would make unticking impossible.
          if (_onlyUnbound &&
              host.identityId != null &&
              host.identityId != widget.identity.id) {
            return false;
          }
          if (_searchQuery.isEmpty) return true;
          return host.label.toLowerCase().contains(_searchQuery) ||
              host.hostname.toLowerCase().contains(_searchQuery);
        }).toList()..sort(
          (a, b) => a.label.toLowerCase().compareTo(b.label.toLowerCase()),
        );

    final initial = _initialSelection(hosts);
    final toBind = selected.difference(initial);
    final toUnbind = initial.difference(selected);
    final hasChanges = toBind.isNotEmpty || toUnbind.isNotEmpty;

    return ShadDialog(
      title: Row(
        children: [
          const Icon(LucideIcons.link, size: 20),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              'Assign hosts',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
      description: Text(
        'Pick every host that should authenticate with '
        '"${widget.identity.title}".',
      ),
      actions: adaptiveDialogActions(context, [
        ShellVibeButton.secondary(
          label: 'Cancel',
          onPressed: _isSaving ? null : () => Navigator.of(context).pop(),
        ),
        ShellVibeButton(
          key: const Key('assign_hosts_save_button'),
          label: _saveLabel(toBind.length, toUnbind.length),
          onPressed: hasChanges
              ? () => _save(bind: toBind, unbind: toUnbind)
              : null,
          busy: _isSaving,
        ),
      ]),
      actionsAxis: adaptiveDialogActionsAxis(context),
      // ShadDialog does not put a Material in the tree, and the search field and
      // checkboxes below need one for ink and text selection.
      child: Material(
        type: MaterialType.transparency,
        child: SizedBox(
          width: 460,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 8),
              ShellVibeSearchField(
                fieldKey: const Key('assign_hosts_search_input'),
                hintText: 'Search hosts…',
                onChanged: (value) =>
                    setState(() => _searchQuery = value.toLowerCase()),
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      '${selected.length} of ${hosts.length} selected',
                      style: TextStyle(fontSize: 12, color: tokens.textSubtle),
                    ),
                  ),
                  ShellVibeButton.quiet(
                    label: _onlyUnbound ? 'Showing unassigned' : 'Showing all',
                    onPressed: () =>
                        setState(() => _onlyUnbound = !_onlyUnbound),
                  ),
                  ShellVibeButton.quiet(
                    key: const Key('assign_hosts_select_all_button'),
                    label: 'Select all',
                    onPressed: visible.isEmpty
                        ? null
                        : () => setState(() {
                            final visibleIds = visible
                                .map((host) => host.id)
                                .toSet();
                            // Toggle against what is on screen only, so a search
                            // narrows what "select all" can touch.
                            if (visibleIds.every(selected.contains)) {
                              selected.removeAll(visibleIds);
                            } else {
                              selected.addAll(visibleIds);
                            }
                          }),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              SizedBox(
                height: 280,
                child: visible.isEmpty
                    ? Center(
                        child: Text(
                          hosts.isEmpty
                              ? 'This workspace has no hosts yet.'
                              : 'No host matches this filter.',
                          style: TextStyle(
                            fontSize: 12.5,
                            color: tokens.textSubtle,
                          ),
                        ),
                      )
                    : ListView.builder(
                        itemCount: visible.length,
                        itemBuilder: (context, index) {
                          final host = visible[index];
                          final isSelected = selected.contains(host.id);
                          final boundElsewhere =
                              host.identityId != null &&
                              host.identityId != widget.identity.id;

                          return ShadCheckbox(
                            key: Key('assign_host_checkbox_${host.id}'),
                            value: isSelected,
                            onChanged: (value) => setState(() {
                              if (value) {
                                selected.add(host.id);
                              } else {
                                selected.remove(host.id);
                              }
                            }),
                            label: Text(
                              host.label,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            sublabel: Text(
                              boundElsewhere
                                  ? '${host.hostname} · uses another identity'
                                  : host.hostname,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 11,
                                color: boundElsewhere
                                    ? tokens.warning
                                    : tokens.textSubtle,
                              ),
                            ),
                          );
                        },
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  static String _saveLabel(int bindCount, int unbindCount) {
    if (bindCount > 0 && unbindCount > 0) {
      return 'Apply to ${bindCount + unbindCount} hosts';
    }
    if (unbindCount > 0) {
      return unbindCount == 1 ? 'Detach 1 host' : 'Detach $unbindCount hosts';
    }
    if (bindCount == 1) return 'Assign 1 host';
    return 'Assign $bindCount hosts';
  }

  Future<void> _save({
    required Set<String> bind,
    required Set<String> unbind,
  }) async {
    setState(() => _isSaving = true);
    try {
      final notifier = ref.read(hostsProvider.notifier);
      var changed = 0;
      if (bind.isNotEmpty) {
        changed += await notifier.assignIdentityToHosts(
          bind.toList(),
          widget.identity.id,
        );
      }
      if (unbind.isNotEmpty) {
        changed += await notifier.assignIdentityToHosts(unbind.toList(), null);
      }
      if (mounted) {
        Navigator.of(context).pop(changed);
      }
    } catch (e) {
      if (mounted) {
        ShadToaster.of(context).show(
          ShadToast.destructive(
            title: const Text('Assign Hosts Error'),
            description: Text('$e'),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }
}
