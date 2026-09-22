import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import 'package:uuid/uuid.dart';

import '../../../../app/theme/shellvibe_tokens.dart';
import '../../../../app/widgets/adaptive_modal.dart';
import '../../../../app/widgets/shellvibe_ui.dart';
import '../../../../core/utils/platform_capabilities.dart';
import '../../../hosts/domain/models/host_model.dart';
import '../../../hosts/presentation/notifiers/hosts_notifier.dart';
import '../../../terminal/domain/models/terminal_tab_session.dart';
import '../../domain/models/template_model.dart';
import '../../domain/models/template_pane_model.dart';
import '../../domain/services/template_editing.dart';
import '../notifiers/templates_notifier.dart';

/// Shows what a saved layout opens, and lets it be changed without running it.
///
/// Every tab is listed with the panes split out of it, nested the way they
/// are split, each naming the host it connects to. A pane can be pointed at
/// another host, split, turned, or removed; a tab can be added, moved or
/// removed. Nothing is written until Save.
class TemplateEditorPanel extends ConsumerStatefulWidget {
  const TemplateEditorPanel({super.key, required this.template});

  final TemplateModel template;

  static Future<void> show(BuildContext context, TemplateModel template) {
    return showAdaptivePanel<void>(
      context: context,
      title: 'Edit Template',
      desktopWidth: 600,
      isScrollControlled: true,
      builder: (_) => TemplateEditorPanel(template: template),
    );
  }

  @override
  ConsumerState<TemplateEditorPanel> createState() =>
      _TemplateEditorPanelState();
}

/// What a pane is pointed at: a saved host, or a local shell (`hostId` null).
typedef _PaneTarget = ({String? hostId});

class _TemplateEditorPanelState extends ConsumerState<TemplateEditorPanel> {
  late TemplateModel _draft = widget.template;
  late final _nameController = TextEditingController(
    text: widget.template.name,
  );
  late final _descriptionController = TextEditingController(
    text: widget.template.description ?? '',
  );
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _nameController.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _nameController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  void _edit(TemplateModel Function(TemplateModel draft) change) {
    setState(() => _draft = change(_draft));
  }

  Future<void> _save() async {
    final name = _nameController.text.trim();
    if (name.isEmpty) return;
    final description = _descriptionController.text.trim();
    setState(() => _saving = true);
    await ref
        .read(templatesProvider.notifier)
        .updateTemplate(
          TemplateModel(
            id: _draft.id,
            workspaceId: _draft.workspaceId,
            name: name,
            description: description.isEmpty ? null : description,
            panes: _draft.panes,
            activePaneId: _draft.activePaneId,
            createdAt: _draft.createdAt,
          ),
        );
    if (mounted) Navigator.of(context).pop();
  }

  /// A local shell can only be offered where the runner can open one: on a
  /// platform that has them, and not as a split of an SSH pane, which the
  /// terminal would open as a second SSH session instead.
  bool _localAllowedUnder(String? parentId) {
    if (!supportsLocalShell) return false;
    if (parentId == null) return true;
    final parent = _draft.panes.where((p) => p.id == parentId).firstOrNull;
    return parent?.sessionType != TerminalSessionType.ssh;
  }

  Future<_PaneTarget?> _pickTarget({
    required String title,
    required bool allowLocal,
  }) {
    return showAdaptivePanel<_PaneTarget>(
      context: context,
      title: title,
      desktopHeight: 420,
      builder: (ctx) => _TargetPicker(
        allowLocal: allowLocal,
        onPicked: (target) => Navigator.of(ctx).pop(target),
      ),
    );
  }

  Future<void> _changeHost(TemplatePaneModel pane) async {
    final target = await _pickTarget(
      title: 'Connect this pane to',
      allowLocal: _localAllowedUnder(pane.parentPaneId),
    );
    if (target == null) return;
    _edit((draft) => draft.withPaneHost(pane.id, target.hostId));
  }

  Future<void> _split(TemplatePaneModel pane, Axis direction) async {
    final target = await _pickTarget(
      title: 'Split with',
      allowLocal: _localAllowedUnder(pane.id),
    );
    if (target == null) return;
    _edit(
      (draft) => draft.addSplit(
        pane.id,
        newPaneId: const Uuid().v4(),
        direction: direction,
        hostId: target.hostId,
      ),
    );
  }

