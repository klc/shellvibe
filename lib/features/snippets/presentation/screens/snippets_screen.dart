import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/models/snippet_model.dart';
import '../../domain/services/snippet_variable_parser.dart';
import '../notifiers/snippets_notifier.dart';
import '../widgets/snippet_form_dialog.dart';
import '../widgets/variable_input_dialog.dart';
import 'runbooks_screen.dart';

class SnippetsScreen extends ConsumerStatefulWidget {
  final String workspaceId;
  final void Function(String command)? onExecuteCommand;

  const SnippetsScreen({
    super.key,
    this.workspaceId = 'default',
    this.onExecuteCommand,
  });

  @override
  ConsumerState<SnippetsScreen> createState() => _SnippetsScreenState();
}

class _SnippetsScreenState extends ConsumerState<SnippetsScreen> {
  String _searchQuery = '';
  String? _selectedTag;

  Future<void> _handleExecuteOrCopy(SnippetModel snippet, {bool copyOnly = false}) async {
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

    final finalCode = SnippetVariableParser.substituteVariables(snippet.code, values);

    if (copyOnly || widget.onExecuteCommand == null) {
      await Clipboard.setData(ClipboardData(text: finalCode));
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Copied snippet to clipboard: "$finalCode"')),
        );
      }
    } else {
      widget.onExecuteCommand!(finalCode);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Executed snippet: "$finalCode"')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final snippetsAsync = ref.watch(snippetsNotifierProvider);

    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Snippets Library'),
          bottom: const TabBar(
            tabs: [
              Tab(key: Key('snippets_tab'), icon: Icon(Icons.code), text: 'Snippets'),
              Tab(key: Key('runbooks_tab'), icon: Icon(Icons.menu_book), text: 'Runbooks'),
            ],
          ),
          actions: [
            IconButton(
              key: const Key('add_snippet_button'),
              icon: const Icon(Icons.add),
              tooltip: 'New Snippet',
              onPressed: () async {
                final newSnippet = await SnippetFormDialog.show(
                  context,
                  workspaceId: widget.workspaceId,
                );
                if (newSnippet != null) {
                  ref.read(snippetsNotifierProvider.notifier).addSnippet(
                        workspaceId: newSnippet.workspaceId,
                        title: newSnippet.title,
                        code: newSnippet.code,
                        tags: newSnippet.tags,
                      );
                }
              },
            ),
          ],
        ),
        body: TabBarView(
          children: [
            // Snippets Tab
            Column(
              children: [
                Padding(
                  padding: const EdgeInsets.all(12.0),
                  child: TextField(
                    key: const Key('snippets_search_field'),
                    decoration: const InputDecoration(
                      hintText: 'Search snippets by title, code or tag...',
                      prefixIcon: Icon(Icons.search),
                      border: OutlineInputBorder(),
                    ),
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
                      final matchesSearch = _searchQuery.isEmpty ||
                          s.title.toLowerCase().contains(_searchQuery) ||
                          s.code.toLowerCase().contains(_searchQuery) ||
                          s.tags.any((t) => t.toLowerCase().contains(_searchQuery));

                      final matchesTag = _selectedTag == null || s.tags.contains(_selectedTag);

                      return matchesSearch && matchesTag;
                    }).toList();

                    return Expanded(
                      child: Column(
                        children: [
                          if (allTags.isNotEmpty)
                            SingleChildScrollView(
                              scrollDirection: Axis.horizontal,
                              padding: const EdgeInsets.symmetric(horizontal: 12.0),
                              child: Row(
                                children: [
                                  FilterChip(
                                    label: const Text('All'),
                                    selected: _selectedTag == null,
                                    onSelected: (_) => setState(() => _selectedTag = null),
                                  ),
                                  const SizedBox(width: 6),
                                  ...allTags.map((tag) => Padding(
                                        padding: const EdgeInsets.only(right: 6.0),
                                        child: FilterChip(
                                          label: Text('#$tag'),
                                          selected: _selectedTag == tag,
                                          onSelected: (selected) {
                                            setState(() {
                                              _selectedTag = selected ? tag : null;
                                            });
                                          },
                                        ),
                                      )),
                                ],
                              ),
                            ),
                          const SizedBox(height: 8),
                          Expanded(
                            child: filtered.isEmpty
                                ? const Center(
                                    child: Text('No snippets found.'),
                                  )
                                : ListView.builder(
                                    itemCount: filtered.length,
                                    itemBuilder: (context, index) {
                                      final snippet = filtered[index];
                                      return Card(
                                        margin:
                                            const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                        child: ListTile(
                                          key: Key('snippet_card_${snippet.id}'),
                                          title: Text(
                                            snippet.title,
                                            style: const TextStyle(fontWeight: FontWeight.bold),
                                          ),
                                          subtitle: Column(
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            children: [
                                              const SizedBox(height: 4),
                                              Container(
                                                padding: const EdgeInsets.all(8),
                                                decoration: BoxDecoration(
                                                  color: Colors.black26,
                                                  borderRadius: BorderRadius.circular(4),
                                                ),
                                                width: double.infinity,
                                                child: Text(
                                                  snippet.code,
                                                  style: const TextStyle(
                                                    fontFamily: 'monospace',
                                                    fontSize: 12,
                                                  ),
                                                ),
                                              ),
                                              if (snippet.tags.isNotEmpty) ...[
                                                const SizedBox(height: 6),
                                                Wrap(
                                                  spacing: 4,
                                                  children: snippet.tags
                                                      .map((t) => Chip(
                                                            label: Text('#$t',
                                                                style: const TextStyle(fontSize: 10)),
                                                            padding: EdgeInsets.zero,
                                                            materialTapTargetSize:
                                                                MaterialTapTargetSize.shrinkWrap,
                                                          ))
                                                      .toList(),
                                                ),
                                              ],
                                            ],
                                          ),
                                          trailing: Row(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              IconButton(
                                                key: Key('snippet_copy_${snippet.id}'),
                                                icon: const Icon(Icons.copy, size: 20),
                                                tooltip: 'Copy Code',
                                                onPressed: () =>
                                                    _handleExecuteOrCopy(snippet, copyOnly: true),
                                              ),
                                              IconButton(
                                                key: Key('snippet_run_${snippet.id}'),
                                                icon: const Icon(Icons.play_arrow,
                                                    color: Colors.green, size: 22),
                                                tooltip: 'Execute in Terminal',
                                                onPressed: () => _handleExecuteOrCopy(snippet),
                                              ),
                                              PopupMenuButton<String>(
                                                onSelected: (val) async {
                                                  if (val == 'edit') {
                                                    final updated = await SnippetFormDialog.show(
                                                      context,
                                                      snippet: snippet,
                                                      workspaceId: widget.workspaceId,
                                                    );
                                                    if (updated != null) {
                                                      ref
                                                          .read(snippetsNotifierProvider.notifier)
                                                          .updateSnippet(updated);
                                                    }
                                                  } else if (val == 'delete') {
                                                    ref
                                                        .read(snippetsNotifierProvider.notifier)
                                                        .deleteSnippet(snippet.id);
                                                  }
                                                },
                                                itemBuilder: (context) => [
                                                  const PopupMenuItem(
                                                      value: 'edit', child: Text('Edit')),
                                                  const PopupMenuItem(
                                                      value: 'delete',
                                                      child: Text('Delete',
                                                          style: TextStyle(color: Colors.red))),
                                                ],
                                              ),
                                            ],
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
                  loading: () => const Center(child: CircularProgressIndicator()),
                  error: (err, stack) => Center(child: Text('Error loading snippets: $err')),
                ),
              ],
            ),
            // Runbooks Tab
            RunbooksScreen(workspaceId: widget.workspaceId),
          ],
        ),
      ),
    );
  }
}
