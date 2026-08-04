import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../../../../app/theme/terly_tokens.dart';
import '../../domain/models/template_model.dart';
import '../notifiers/templates_notifier.dart';

/// One-line summary of what a template will open.
String templateSummary(TemplateModel template) {
  final tabs = template.tabCount;
  final splits = template.panes.length - tabs;
  final tabPart = '$tabs ${tabs == 1 ? 'tab' : 'tabs'}';
  if (splits == 0) return tabPart;
  return '$tabPart · $splits ${splits == 1 ? 'split pane' : 'split panes'}';
}

/// Bottom sheet listing the workspace's templates. Tapping one runs it.
///
/// Mirrors the terminal's host picker sheet, so "run a template" and "connect
/// to a host" are picked the same way.
class TemplatePickerSheet extends ConsumerWidget {
  final Future<void> Function(TemplateModel template) onSelect;

  const TemplatePickerSheet({super.key, required this.onSelect});

  static void show(
    BuildContext context, {
    required Future<void> Function(TemplateModel template) onSelect,
  }) {
    final tokens = TerlyTokens.resolve(context);
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      backgroundColor: tokens.surface,
      builder: (ctx) => TemplatePickerSheet(onSelect: onSelect),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final templatesAsync = ref.watch(templatesProvider);

    return templatesAsync.when(
      loading: () => const Padding(
        padding: EdgeInsets.all(24),
        child: Center(child: CircularProgressIndicator()),
      ),
      error: (e, s) => Padding(
        padding: const EdgeInsets.all(24),
        child: Center(child: Text('Error loading templates: $e')),
      ),
      data: (templates) {
        if (templates.isEmpty) {
          return const Padding(
            padding: EdgeInsets.all(24),
            child: Center(
              child: Text(
                'No templates yet. Open the tabs and panes you want, then save '
                'them as a template.',
                textAlign: TextAlign.center,
              ),
            ),
          );
        }

        return ListView.builder(
          shrinkWrap: true,
          itemCount: templates.length,
          itemBuilder: (context, index) {
            final template = templates[index];
            return ListTile(
              key: Key('run_template_${template.id}'),
              leading: const Icon(LucideIcons.layoutTemplate, size: 18),
              title: Text(template.name),
              subtitle: Text(
                template.description == null
                    ? templateSummary(template)
                    : '${templateSummary(template)} · ${template.description}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              onTap: () async {
                Navigator.of(context).pop();
                await onSelect(template);
              },
            );
          },
        );
      },
    );
  }
}