  Future<void> _addTab() async {
    final target = await _pickTarget(
      title: 'New tab',
      allowLocal: _localAllowedUnder(null),
    );
    if (target == null) return;
    _edit(
      (draft) =>
          draft.addTab(newPaneId: const Uuid().v4(), hostId: target.hostId),
    );
  }

  @override
  Widget build(BuildContext context) {
    final tokens = ShellVibeTokens.resolve(context);
    final hosts = ref.watch(hostsProvider).value ?? const <HostModel>[];
    final hostsById = {for (final host in hosts) host.id: host};
    final roots = _draft.orderedRoots;
    final desktop = usesDesktopModals(context);

    final body = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 4),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // The sheet a phone gets has no header of its own.
              if (!desktop)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Text(
                    'Edit Template',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: tokens.textPrimary,
                    ),
                  ),
                ),
              TextField(
                key: const Key('template_editor_name'),
                controller: _nameController,
                decoration: const InputDecoration(labelText: 'Name'),
              ),
              const SizedBox(height: 10),
              TextField(
                key: const Key('template_editor_description'),
                controller: _descriptionController,
                decoration: const InputDecoration(
                  labelText: 'Description (optional)',
                ),
              ),
            ],
          ),
        ),
        ShellVibeSectionLabel(
          label: 'Layout · ${templateSummary(_draft)}',
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 6),
        ),
        Flexible(
          child: ListView(
            shrinkWrap: true,
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
            children: [
              if (roots.isEmpty)
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text(
                    'This template opens nothing. Add a tab to give it '
                    'something to open.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: tokens.textSubtle),
                  ),
                ),
              for (var index = 0; index < roots.length; index++)
                _TabCard(
                  key: Key('template_tab_${roots[index].id}'),
                  index: index,
                  isFirst: index == 0,
                  isLast: index == roots.length - 1,
                  onMoveUp: () => _edit(
                    (draft) => draft.moveTab(roots[index].id, index - 1),
                  ),
                  onMoveDown: () => _edit(
                    (draft) => draft.moveTab(roots[index].id, index + 1),
                  ),
                  onRemove: () =>
                      _edit((draft) => draft.removeTab(roots[index].id)),
                  root: roots[index].id,
                  children: [
                    for (final entry in _walk(roots[index]))
                      _PaneRow(
                        key: Key('template_pane_${entry.pane.id}'),
                        pane: entry.pane,
                        depth: entry.depth,
                        host: hostsById[entry.pane.hostId],
                        problem: _draft.problemWith(
                          entry.pane,
                          hostsById: hostsById,
                          supportsLocalShell: supportsLocalShell,
                        ),
                        onChangeHost: () => _changeHost(entry.pane),
                        onSplit: (direction) => _split(entry.pane, direction),
                        onToggleDirection: entry.pane.isRoot
                            ? null
                            : () => _edit(
                                (draft) => draft.withSplitDirection(
                                  entry.pane.id,
                                  entry.pane.splitDirection == Axis.vertical
                                      ? Axis.horizontal
                                      : Axis.vertical,
                                ),
                              ),
                        onRemove: entry.pane.isRoot
                            ? null
                            : () => _edit(
                                (draft) => draft.removePane(entry.pane.id),
                              ),
                      ),
                  ],
                ),
              Align(
                alignment: Alignment.centerLeft,
                child: ShellVibeButton.quiet(
                  buttonKey: const Key('template_add_tab'),
                  icon: LucideIcons.plus,
                  label: 'Add Tab',
                  onPressed: _addTab,
                ),
              ),
            ],
          ),
        ),
        Container(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 14),
          decoration: BoxDecoration(
            border: Border(top: BorderSide(color: tokens.border)),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              ShellVibeButton.secondary(
                buttonKey: const Key('template_editor_cancel'),
                label: 'Cancel',
                onPressed: () => Navigator.of(context).pop(),
              ),
              const SizedBox(width: 8),
              ShellVibeButton(
                buttonKey: const Key('template_editor_save'),
                label: 'Save',
                busy: _saving,
                onPressed: _nameController.text.trim().isEmpty || _saving
                    ? null
                    : _save,
              ),
            ],
          ),
        ),
      ],
    );

    if (desktop) return body;
    // A sheet sizes to its content; this keeps a long template from pushing
    // the Save row off a phone's screen.
    return ConstrainedBox(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.sizeOf(context).height * 0.85,
      ),
      child: Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: body,
      ),
    );
  }

  /// [root] and its splits, depth-first, each with how deep it is nested.
  List<({TemplatePaneModel pane, int depth})> _walk(TemplatePaneModel root) {
    final rows = <({TemplatePaneModel pane, int depth})>[];
    void visit(TemplatePaneModel pane, int depth) {
      rows.add((pane: pane, depth: depth));
      for (final child in _draft.childrenOf(pane.id)) {
        visit(child, depth + 1);
      }
    }

    visit(root, 0);
    return rows;
  }
}

