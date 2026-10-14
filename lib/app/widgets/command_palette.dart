import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../../features/bookmarks/presentation/notifiers/bookmarks_notifier.dart';
import '../../features/hosts/domain/models/host_model.dart';
import '../../features/hosts/presentation/notifiers/hosts_notifier.dart';
import '../../features/templates/domain/models/template_model.dart';
import '../../features/templates/presentation/notifiers/templates_notifier.dart';
import '../../features/tunnels/presentation/tunnel_availability.dart';
import '../keyboard/app_keymap.dart';
import '../theme/shellvibe_tokens.dart';
import 'app_navigation_shell.dart';
import 'shellvibe_ui.dart';

/// The jump-to dialog: bookmarks, hosts, templates and modules behind one
/// query line. Shown by the navigation shell; the callbacks are what it does
/// with a pick, since the dialog has no router of its own to go through.
class CommandPalette extends ConsumerStatefulWidget {
  final ValueChanged<int> onSelected;
  final ValueChanged<HostModel> onHostSelected;
  final ValueChanged<TemplateModel> onTemplateSelected;
  final VoidCallback onShowShortcuts;

  const CommandPalette({
    super.key,
    required this.onSelected,
    required this.onHostSelected,
    required this.onTemplateSelected,
    required this.onShowShortcuts,
  });

  @override
  ConsumerState<CommandPalette> createState() => _CommandPaletteState();
}

/// One runnable result in the command palette.
class _PaletteEntry {
  final Key? key;
  final IconData icon;
  final String label;
  final String detail;
  final String trailing;
  final VoidCallback onRun;

  const _PaletteEntry({
    this.key,
    required this.icon,
    required this.label,
    required this.detail,
    this.trailing = '',
    required this.onRun,
  });
}

class _CommandPaletteState extends ConsumerState<CommandPalette> {
  String query = '';

  /// Position, across every section, of the row Enter runs.
  int _selected = 0;

  /// One key per result position, so the arrow keys can scroll the selected
  /// row into view. Indexed by position rather than by entry: a row is found
  /// by where it sits, and the list is rebuilt on every keystroke anyway.
  final _rowKeys = <GlobalKey>[];

  GlobalKey _rowKey(int index) {
    while (_rowKeys.length <= index) {
      _rowKeys.add(GlobalKey());
    }
    return _rowKeys[index];
  }

