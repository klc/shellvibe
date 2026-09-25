import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../../../../app/theme/shellvibe_tokens.dart';
import '../../../../app/widgets/shellvibe_ui.dart';
import '../../../../core/utils/platform_capabilities.dart';
import '../../../bookmarks/presentation/notifiers/bookmarks_notifier.dart';
import '../../../hosts/domain/models/host_model.dart';
import '../../../hosts/presentation/notifiers/hosts_notifier.dart';
import '../../../templates/domain/models/template_model.dart';
import '../../../templates/presentation/notifiers/templates_notifier.dart';

/// Host picker shown by the "Connect to Host" panel.
///
/// Stateful for the query alone: the list it filters is long enough on a real
/// workspace that scrolling it is the slow way to reach a host, and typing is
/// the fast one.
class SelectHostPanel extends ConsumerStatefulWidget {
  final Future<void> Function(HostModel host) onSelected;

  /// Lists saved templates under the hosts when set.
  final ValueChanged<TemplateModel>? onTemplateSelected;

  const SelectHostPanel({
    super.key,
    required this.onSelected,
    this.onTemplateSelected,
  });

  @override
  ConsumerState<SelectHostPanel> createState() => _SelectHostPanelState();
}

class _SelectHostPanelState extends ConsumerState<SelectHostPanel> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final tokens = ShellVibeTokens.resolve(context);
    final hostsAsync = ref.watch(hostsProvider);

    final allTemplates = widget.onTemplateSelected == null
        ? const <TemplateModel>[]
        : ref.watch(templatesProvider).value ?? const <TemplateModel>[];

    return hostsAsync.when(
      data: (hosts) {
        if (hosts.isEmpty && allTemplates.isEmpty) {
          return const Padding(
            padding: EdgeInsets.all(24.0),
            child: Center(child: Text('No hosts available. Create one first.')),
          );
        }

        // Starred hosts lead, in the order they were starred, exactly as they
        // do in the ⌘K palette: a picker and a palette that disagree about
        // where a favourite sits are two things to learn instead of one.
        final bookmarkedIds = [
          for (final bookmark in ref.watch(bookmarksProvider).value ?? const [])
            if (bookmark.hostId != null) bookmark.hostId!,
        ];
        final favorites = [
          for (final id in bookmarkedIds) ...hosts.where((h) => h.id == id),
        ].where((host) => hostMatchesQuery(host, _query)).toList();
        final others = hosts
            .where((host) => !bookmarkedIds.contains(host.id))
            .where((host) => hostMatchesQuery(host, _query))
            .toList();
        final templates = allTemplates
            .where((template) => templateMatchesQuery(template, _query))
            .toList();

        Widget row(HostModel host, {required bool favorite}) {
          return ListTile(
            key: Key('select_host_row_${host.id}'),
            leading: Icon(
              favorite ? LucideIcons.star : LucideIcons.server,
              size: 18,
              color: favorite ? tokens.brand : null,
            ),
            title: Text(host.label),
            subtitle: Text('${host.hostname}:${host.port}'),
            onTap: () => widget.onSelected(host),
          );
        }

        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
              child: ShellVibeSearchField(
                fieldKey: const Key('select_host_search_input'),
                hintText: 'Search hosts, addresses and protocols…',
                // On a phone this panel is a sheet, and a keyboard raised over
                // the list on open hides the very rows it filters.
                autofocus: !isMobilePlatform,
                onChanged: (value) => setState(() => _query = value),
              ),
            ),
            Flexible(
              child: favorites.isEmpty && others.isEmpty && templates.isEmpty
                  ? Padding(
                      padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
                      child: Text(
                        'No hosts match that search.',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: tokens.textSubtle),
                      ),
                    )
                  : ListView(
                      shrinkWrap: true,
                      children: [
                        // The headings only appear once there is something to
                        // separate: with nothing starred the list is the plain
                        // one it was.
                        if (favorites.isNotEmpty) ...[
                          const ShellVibeSectionLabel(
                            label: 'Favorites',
                            padding: EdgeInsets.fromLTRB(16, 8, 16, 4),
                          ),
                          for (final host in favorites)
                            row(host, favorite: true),
                          if (others.isNotEmpty)
                            const ShellVibeSectionLabel(
                              label: 'All hosts',
                              padding: EdgeInsets.fromLTRB(16, 12, 16, 4),
                            ),
                        ],
                        for (final host in others) row(host, favorite: false),
                        // After the hosts rather than among them: a template
                        // opens several tabs, which is a bigger step than the
                        // one this panel is mostly used for.
                        if (templates.isNotEmpty) ...[
                          const ShellVibeSectionLabel(
                            label: 'Templates',
                            padding: EdgeInsets.fromLTRB(16, 12, 16, 4),
                          ),
                          for (final template in templates)
                            ListTile(
                              key: Key('select_template_row_${template.id}'),
                              leading: const Icon(
                                LucideIcons.layoutTemplate,
                                size: 18,
                              ),
                              title: Text(template.name),
                              subtitle: Text(templateSummary(template)),
                              onTap: () =>
                                  widget.onTemplateSelected?.call(template),
                            ),
                        ],
                      ],
                    ),
            ),
          ],
        );
      },
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, s) => Center(child: Text('Error loading hosts: $e')),
    );
  }
}