/// One tab of the template: a header with its position and controls, and the
/// panes it opens.
class _TabCard extends StatelessWidget {
  const _TabCard({
    super.key,
    required this.root,
    required this.index,
    required this.isFirst,
    required this.isLast,
    required this.onMoveUp,
    required this.onMoveDown,
    required this.onRemove,
    required this.children,
  });

  final String root;
  final int index;
  final bool isFirst;
  final bool isLast;
  final VoidCallback onMoveUp;
  final VoidCallback onMoveDown;
  final VoidCallback onRemove;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final tokens = ShellVibeTokens.resolve(context);
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(tokens.radiusMedium),
        border: Border.all(color: tokens.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 4, 4, 0),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    'TAB ${index + 1}',
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 1,
                      color: tokens.textSubtle,
                    ),
                  ),
                ),
                ShellVibeIconButton(
                  buttonKey: Key('template_tab_up_$root'),
                  icon: LucideIcons.arrowUp,
                  tooltip: 'Move tab up',
                  onPressed: isFirst ? null : onMoveUp,
                ),
                ShellVibeIconButton(
                  buttonKey: Key('template_tab_down_$root'),
                  icon: LucideIcons.arrowDown,
                  tooltip: 'Move tab down',
                  onPressed: isLast ? null : onMoveDown,
                ),
                ShellVibeIconButton(
                  buttonKey: Key('template_tab_remove_$root'),
                  icon: LucideIcons.trash2,
                  tooltip: 'Remove tab',
                  danger: true,
                  onPressed: onRemove,
                ),
              ],
            ),
          ),
          ...children,
          const SizedBox(height: 4),
        ],
      ),
    );
  }
}

/// A pane of a tab: where it connects, how it is split from its parent, and
/// what can be done to it.
class _PaneRow extends StatelessWidget {
  const _PaneRow({
    super.key,
    required this.pane,
    required this.depth,
    required this.host,
    required this.problem,
    required this.onChangeHost,
    required this.onSplit,
    required this.onToggleDirection,
    required this.onRemove,
  });

  final TemplatePaneModel pane;
  final int depth;
  final HostModel? host;
  final String? problem;
  final VoidCallback onChangeHost;
  final ValueChanged<Axis> onSplit;
  final VoidCallback? onToggleDirection;
  final VoidCallback? onRemove;

