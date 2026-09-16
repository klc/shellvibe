import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../../../../app/theme/shellvibe_tokens.dart';
import '../../../../app/widgets/adaptive_modal.dart';
import '../../../../app/widgets/shellvibe_ui.dart';
import '../../domain/models/snippet_model.dart';
import '../notifiers/snippets_notifier.dart';

/// Panel listing the workspace's snippets. Picking one sends it.
///
/// This replaces the permanent strip that used to sit under the panes: a
/// snippet is something the user reaches for occasionally, and paying for it
/// with terminal rows on every session was the wrong trade. It is reached by
/// keyboard (⌘⇧S / Ctrl+Shift+S) or from the pane's context menu, and mirrors
/// the template picker so "run a template" and "send a snippet" are picked the
/// same way.
class SnippetPickerSheet extends ConsumerStatefulWidget {
  /// Named so the sheet can say where the snippet is about to land — the one
  /// thing the old always-visible strip told the user for free.
  final String targetLabel;
  final Future<void> Function(SnippetModel snippet) onSelect;

  const SnippetPickerSheet({
    super.key,
    required this.targetLabel,
    required this.onSelect,
  });

  static void show(
    BuildContext context, {
    required String targetLabel,
    required Future<void> Function(SnippetModel snippet) onSelect,
  }) {
    showAdaptivePanel<void>(
      context: context,
      title: 'Send Snippet',
      desktopHeight: 460,
      builder: (ctx) =>
          SnippetPickerSheet(targetLabel: targetLabel, onSelect: onSelect),
    );
  }

  @override
  ConsumerState<SnippetPickerSheet> createState() => _SnippetPickerSheetState();
}

class _SnippetPickerSheetState extends ConsumerState<SnippetPickerSheet> {
  final _searchController = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  List<SnippetModel> _filter(List<SnippetModel> snippets) {
    final query = _query.trim().toLowerCase();
    if (query.isEmpty) return snippets;
    return snippets.where((snippet) {
      return snippet.title.toLowerCase().contains(query) ||
          snippet.code.toLowerCase().contains(query) ||
          snippet.tags.any((tag) => tag.toLowerCase().contains(query));
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final tokens = ShellVibeTokens.resolve(context);
    final snippetsAsync = ref.watch(snippetsProvider);

    return snippetsAsync.when(
      loading: () => const Padding(
        padding: EdgeInsets.all(24),
        child: Center(child: CircularProgressIndicator()),
      ),
      error: (e, s) => Padding(
        padding: const EdgeInsets.all(24),
        child: Center(child: Text('Error loading snippets: $e')),
      ),
      data: (snippets) {
        if (snippets.isEmpty) {
          return const Padding(
            padding: EdgeInsets.all(24),
            child: Center(
              child: Text(
                'No snippets yet. Save a command in the Automation Library '
                'and it will show up here.',
                textAlign: TextAlign.center,
              ),
            ),
          );
        }

        final visible = _filter(snippets);

        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    widget.targetLabel.toUpperCase(),
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      fontSize: 10,
                      letterSpacing: 0.8,
                      color: tokens.textMuted,
                    ),
                  ),
                  const SizedBox(height: 8),
                  ShadInput(
                    key: const Key('snippet_picker_search'),
                    controller: _searchController,
                    autofocus: true,
                    placeholder: const Text('Search snippets…'),
                    onChanged: (value) => setState(() => _query = value),
                  ),
                ],
              ),
            ),
            if (visible.isEmpty)
              const Padding(
                padding: EdgeInsets.all(24),
                child: Center(child: Text('No snippets match that search.')),
              )
            else
              Flexible(
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: visible.length,
                  itemBuilder: (context, index) {
                    final snippet = visible[index];
                    final firstLine = snippet.code.split('\n').first.trim();
                    return ListTile(
                      key: Key('snippet_picker_${snippet.id}'),
                      leading: const Icon(LucideIcons.codeXml, size: 18),
                      title: Text(snippet.title),
                      subtitle: Text(
                        firstLine.isEmpty ? snippet.code : firstLine,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: shellvibeMono(
                          context,
                          size: 11,
                          color: tokens.textSubtle,
                        ),
                      ),
                      onTap: () async {
                        Navigator.of(context).pop();
                        await widget.onSelect(snippet);
                      },
                    );
                  },
                ),
              ),
          ],
        );
      },
    );
  }
}
