import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../../../../app/theme/terly_tokens.dart';
import '../../../../app/widgets/terly_ui.dart';
import '../../../settings/presentation/notifiers/settings_notifier.dart';
import '../../../../shared/providers/workspace_provider.dart';
import '../../domain/models/snippet_model.dart';
import '../../domain/services/snippet_variable_parser.dart';
import '../notifiers/snippets_notifier.dart';
import '../widgets/snippet_form_dialog.dart';
import '../widgets/variable_input_dialog.dart';
import 'runbooks_screen.dart';

class SnippetsScreen extends ConsumerStatefulWidget {
  final String? workspaceId;
  final void Function(String command)? onExecuteCommand;

  const SnippetsScreen({super.key, this.workspaceId, this.onExecuteCommand});

  @override
  ConsumerState<SnippetsScreen> createState() => _SnippetsScreenState();
}

class _SnippetsScreenState extends ConsumerState<SnippetsScreen> {
  String _searchQuery = '';
  String? _selectedTag;

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

  @override
  Widget build(BuildContext context) {
    final snippetsAsync = ref.watch(snippetsProvider);
    final String workspaceId =
        widget.workspaceId ?? ref.watch(activeWorkspaceIdProvider);

    return DefaultTabController(
      length: 2,
      child: Scaffold(
        body: Column(
          children: [
            TerlyPageHeader(
              icon: LucideIcons.blocks,
              title: 'Snippets Library',
              description: 'Reusable commands and operational runbooks',
              actions: [
                ShadButton(
                  size: ShadButtonSize.sm,
                  key: const Key('add_snippet_button'),
                  leading: const Icon(LucideIcons.plus, size: 16),
                  onPressed: () async {
                    final newSnippet = await SnippetFormDialog.show(
                      context,
                      workspaceId: workspaceId,
                    );
                    if (newSnippet != null) {
                      ref
                          .read(snippetsProvider.notifier)
                          .addSnippet(
                            workspaceId: newSnippet.workspaceId,
                            title: newSnippet.title,
                            code: newSnippet.code,
                            tags: newSnippet.tags,
                          );
                    }
                  },
                  child: const Text('Add'),
                ),
              ],
            ),
            Container(
              height: 42,
              decoration: BoxDecoration(
                color: TerlyTokens.resolve(context).surface,
                border: Border(
                  bottom: BorderSide(
                    color: TerlyTokens.resolve(context).border,
                  ),
                ),
              ),
              child: const TabBar(
                tabs: [
                  Tab(
                    key: Key('snippets_tab'),
                    icon: Icon(LucideIcons.codeXml, size: 16),
                    text: 'Snippets',
                  ),
                  Tab(
                    key: Key('runbooks_tab'),
                    icon: Icon(LucideIcons.bookOpenText, size: 16),
                    text: 'Runbooks',
                  ),
                ],
              ),
            ),
            Expanded(
              child: TabBarView(
                children: [
                  // Snippets Tab
                  Column(
                    children: [
                      Padding(
                        padding: const EdgeInsets.all(12),
                        child: TerlySearchField(
                          fieldKey: const Key('snippets_search_field'),
                          hintText: 'Search snippets by title, code or tag...',
                          onChanged: (val) {
                            setState(() {
                              _searchQuery = val.trim().toLowerCase();
                            });
                          },
                        ),
                      ),
                      snippetsAsync.when(
                        data: (snippets) {
                          final allTags = <String>{};
                          for (final s in snippets) {
                            allTags.addAll(s.tags);
                          }

                          var filtered = snippets.where((s) {
                            final matchesSearch =
                                _searchQuery.isEmpty ||
                                s.title.toLowerCase().contains(_searchQuery) ||
                                s.code.toLowerCase().contains(_searchQuery) ||
                                s.tags.any(
                                  (t) => t.toLowerCase().contains(_searchQuery),
                                );

                            final matchesTag =
                                _selectedTag == null ||
                                s.tags.contains(_selectedTag);

                            return matchesSearch && matchesTag;
                          }).toList();

                          return Expanded(
                            child: Column(
                              children: [
                                if (allTags.isNotEmpty)
                                  SingleChildScrollView(
                                    scrollDirection: Axis.horizontal,
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 12,
                                    ),
                                    child: Row(
                                      children: [
                                        if (_selectedTag == null)
                                          ShadButton(
                                            size: ShadButtonSize.sm,
                                            onPressed: () => setState(
                                              () => _selectedTag = null,
                                            ),
                                            child: const Text('All'),
                                          )
                                        else
                                          ShadButton.outline(
                                            size: ShadButtonSize.sm,
                                            onPressed: () => setState(
                                              () => _selectedTag = null,
                                            ),
                                            child: const Text('All'),
                                          ),
                                        const SizedBox(width: 6),
                                        ...allTags.map((tag) {
                                          final isSelected =
                                              _selectedTag == tag;
                                          return Padding(
                                            padding: const EdgeInsets.only(
                                              right: 6,
                                            ),
                                            child: isSelected
                                                ? ShadButton(
                                                    size: ShadButtonSize.sm,
                                                    onPressed: () => setState(
                                                      () => _selectedTag = null,
                                                    ),
                                                    child: Text('#$tag'),
                                                  )
                                                : ShadButton.outline(
                                                    size: ShadButtonSize.sm,
                                                    onPressed: () => setState(
                                                      () => _selectedTag = tag,
                                                    ),
                                                    child: Text('#$tag'),
                                                  ),
                                          );
                                        }),
                                      ],
                                    ),
                                  ),
                                const SizedBox(height: 8),
                                Expanded(
                                  child: filtered.isEmpty
                                      ? const TerlyEmptyState(
                                          icon: LucideIcons.codeXml,
                                          title: 'No snippets found.',
                                          description:
                                              'Create a reusable command or adjust your filters.',
                                        )
                                      : ListView.builder(
                                          padding: const EdgeInsets.only(
                                            bottom: 16,
                                          ),
                                          itemCount: filtered.length,
                                          itemBuilder: (context, index) {
                                            final snippet = filtered[index];
                                            final tokens = TerlyTokens.resolve(
                                              context,
                                            );
                                            return Padding(
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                    horizontal: 12,
                                                    vertical: 5,
                                                  ),
                                              child: TerlySurface(
                                                child: ListTile(
                                                  key: Key(
                                                    'snippet_card_${snippet.id}',
                                                  ),
                                                  title: Text(
                                                    snippet.title,
                                                    style: const TextStyle(
                                                      fontWeight:
                                                          FontWeight.w600,
                                                    ),
                                                  ),
                                                  subtitle: Column(
                                                    crossAxisAlignment:
                                                        CrossAxisAlignment
                                                            .start,
                                                    children: [
                                                      const SizedBox(height: 6),
                                                      Container(
                                                        padding:
                                                            const EdgeInsets.all(
                                                              8,
                                                            ),
                                                        decoration: BoxDecoration(
                                                          color: tokens.canvas,
                                                          borderRadius:
                                                              BorderRadius.circular(
                                                                tokens
                                                                    .radiusSmall,
                                                              ),
                                                        ),
                                                        width: double.infinity,
                                                        child: Text(
                                                          snippet.code,
                                                          maxLines: 3,
                                                          overflow: TextOverflow
                                                              .ellipsis,
                                                          style:
                                                              const TextStyle(
                                                                fontFamily:
                                                                    'monospace',
                                                                fontSize: 12,
                                                              ),
                                                        ),
                                                      ),
                                                      if (snippet
                                                          .tags
                                                          .isNotEmpty) ...[
                                                        const SizedBox(
                                                          height: 6,
                                                        ),
                                                        Wrap(
                                                          spacing: 4,
                                                          runSpacing: 4,
                                                          children: snippet.tags
                                                              .map(
                                                                (
                                                                  tag,
                                                                ) => TerlyStatusChip(
                                                                  label:
                                                                      '#$tag',
                                                                ),
                                                              )
                                                              .toList(),
                                                        ),
                                                      ],
                                                    ],
                                                  ),
                                                  trailing: Row(
                                                    mainAxisSize:
                                                        MainAxisSize.min,
                                                    children: [
                                                      IconButton(
                                                        key: Key(
                                                          'snippet_copy_${snippet.id}',
                                                        ),
                                                        icon: const Icon(
                                                          LucideIcons.copy,
                                                          size: 17,
                                                        ),
                                                        tooltip: 'Copy Code',
                                                        onPressed: () =>
                                                            _handleExecuteOrCopy(
                                                              snippet,
                                                              copyOnly: true,
                                                            ),
                                                      ),
                                                      IconButton(
                                                        key: Key(
                                                          'snippet_run_${snippet.id}',
                                                        ),
                                                        icon: Icon(
                                                          LucideIcons.play,
                                                          color: tokens.success,
                                                          size: 18,
                                                        ),
                                                        tooltip:
                                                            'Execute in Terminal',
                                                        onPressed: () =>
                                                            _handleExecuteOrCopy(
                                                              snippet,
                                                            ),
                                                      ),
                                                      PopupMenuButton<String>(
                                                        icon: const Icon(
                                                          LucideIcons.ellipsis,
                                                          size: 18,
                                                        ),
                                                        onSelected: (val) async {
                                                          if (val == 'edit') {
                                                            final updated =
                                                                await SnippetFormDialog.show(
                                                                  context,
                                                                  snippet:
                                                                      snippet,
                                                                  workspaceId:
                                                                      workspaceId,
                                                                );
                                                            if (updated !=
                                                                null) {
                                                              ref
                                                                  .read(
                                                                    snippetsProvider
                                                                        .notifier,
                                                                  )
                                                                  .updateSnippet(
                                                                    updated,
                                                                  );
                                                            }
                                                          } else if (val ==
                                                              'delete') {
                                                            ref
                                                                .read(
                                                                  snippetsProvider
                                                                      .notifier,
                                                                )
                                                                .deleteSnippet(
                                                                  snippet.id,
                                                                );
                                                          }
                                                        },
                                                        itemBuilder:
                                                            (context) => const [
                                                              PopupMenuItem(
                                                                value: 'edit',
                                                                child: Text(
                                                                  'Edit',
                                                                ),
                                                              ),
                                                              PopupMenuItem(
                                                                value: 'delete',
                                                                child: Text(
                                                                  'Delete',
                                                                ),
                                                              ),
                                                            ],
                                                      ),
                                                    ],
                                                  ),
                                                ),
                                              ),
                                            );
                                          },
                                        ),
                                ),
                              ],
                            ),
                          );
                        },
                        loading: () => const Expanded(
                          child: Center(child: CircularProgressIndicator()),
                        ),
                        error: (err, stack) => Expanded(
                          child: TerlyEmptyState(
                            icon: LucideIcons.triangleAlert,
                            title: 'Snippets could not be loaded',
                            description: '$err',
                          ),
                        ),
                      ),
                    ],
                  ),
                  RunbooksScreen(workspaceId: workspaceId),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
