import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../../../../app/theme/terly_tokens.dart';
import '../../../../app/widgets/terly_ui.dart';
import '../../../settings/presentation/notifiers/settings_notifier.dart';
import '../../../../shared/providers/workspace_provider.dart';
import '../../domain/models/snippet_model.dart';
import '../../domain/services/snippet_variable_parser.dart';
import '../notifiers/runbooks_notifier.dart';
import '../notifiers/snippets_notifier.dart';
import '../widgets/runbook_editor_dialog.dart';
import '../widgets/snippet_form_dialog.dart';
import '../widgets/variable_input_dialog.dart';
import 'runbooks_screen.dart';

/// Width at which the module's context column fits alongside the list.
const double _kContextColumnBreakpoint = 900;

/// Width at which the inline detail drawer fits as well.
const double _kDetailDrawerBreakpoint = 1180;

/// Column weights shared by the snippet list header and its rows.
const List<int> _kSnippetColumnFlex = [4, 5, 3];

/// Rendered width of the row's trailing controls.
///
/// Measured, not guessed: the two compact [IconButton]s occupy 34px each and
/// the [PopupMenuButton] 48px once Material's minimum tap target is applied,
/// plus the 12px the popup adds around its icon.
const double _kSnippetActionsWidth = 128;

/// The two halves of the automation library.
///
/// They share one surface — search, filters and the detail drawer keep working
/// the same way — so the switch is navigation inside a module rather than two
/// unrelated screens.
enum AutomationSection { snippets, runbooks }

class SnippetsScreen extends ConsumerStatefulWidget {
  final String? workspaceId;
  final void Function(String command)? onExecuteCommand;
  final AutomationSection initialSection;

  const SnippetsScreen({
    super.key,
    this.workspaceId,
    this.onExecuteCommand,
    this.initialSection = AutomationSection.snippets,
  });

  @override
  ConsumerState<SnippetsScreen> createState() => _SnippetsScreenState();
}

class _SnippetsScreenState extends ConsumerState<SnippetsScreen> {
  late AutomationSection _section = widget.initialSection;
  String _searchQuery = '';
  String? _selectedTag;
  String? _selectedSnippetId;

  String get _workspaceId =>
      widget.workspaceId ?? ref.read(activeWorkspaceIdProvider);

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final showContextColumn =
            constraints.maxWidth >= _kContextColumnBreakpoint;
        final showDetailDrawer =
            constraints.maxWidth >= _kDetailDrawerBreakpoint;