  @override
  Widget build(BuildContext context) {
    final tokens = ShellVibeTokens.resolve(context);
    final isLocal = pane.sessionType == TerminalSessionType.local;
    final title = isLocal
        ? (pane.title ?? 'Local Shell')
        : (host?.label ?? 'Missing host');
    final detail = isLocal
        ? 'Local shell'
        : host == null
        ? 'The host this pane used was deleted'
        : '${host!.username == null || host!.username!.isEmpty ? '' : '${host!.username}@'}'
              '${host!.hostname}:${host!.port}';
    final splitIcon = pane.isRoot
        ? LucideIcons.appWindow
        : pane.splitDirection == Axis.vertical
        ? LucideIcons.rows2
        : LucideIcons.columns2;
    final splitLabel = pane.isRoot
        ? 'The tab itself'
        : pane.splitDirection == Axis.vertical
        ? 'Split top and bottom — tap to split side by side'
        : 'Split side by side — tap to split top and bottom';

    return Padding(
      padding: EdgeInsets.only(left: 4.0 + depth * 18, right: 4),
      child: Row(
        children: [
          ShellVibeIconButton(
            buttonKey: Key('template_pane_direction_${pane.id}'),
            icon: splitIcon,
            tooltip: splitLabel,
            onPressed: onToggleDirection,
          ),
          const SizedBox(width: 4),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                    color: problem == null ? tokens.textPrimary : tokens.danger,
                  ),
                ),
                Text(
                  problem ?? detail,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: shellvibeMono(
                    context,
                    size: 10.5,
                    color: problem == null ? tokens.textSubtle : tokens.danger,
                  ),
                ),
              ],
            ),
          ),
          ShellVibeIconButton(
            buttonKey: Key('template_pane_host_${pane.id}'),
            icon: LucideIcons.server,
            tooltip: 'Change host',
            onPressed: onChangeHost,
          ),
          PopupMenuButton<Axis>(
            key: Key('template_pane_split_${pane.id}'),
            tooltip: 'Split this pane',
            icon: Icon(
              LucideIcons.squareSplitHorizontal,
              size: 16,
              color: tokens.textMuted,
            ),
            onSelected: onSplit,
            itemBuilder: (context) => const [
              PopupMenuItem(
                key: Key('template_split_horizontal'),
                value: Axis.horizontal,
                child: Row(
                  children: [
                    Icon(LucideIcons.columns2, size: 16),
                    SizedBox(width: 8),
                    Text('Split side by side'),
                  ],
                ),
              ),
              PopupMenuItem(
                key: Key('template_split_vertical'),
                value: Axis.vertical,
                child: Row(
                  children: [
                    Icon(LucideIcons.rows2, size: 16),
                    SizedBox(width: 8),
                    Text('Split top and bottom'),
                  ],
                ),
              ),
            ],
          ),
          if (onRemove != null)
            ShellVibeIconButton(
              buttonKey: Key('template_pane_remove_${pane.id}'),
              icon: LucideIcons.x,
              tooltip: 'Remove pane',
              danger: true,
              onPressed: onRemove,
            )
          else
            // Keeps the columns of controls aligned with the split rows.
            const SizedBox(width: 40),
        ],
      ),
    );
  }
}

/// Searchable list of what a pane can connect to.
class _TargetPicker extends ConsumerStatefulWidget {
  const _TargetPicker({required this.allowLocal, required this.onPicked});

  final bool allowLocal;
  final ValueChanged<_PaneTarget> onPicked;

  @override
  ConsumerState<_TargetPicker> createState() => _TargetPickerState();
}

class _TargetPickerState extends ConsumerState<_TargetPicker> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final hosts = (ref.watch(hostsProvider).value ?? const <HostModel>[])
        .where((host) => hostMatchesQuery(host, _query))
        .toList();
    final showLocal =
        widget.allowLocal &&
        'local shell'.contains(_query.trim().toLowerCase());

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
          child: ShellVibeSearchField(
            fieldKey: const Key('template_target_search'),
            hintText: 'Search hosts, addresses and protocols…',
            autofocus: !isMobilePlatform,
            onChanged: (value) => setState(() => _query = value),
          ),
        ),
        Flexible(
          child: ListView(
            shrinkWrap: true,
            children: [
              if (showLocal)
                ListTile(
                  key: const Key('template_target_local'),
                  leading: const Icon(LucideIcons.squareTerminal, size: 18),
                  title: const Text('Local shell'),
                  onTap: () => widget.onPicked((hostId: null)),
                ),
              for (final host in hosts)
                ListTile(
                  key: Key('template_target_${host.id}'),
                  leading: const Icon(LucideIcons.server, size: 18),
                  title: Text(host.label),
                  subtitle: Text('${host.hostname}:${host.port}'),
                  onTap: () => widget.onPicked((hostId: host.id)),
                ),
              if (!showLocal && hosts.isEmpty)
                const Padding(
                  padding: EdgeInsets.fromLTRB(24, 8, 24, 24),
                  child: Text(
                    'No hosts match that search.',
                    textAlign: TextAlign.center,
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}