  void _moveSelection(int delta, int count) {
    if (count == 0) return;
    setState(() => _selected = (_selected + delta).clamp(0, count - 1));
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final rowContext = _rowKeys[_selected].currentContext;
      if (rowContext == null || !rowContext.mounted) return;
      Scrollable.ensureVisible(
        rowContext,
        alignmentPolicy: delta > 0
            ? ScrollPositionAlignmentPolicy.keepVisibleAtEnd
            : ScrollPositionAlignmentPolicy.keepVisibleAtStart,
      );
    });
  }

  /// The non-empty sections matching [value] (the lower-cased query), in the
  /// order they are listed.
  List<(String, List<_PaletteEntry>)> _buildSections(
    BuildContext context,
    String value,
  ) {
    final tunnelsSupported = tunnelsSupportedFor(context);
    final filtered = appNavigationItems.indexed.where((entry) {
      final item = entry.$2;
      if (item.path == '/tunnels' && !tunnelsSupported) return false;
      return item.label.toLowerCase().contains(value) ||
          item.description.toLowerCase().contains(value);
    }).toList();

    // The palette is what makes a bookmark reachable from anywhere; without it
    // a starred host is only a filter on one screen. Bookmarks lead, then the
    // rest of the hosts, then the modules the palette started out listing.
    final hosts = ref.watch(hostsProvider).value ?? const <HostModel>[];
    final templates =
        ref.watch(templatesProvider).value ?? const <TemplateModel>[];
    final bookmarks = ref.watch(bookmarksProvider).value ?? const [];

    final bookmarkedHostIds = bookmarks
        .where((bookmark) => bookmark.hostId != null)
        .map((bookmark) => bookmark.hostId!)
        .toList();
    final bookmarkedTemplateIds = bookmarks
        .where((bookmark) => bookmark.templateId != null)
        .map((bookmark) => bookmark.templateId!)
        .toList();

    // Ordered by the bookmark list, not by the host list: a bookmark bar is
    // arranged by the person who made it.
    final bookmarkedHosts = [
      for (final id in bookmarkedHostIds)
        ...hosts.where((host) => host.id == id),
    ].where((host) => hostMatchesQuery(host, value)).toList();
    final bookmarkedTemplates = [
      for (final id in bookmarkedTemplateIds)
        ...templates.where((template) => template.id == id),
    ].where((template) => templateMatchesQuery(template, value)).toList();

    final otherHosts = hosts
        .where((host) => !bookmarkedHostIds.contains(host.id))
        .where((host) => hostMatchesQuery(host, value))
        .toList();
    // A template is a way in to several hosts at once, so it is found the
    // same way a host is, starred or not.
    final otherTemplates = templates
        .where((template) => !bookmarkedTemplateIds.contains(template.id))
        .where((template) => templateMatchesQuery(template, value))
        .toList();

    _PaletteEntry hostEntry(
      HostModel host, {
      required String keyPrefix,
      required IconData icon,
    }) => _PaletteEntry(
      key: Key('${keyPrefix}_${host.id}'),
      icon: icon,
      label: host.label,
      detail: host.hostname,
      trailing: host.protocol,
      onRun: () => widget.onHostSelected(host),
    );
    _PaletteEntry templateEntry(
      TemplateModel template, {
      required String keyPrefix,
    }) => _PaletteEntry(
      key: Key('${keyPrefix}_${template.id}'),
      icon: LucideIcons.layoutTemplate,
      label: template.name,
      detail: templateSummary(template),
      onRun: () => widget.onTemplateSelected(template),
    );

    return <(String, List<_PaletteEntry>)>[
      (
        'Bookmarks',
        [
          for (final host in bookmarkedHosts)
            hostEntry(
              host,
              keyPrefix: 'palette_bookmark',
              icon: LucideIcons.star,
            ),
          for (final template in bookmarkedTemplates)
            templateEntry(template, keyPrefix: 'palette_bookmark'),
        ],
      ),
      (
        'Hosts',
        [
          for (final host in otherHosts)
            hostEntry(
              host,
              keyPrefix: 'palette_host',
              icon: LucideIcons.server,
            ),
        ],
      ),
      (
        'Templates',
        [
          for (final template in otherTemplates)
            templateEntry(template, keyPrefix: 'palette_template'),
        ],
      ),
      (
        'Modules',
        [
          for (final (index, item) in filtered)
            _PaletteEntry(
              icon: item.icon,
              label: item.label,
              detail: item.description,
              trailing: item.shortcut,
              onRun: () => widget.onSelected(index),
            ),
        ],
      ),
      (
        'Help',
        [
          // The palette is where someone who does not know a key goes looking
          // for one, so the list of them is a row here.
          if ('keyboard shortcuts keys'.contains(value))
            _PaletteEntry(
              key: const Key('palette_keyboard_shortcuts'),
              icon: LucideIcons.keyboard,
              label: 'Keyboard Shortcuts',
              detail: 'Every shortcut on this keyboard',
              onRun: widget.onShowShortcuts,
            ),
        ],
      ),
    ].where((section) => section.$2.isNotEmpty).toList();
  }

  @override
  Widget build(BuildContext context) {
    final tokens = ShellVibeTokens.resolve(context);
    final sections = _buildSections(context, query.toLowerCase());

    // The selection runs across the sections rather than within one, so Enter
    // and the arrow keys see a single list.
    final entries = [for (final (_, rows) in sections) ...rows];
    final selected = entries.isEmpty
        ? -1
        : _selected.clamp(0, entries.length - 1);

    final results = <Widget>[];
    var position = 0;
    for (final (label, rows) in sections) {
      results.add(
        ShellVibeSectionLabel(
          label: label,
          padding: const EdgeInsets.fromLTRB(10, 8, 10, 6),
        ),
      );
      for (final entry in rows) {
        final index = position++;
        results.add(
          KeyedSubtree(
            key: _rowKey(index),
            child: _PaletteRow(
              key: entry.key,
              icon: entry.icon,
              label: entry.label,
              detail: entry.detail,
              trailing: entry.trailing,
              highlighted: index == selected,
              onTap: entry.onRun,
            ),
          ),
        );
      }
    }

    // Pinned near the top rather than centred: the palette is a jump target,
    // and the eye should land on the query line, not the middle of the screen.
    return Dialog(
      alignment: const Alignment(0, -0.7),
      insetPadding: const EdgeInsets.all(20),
      backgroundColor: Colors.transparent,
      elevation: 0,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 660, maxHeight: 620),
        child: ShellVibeOverlaySurface(
          gradientExtent: 200,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
                decoration: BoxDecoration(
                  border: Border(
                    bottom: BorderSide(
                      color: tokens.textPrimary.withValues(alpha: 0.06),
                    ),
                  ),
                ),
                child: Row(
                  children: [
                    Icon(LucideIcons.search, size: 18, color: tokens.brand),
                    const SizedBox(width: 12),
                    Expanded(
                      // Bound above the field, which leaves the arrow keys to
                      // its own caret movement otherwise. A single-line query
                      // has no line above or below to move to.
                      child: CallbackShortcuts(
                        bindings: {
                          const SingleActivator(
                            LogicalKeyboardKey.arrowDown,
                          ): () =>
                              _moveSelection(1, entries.length),
                          const SingleActivator(
                            LogicalKeyboardKey.arrowUp,
                          ): () =>
                              _moveSelection(-1, entries.length),
                        },
                        child: TextField(
                          key: const Key('command_palette_search'),
                          autofocus: true,
                          cursorColor: tokens.brand,
                          cursorWidth: 2,
                          style: TextStyle(
                            fontSize: 16,
                            color: tokens.textPrimary,
                          ),
                          decoration: InputDecoration(
                            isDense: true,
                            filled: false,
                            border: InputBorder.none,
                            enabledBorder: InputBorder.none,
                            focusedBorder: InputBorder.none,
                            contentPadding: EdgeInsets.zero,
                            hintText:
                                'Search hosts, sessions, files and tools…',
                            hintStyle: TextStyle(
                              fontSize: 16,
                              color: tokens.textSubtle,
                            ),
                          ),
                          onChanged: (value) => setState(() {
                            query = value;
                            _selected = 0;
                          }),
                          // Non-null so Enter with nothing to run keeps the
                          // focus in the query instead of dropping it.
                          onEditingComplete: () {},
                          onSubmitted: (_) {
                            if (selected >= 0) entries[selected].onRun();
                          },
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    const _PaletteKeyCap(label: 'esc'),
                  ],
                ),
              ),
              Flexible(
                child: ListView(
                  shrinkWrap: true,
                  padding: const EdgeInsets.fromLTRB(10, 10, 10, 12),
                  children: results,
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 18,
                  vertical: 11,
                ),
                decoration: BoxDecoration(
                  color: tokens.textPrimary.withValues(alpha: 0.025),
                  border: Border(
                    top: BorderSide(
                      color: tokens.textPrimary.withValues(alpha: 0.06),
                    ),
                  ),
                ),
                child: DefaultTextStyle.merge(
                  style: shellvibeMono(
                    context,
                    size: 10.5,
                    color: tokens.textSubtle,
                  ),
                  child: Row(
                    children: [
                      const Text('↑↓ move'),
                      const SizedBox(width: 18),
                      const Text('↵ run'),
                      const Spacer(),
                      Text(shortcutLabel(AppCommand.commandPalette)!),
                    ],
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

/// One 44px result row in the command palette.
class _PaletteRow extends StatelessWidget {
  final IconData icon;
  final String label;

  /// The mono line after the label: what the row is, or where it points.
  final String detail;

  /// Right-aligned hint shown when the row is not the one Enter would run.
  final String trailing;
  final bool highlighted;
  final VoidCallback onTap;

  const _PaletteRow({
    super.key,
    required this.icon,
    required this.label,
    required this.detail,
    this.trailing = '',
    required this.highlighted,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final tokens = ShellVibeTokens.resolve(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          height: 44,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            color: highlighted
                ? tokens.brand.withValues(alpha: 0.12)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: highlighted
                  ? tokens.brand.withValues(alpha: 0.22)
                  : Colors.transparent,
            ),
          ),
          child: Row(
            children: [
              Icon(
                icon,
                size: 16,
                color: highlighted ? tokens.brandBright : tokens.textMuted,
              ),
              const SizedBox(width: 12),
              // The label keeps its full width up to a cap and the detail gets
              // whatever is left; a long host name truncates rather than
              // pushing the row past its edge.
              Expanded(
                child: LayoutBuilder(
                  builder: (context, constraints) => Row(
                    children: [
                      ConstrainedBox(
                        constraints: BoxConstraints(
                          maxWidth: constraints.maxWidth * 0.6,
                        ),
                        child: Text(
                          label,
                          maxLines: 1,
                          softWrap: false,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: highlighted
                                ? tokens.textPrimary
                                : tokens.textSecondary,
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          detail,
                          maxLines: 1,
                          softWrap: false,
                          overflow: TextOverflow.ellipsis,
                          style: shellvibeMono(context, size: 11),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 12),
              if (highlighted) ...[
                Text(
                  'open',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: tokens.brand,
                  ),
                ),
                const SizedBox(width: 10),
                const _PaletteKeyCap(label: '↵', brand: true),
              ] else
                Text(trailing, style: shellvibeMono(context, size: 11)),
            ],
          ),
        ),
      ),
    );
  }
}

/// The small mono key hint used in the palette's query row and result rows.
class _PaletteKeyCap extends StatelessWidget {
  final String label;
  final bool brand;

  const _PaletteKeyCap({required this.label, this.brand = false});

  @override
  Widget build(BuildContext context) {
    final tokens = ShellVibeTokens.resolve(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: brand
            ? tokens.brand.withValues(alpha: 0.18)
            : tokens.textPrimary.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        label,
        style: shellvibeMono(
          context,
          size: 10,
          color: brand ? tokens.brandSoft : tokens.textMuted,
        ),
      ),
    );
  }
}