        return Scaffold(
          body: Row(
            children: [
              if (showContextColumn) _buildContextColumn(context),
              Expanded(
                child: _buildWorkArea(
                  context,
                  showContextColumn: showContextColumn,
                  showDetailDrawer: showDetailDrawer,
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  // ── context column ──────────────────────────────────────────────────────

  Widget _buildContextColumn(BuildContext context) {
    final snippets = ref.watch(snippetsProvider).value ?? const <SnippetModel>[];
    final runbookCount = ref.watch(runbooksProvider).value?.length ?? 0;

    return TerlyContextColumn(
      head: _SectionSwitcher(
        section: _section,
        onChanged: _selectSection,
      ),
      search: _buildSearchField(),
      children: switch (_section) {
        AutomationSection.snippets => [
          const TerlySectionLabel(label: 'Tags'),
          TerlyNavItem(
            itemKey: const Key('snippets_filter_all'),
            icon: LucideIcons.layoutGrid,
            label: 'All snippets',
            count: snippets.length,
            selected: _selectedTag == null,
            onTap: () => setState(() => _selectedTag = null),
          ),
          for (final tag in _allTags(snippets))
            TerlyNavItem(
              itemKey: Key('snippets_filter_$tag'),
              icon: LucideIcons.hash,
              label: tag,
              count: snippets.where((s) => s.tags.contains(tag)).length,
              selected: _selectedTag == tag,
              onTap: () => setState(() => _selectedTag = tag),
            ),
        ],
        AutomationSection.runbooks => [
          const TerlySectionLabel(label: 'Library'),
          TerlyNavItem(
            itemKey: const Key('runbooks_filter_all'),
            icon: LucideIcons.listChecks,
            label: 'All runbooks',
            count: runbookCount,
            selected: true,
          ),
        ],
      },
    );
  }

  Widget _buildSearchField() {
    return switch (_section) {
      AutomationSection.snippets => TerlySearchField(
        fieldKey: const Key('snippets_search_field'),
        hintText: 'Search snippets, commands and tags…',
        onChanged: (value) =>
            setState(() => _searchQuery = value.trim().toLowerCase()),
      ),
      AutomationSection.runbooks => TerlySearchField(
        fieldKey: const Key('runbooks_search_field'),
        hintText: 'Search runbooks…',
        onChanged: (value) =>
            setState(() => _searchQuery = value.trim().toLowerCase()),
      ),
    };
  }

  // ── work area ───────────────────────────────────────────────────────────

  Widget _buildWorkArea(
    BuildContext context, {
    required bool showContextColumn,
    required bool showDetailDrawer,
  }) {
    final snippetsAsync = ref.watch(snippetsProvider);
    final runbooksAsync = ref.watch(runbooksProvider);

    final actions = <Widget>[
      switch (_section) {
        AutomationSection.snippets => ShadButton(
          key: const Key('add_snippet_button'),
          size: ShadButtonSize.sm,
          leading: const Icon(LucideIcons.plus, size: 16),
          onPressed: _openSnippetForm,
          child: const Text('Add Snippet'),
        ),
        AutomationSection.runbooks => ShadButton(
          key: const Key('add_runbook_button'),
          size: ShadButtonSize.sm,
          leading: const Icon(LucideIcons.plus, size: 16),
          onPressed: _openRunbookEditor,
          child: const Text('Add Runbook'),
        ),
      },
    ];

    return Column(
      children: [
        if (showContextColumn)
          TerlyWorkToolbar(
            title: switch (_section) {
              AutomationSection.snippets =>
                _selectedTag == null ? 'All snippets' : '#$_selectedTag',
              AutomationSection.runbooks => 'All runbooks',
            },
            meta: switch (_section) {
              AutomationSection.snippets => snippetsAsync.maybeWhen(
                data: (snippets) => '${_visibleSnippets(snippets).length} shown',
                orElse: () => null,
              ),
              AutomationSection.runbooks => runbooksAsync.maybeWhen(
                data: (runbooks) => '${runbooks.length} runbooks',
                orElse: () => null,
              ),
            },
            actions: actions,
          )
        else
          TerlyPageHeader(
            icon: LucideIcons.blocks,
            title: 'Automation Library',
            description: 'Reusable commands and operational runbooks',
            actions: actions,
          ),
        if (!showContextColumn)
          _buildCompactFilterBar(context, snippetsAsync.value ?? const []),
        Expanded(
          child: switch (_section) {
            AutomationSection.snippets => _buildSnippetsSection(
              context,
              snippetsAsync,
              compact: !showContextColumn,
              showDetailDrawer: showDetailDrawer,
            ),
            AutomationSection.runbooks => RunbooksScreen(
              workspaceId: _workspaceId,
              searchQuery: _searchQuery,
              compact: !showContextColumn,
              showDetailDrawer: showDetailDrawer,
            ),
          },
        ),
      ],
    );
  }

  Widget _buildCompactFilterBar(
    BuildContext context,
    List<SnippetModel> snippets,
  ) {
    final tokens = TerlyTokens.resolve(context);
    final tags = _section == AutomationSection.snippets
        ? _allTags(snippets)
        : const <String>[];

    return Container(
      padding: EdgeInsets.fromLTRB(
        tokens.pagePadding,
        10,
        tokens.pagePadding,
        8,
      ),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: tokens.border)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Align(
            alignment: Alignment.centerLeft,
            child: SizedBox(
              width: 260,
              child: _SectionSwitcher(
                section: _section,
                onChanged: _selectSection,
              ),
            ),
          ),
          const SizedBox(height: 8),
          _buildSearchField(),
          if (tags.isNotEmpty) ...[
            const SizedBox(height: 8),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  _FilterChip(
                    label: 'All',
                    selected: _selectedTag == null,
                    onTap: () => setState(() => _selectedTag = null),
                  ),
                  for (final tag in tags)
                    _FilterChip(
                      chipKey: Key('snippets_chip_$tag'),
                      label: '#$tag',
                      selected: _selectedTag == tag,
                      onTap: () => setState(() => _selectedTag = tag),
                    ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  // ── snippets section ────────────────────────────────────────────────────

  Widget _buildSnippetsSection(
    BuildContext context,
    AsyncValue<List<SnippetModel>> snippetsAsync, {
    required bool compact,
    required bool showDetailDrawer,
  }) {
    final tokens = TerlyTokens.resolve(context);

    return snippetsAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, stackTrace) => TerlyEmptyState(
        icon: LucideIcons.triangleAlert,
        title: 'Snippets could not be loaded',
        description: '$error',
      ),
      data: (snippets) {
        if (snippets.isEmpty) {
          return TerlyEmptyState(
            icon: LucideIcons.codeXml,
            title: 'No snippets yet.',
            description:
                'Save a command once and reuse it across every host in this '
                'workspace.',
            actions: [
              ShadButton(
                leading: const Icon(LucideIcons.plus, size: 16),
                onPressed: _openSnippetForm,
                child: const Text('Add snippet'),
              ),
            ],
          );
        }

        final visible = _visibleSnippets(snippets);
        if (visible.isEmpty) {
          return const TerlyEmptyState(
            icon: LucideIcons.searchX,
            title: 'No snippets match your filters.',
            description: 'Try another word, or clear the selected tag.',
          );
        }

        final selected = visible
            .where((snippet) => snippet.id == _selectedSnippetId)
            .firstOrNull;

        return Row(
          children: [
            Expanded(
              child: Column(
                children: [
                  _SnippetListHeader(tokens: tokens, compact: compact),
                  Expanded(
                    child: ListView.builder(
                      itemCount: visible.length,
                      itemBuilder: (context, index) {
                        final snippet = visible[index];
                        return _SnippetRow(
                          key: ValueKey(snippet.id),
                          snippet: snippet,
                          compact: compact,
                          selected: snippet.id == _selectedSnippetId,
                          onSelect: () {
                            setState(() => _selectedSnippetId = snippet.id);
                            // Too narrow for the inline drawer, so the detail
                            // becomes a sheet rather than a selection that
                            // leads nowhere.
                            if (!showDetailDrawer) {
                              _showSnippetDetailSheet(snippet);
                            }
                          },
                          onCopy: () =>
                              _handleExecuteOrCopy(snippet, copyOnly: true),
                          onRun: () => _handleExecuteOrCopy(snippet),
                          onEdit: () => _openSnippetForm(snippet: snippet),
                          onDelete: () => _deleteSnippet(snippet),
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
            if (showDetailDrawer && selected != null)
              TerlyDetailDrawer(
                child: _SnippetDetailPanel(
                  snippet: selected,
                  canRun: widget.onExecuteCommand != null,
                  onCopy: () => _handleExecuteOrCopy(selected, copyOnly: true),
                  onRun: () => _handleExecuteOrCopy(selected),
                  onEdit: () => _openSnippetForm(snippet: selected),
                  onDelete: () => _deleteSnippet(selected),
                  onClose: () => setState(() => _selectedSnippetId = null),
                ),
              ),
          ],
        );
      },
    );
  }

  /// The narrow-width form of the detail drawer.
  void _showSnippetDetailSheet(SnippetModel snippet) {
    final tokens = TerlyTokens.resolve(context);
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      backgroundColor: tokens.surface,
      builder: (sheetContext) => SafeArea(
        child: SizedBox(
          height: MediaQuery.sizeOf(sheetContext).height * 0.72,
          child: _SnippetDetailPanel(
            snippet: snippet,
            canRun: widget.onExecuteCommand != null,
            onCopy: () {
              Navigator.of(sheetContext).pop();
              _handleExecuteOrCopy(snippet, copyOnly: true);
            },
            onRun: () {
              Navigator.of(sheetContext).pop();
              _handleExecuteOrCopy(snippet);
            },
            onEdit: () {
              Navigator.of(sheetContext).pop();
              _openSnippetForm(snippet: snippet);
            },
            onDelete: () {
              Navigator.of(sheetContext).pop();
              _deleteSnippet(snippet);
            },
            onClose: () => Navigator.of(sheetContext).pop(),
          ),
        ),
      ),
    );
  }

  // ── data helpers ────────────────────────────────────────────────────────

  List<String> _allTags(List<SnippetModel> snippets) {
    final tags = <String>{};
    for (final snippet in snippets) {
      tags.addAll(snippet.tags);
    }
    final sorted = tags.toList()..sort();
    return sorted;
  }

  List<SnippetModel> _visibleSnippets(List<SnippetModel> snippets) {
    return snippets.where((snippet) {
      final matchesSearch =
          _searchQuery.isEmpty ||
          snippet.title.toLowerCase().contains(_searchQuery) ||
          snippet.code.toLowerCase().contains(_searchQuery) ||
          snippet.tags.any((tag) => tag.toLowerCase().contains(_searchQuery));
      final matchesTag =
          _selectedTag == null || snippet.tags.contains(_selectedTag);
      return matchesSearch && matchesTag;
    }).toList();
  }

  void _selectSection(AutomationSection section) {
    if (section == _section) return;
    setState(() {
      _section = section;
      // The two sections do not share a filter vocabulary, so carrying the
      // query or the tag across the switch would silently hide rows.
      _searchQuery = '';
      _selectedTag = null;
      _selectedSnippetId = null;
    });
  }

  // ── actions ─────────────────────────────────────────────────────────────

  Future<void> _openSnippetForm({SnippetModel? snippet}) async {
    final workspaceId = _workspaceId;
    final result = await SnippetFormDialog.show(
      context,
      snippet: snippet,
      workspaceId: workspaceId,
    );
    if (!mounted) return;
    if (result == null) return;

    final notifier = ref.read(snippetsProvider.notifier);
    if (snippet == null) {
      await notifier.addSnippet(
        workspaceId: result.workspaceId,
        title: result.title,
        code: result.code,
        tags: result.tags,
      );
    } else {
      await notifier.updateSnippet(result);
    }
  }

  Future<void> _openRunbookEditor() async {
    final workspaceId = _workspaceId;
    final result = await RunbookEditorDialog.show(
      context,
      workspaceId: workspaceId,
    );
    if (!mounted) return;
    if (result == null) return;

    await ref
        .read(runbooksProvider.notifier)
        .addRunbook(
          workspaceId: result.workspaceId,
          title: result.title,
          description: result.description,
          steps: result.steps,
        );
  }

  Future<void> _deleteSnippet(SnippetModel snippet) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => ShadDialog.alert(
        title: const Text('Delete Snippet'),
        description: Text('Are you sure you want to delete "${snippet.title}"?'),
        actions: [
          ShadButton.outline(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          ShadButton.destructive(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirm != true) return;
    if (!mounted) return;

    if (_selectedSnippetId == snippet.id) {
      setState(() => _selectedSnippetId = null);
    }
    await ref.read(snippetsProvider.notifier).deleteSnippet(snippet.id);
  }

  Future<void> _handleExecuteOrCopy(
    SnippetModel snippet, {
    bool copyOnly = false,
  }) async {
    final vars = SnippetVariableParser.extractVariables(snippet.code);
    Map<String, String> values = {};

    if (vars.isNotEmpty) {
      final inputValues = await VariableInputDialog.show(
        context,
        variables: vars,
        title: 'Fill Variables for "${snippet.title}"',
      );
      if (!mounted) return;
      if (inputValues == null) return; // User cancelled
      values = inputValues;
    }

    final finalCode = SnippetVariableParser.substituteVariables(
      snippet.code,
      values,
    );

    if (copyOnly || widget.onExecuteCommand == null) {
      final settings = ref.read(settingsProvider).value;
      final clearSeconds = settings?.clipboardAutoClearSeconds ?? 30;
      final autoClearService = ref.read(clipboardAutoClearServiceProvider);
      await autoClearService.copyAndScheduleClear(
        finalCode,
        duration: Duration(seconds: clearSeconds),
      );
      if (mounted) {
        ShadToaster.of(context).show(
          ShadToast(
            description: Text('Copied snippet "${snippet.title}" to clipboard'),
          ),
        );
      }
    } else {
      widget.onExecuteCommand!(finalCode);
      if (mounted) {
        ShadToaster.of(context).show(
          ShadToast(description: Text('Executed snippet "${snippet.title}"')),
        );
      }
    }
  }
}

/// Segmented navigation between the two halves of the library.
class _SectionSwitcher extends StatelessWidget {
  final AutomationSection section;
  final ValueChanged<AutomationSection> onChanged;

  const _SectionSwitcher({required this.section, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final tokens = TerlyTokens.resolve(context);
    return Container(
      height: 32,
      padding: const EdgeInsets.all(2),
      decoration: BoxDecoration(
        color: tokens.surfaceRaised,
        borderRadius: BorderRadius.circular(tokens.radiusMedium),
        border: Border.all(color: tokens.border),
      ),
      child: Row(
        children: [
          Expanded(
            child: _SectionSegment(
              segmentKey: const Key('automation_section_snippets'),
              icon: LucideIcons.codeXml,
              label: 'Snippets',
              selected: section == AutomationSection.snippets,
              onTap: () => onChanged(AutomationSection.snippets),
            ),
          ),
          Expanded(
            child: _SectionSegment(
              segmentKey: const Key('automation_section_runbooks'),
              icon: LucideIcons.listChecks,
              label: 'Runbooks',
              selected: section == AutomationSection.runbooks,
              onTap: () => onChanged(AutomationSection.runbooks),
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionSegment extends StatelessWidget {
  final Key segmentKey;
  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _SectionSegment({
    required this.segmentKey,
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final tokens = TerlyTokens.resolve(context);
    final foreground = selected ? tokens.textPrimary : tokens.textMuted;
    return Semantics(
      button: true,
      selected: selected,
      child: InkWell(
        key: segmentKey,
        onTap: onTap,
        borderRadius: BorderRadius.circular(tokens.radiusSmall),
        child: Container(
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: selected ? tokens.canvas : Colors.transparent,
            borderRadius: BorderRadius.circular(tokens.radiusSmall),
            border: Border.all(
              color: selected ? tokens.border : Colors.transparent,
            ),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 13, color: foreground),
              const SizedBox(width: 7),
              Flexible(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: foreground,
                    fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Compact-width tag filter, shaped like the one the hosts module uses.
class _FilterChip extends StatelessWidget {
  final Key? chipKey;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _FilterChip({
    this.chipKey,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final tokens = TerlyTokens.resolve(context);
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

class _SnippetListHeader extends StatelessWidget {
  final TerlyTokens tokens;
  final bool compact;

  const _SnippetListHeader({required this.tokens, required this.compact});

  @override
  Widget build(BuildContext context) {
    final style = Theme.of(context).textTheme.labelSmall?.copyWith(
      fontSize: 10,
      letterSpacing: 0.8,
      color: tokens.textMuted,
    );
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: tokens.border)),
      ),
      child: Row(
        children: [
          Expanded(
            flex: _kSnippetColumnFlex[0],
            child: Text('NAME', style: style, maxLines: 1),
          ),
          Expanded(
            flex: _kSnippetColumnFlex[1],
            child: Text('COMMAND', style: style, maxLines: 1),
          ),
          if (!compact)
            Expanded(
              flex: _kSnippetColumnFlex[2],
              child: Text('TAGS', style: style, maxLines: 1),
            ),
          const SizedBox(width: _kSnippetActionsWidth),
        ],
      ),
    );
  }
}

/// Single-line dense snippet row.
class _SnippetRow extends StatelessWidget {
  final SnippetModel snippet;
  final bool compact;
  final bool selected;
  final VoidCallback onSelect;
  final VoidCallback onCopy;
  final VoidCallback onRun;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  const _SnippetRow({
    super.key,
    required this.snippet,
    required this.compact,
    required this.selected,
    required this.onSelect,
    required this.onCopy,
    required this.onRun,
    required this.onEdit,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final tokens = TerlyTokens.resolve(context);
    final monoStyle = Theme.of(context).textTheme.bodySmall?.copyWith(
      color: tokens.textMuted,
      fontFamily: 'monospace',
      fontSize: 12,
    );
    // The list is one line per snippet, so a multi-line body is flattened
    // rather than clipped to its first line.
    final preview = snippet.code.replaceAll(RegExp(r'\s*\n\s*'), ' ; ');

    return Semantics(
      button: true,
      selected: selected,
      label: '${snippet.title}, snippet',
      child: InkWell(
        key: Key('snippet_card_${snippet.id}'),
        onTap: onSelect,
        child: Container(
          padding: const EdgeInsets.fromLTRB(16, 0, 8, 0),
          constraints: const BoxConstraints(minHeight: 42),
          decoration: BoxDecoration(
            color: selected
                ? tokens.textPrimary.withValues(alpha: 0.06)
                : Colors.transparent,
            border: Border(
              bottom: BorderSide(color: tokens.border),
              left: BorderSide(
                color: selected ? tokens.brand : Colors.transparent,
                width: 2,
              ),
            ),
          ),
          child: Row(
            children: [
              Expanded(
                flex: _kSnippetColumnFlex[0],
                child: Text(
                  snippet.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 13,
                  ),
                ),
              ),
              Expanded(
                flex: _kSnippetColumnFlex[1],
                child: Text(
                  preview,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: monoStyle,
                ),
              ),
              if (!compact)
                Expanded(
                  flex: _kSnippetColumnFlex[2],
                  child: snippet.tags.isEmpty
                      ? const SizedBox.shrink()
                      : Align(
                          alignment: Alignment.centerLeft,
                          child: TerlyStatusChip(
                            label: snippet.tags.length == 1
                                ? '#${snippet.tags.first}'
                                : '#${snippet.tags.first} +${snippet.tags.length - 1}',
                          ),
                        ),
                ),
              SizedBox(
                width: _kSnippetActionsWidth,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    IconButton(
                      key: Key('snippet_copy_${snippet.id}'),
                      visualDensity: VisualDensity.compact,
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints.tightFor(
                        width: 34,
                        height: 34,
                      ),
                      icon: const Icon(LucideIcons.copy, size: 16),
                      tooltip: 'Copy command',
                      onPressed: onCopy,
                    ),
                    IconButton(
                      key: Key('snippet_run_${snippet.id}'),
                      visualDensity: VisualDensity.compact,
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints.tightFor(
                        width: 34,
                        height: 34,
                      ),
                      icon: Icon(
                        LucideIcons.play,
                        size: 16,
                        color: tokens.success,
                      ),
                      tooltip: 'Execute in terminal',
                      onPressed: onRun,
                    ),
                    PopupMenuButton<String>(
                      tooltip: 'Snippet actions',
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
                              Text('Edit snippet'),
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
                                'Delete snippet',
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
    );
  }
}

/// Inline right-hand detail panel for a snippet.
class _SnippetDetailPanel extends StatelessWidget {
  final SnippetModel snippet;
  final bool canRun;
  final VoidCallback onCopy;
  final VoidCallback onRun;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  final VoidCallback onClose;

  const _SnippetDetailPanel({
    required this.snippet,
    required this.canRun,
    required this.onCopy,
    required this.onRun,
    required this.onEdit,
    required this.onDelete,
    required this.onClose,
  });

  @override
  Widget build(BuildContext context) {
    final tokens = TerlyTokens.resolve(context);
    final variables = SnippetVariableParser.extractVariables(snippet.code);
    final lineCount = '\n'.allMatches(snippet.code).length + 1;

    return ListView(
      key: const Key('snippet_detail_drawer'),
      padding: const EdgeInsets.all(14),
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Text(
                snippet.title,
                style: Theme.of(
                  context,
                ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600),
              ),
            ),
            IconButton(
              visualDensity: VisualDensity.compact,
              icon: const Icon(LucideIcons.x, size: 15),
              tooltip: 'Close details',
              onPressed: onClose,
            ),
          ],
        ),
        if (snippet.tags.isNotEmpty) ...[
          const SizedBox(height: 6),
          Wrap(
            spacing: 4,
            runSpacing: 4,
            children: [
              for (final tag in snippet.tags) TerlyStatusChip(label: '#$tag'),
            ],
          ),
        ],
        const SizedBox(height: 12),
        ShadButton(
          key: const Key('snippet_detail_run'),
          width: double.infinity,
          leading: const Icon(LucideIcons.play, size: 16),
          onPressed: canRun ? onRun : onCopy,
          // Without a terminal to run in, the primary action is the one that
          // actually happens rather than a button that silently copies.
          child: Text(canRun ? 'Run in terminal' : 'Copy command'),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: ShadButton.outline(
                key: const Key('snippet_detail_copy'),
                size: ShadButtonSize.sm,
                onPressed: onCopy,
                child: const Text('Copy'),
              ),
            ),
            const SizedBox(width: 6),
            Expanded(
              child: ShadButton.outline(
                key: const Key('snippet_detail_edit'),
                size: ShadButtonSize.sm,
                onPressed: onEdit,
                child: const Text('Edit'),
              ),
            ),
          ],
        ),
        const SizedBox(height: 14),
        const TerlySectionLabel(label: 'Command', padding: EdgeInsets.zero),
        const SizedBox(height: 6),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: tokens.canvas,
            borderRadius: BorderRadius.circular(tokens.radiusSmall),
            border: Border.all(color: tokens.border),
          ),
          child: SelectableText(
            snippet.code,
            style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
          ),
        ),
        const SizedBox(height: 14),
        _DetailRow(label: 'lines', value: '$lineCount'),
        _DetailRow(
          label: 'variables',
          value: variables.isEmpty ? 'none' : variables.join(', '),
        ),
        _DetailRow(
          label: 'tags',
          value: snippet.tags.isEmpty ? 'none' : '${snippet.tags.length}',
        ),
        const SizedBox(height: 14),
        ShadButton.destructive(
          key: const Key('snippet_detail_delete'),
          size: ShadButtonSize.sm,
          width: double.infinity,
          onPressed: onDelete,
          child: const Text('Delete snippet'),
        ),
      ],
    );
  }
}

class _DetailRow extends StatelessWidget {
  final String label;
  final String value;

  const _DetailRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    final tokens = TerlyTokens.resolve(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 78,
            child: Text(
              label.toUpperCase(),
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                fontSize: 9,
                letterSpacing: 0.8,
                color: tokens.textMuted,
              ),
            ),
          ),
          Expanded(
            child: Text(value, style: Theme.of(context).textTheme.bodySmall),
          ),
        ],
      ),
    );
  }
}
