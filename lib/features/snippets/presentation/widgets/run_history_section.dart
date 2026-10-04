import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../../../../app/theme/shellvibe_tokens.dart';
import '../../../../app/widgets/adaptive_modal.dart';
import '../../../../app/widgets/shellvibe_ui.dart';
import '../../data/repositories/run_history_repository.dart';
import '../../data/run_providers.dart';
import '../../domain/models/runbook_model.dart';
import '../../domain/models/snippet_model.dart';
import '../notifiers/run_history_providers.dart';
import '../notifiers/runbook_run_notifier.dart';
import 'run_progress_view.dart';

/// A runbook's recent stored runs, with Clear.
class RunbookHistorySection extends ConsumerWidget {
  final RunbookModel runbook;

  const RunbookHistorySection({super.key, required this.runbook});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return _HistoryList(
      title: 'History',
      subject: 'runbook "${runbook.title}"',
      history: ref.watch(runbookHistoryProvider(runbook.id)).value,
      onClear: () =>
          ref.read(runHistoryRepositoryProvider).clear(runbookId: runbook.id),
    );
  }
}

/// A snippet's recent stored runs, with Clear. The same list as a runbook's:
/// a snippet run is stored as the one-step runbook it ran as.
class SnippetHistorySection extends ConsumerWidget {
  final SnippetModel snippet;

  const SnippetHistorySection({super.key, required this.snippet});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return _HistoryList(
      title: 'Recent runs',
      subject: 'snippet "${snippet.title}"',
      history: ref.watch(snippetHistoryProvider(snippet.id)).value,
      onClear: () =>
          ref.read(runHistoryRepositoryProvider).clear(snippetId: snippet.id),
    );
  }
}

class _HistoryList extends ConsumerWidget {
  final String title;
  final String subject;
  final List<RunHistorySummary>? history;
  final Future<void> Function() onClear;

  const _HistoryList({
    required this.title,
    required this.subject,
    required this.history,
    required this.onClear,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = ShellVibeTokens.resolve(context);
    final runs = history;
    if (runs == null || runs.isEmpty) return const SizedBox.shrink();

    return Column(
      key: const Key('run_history_section'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ShellVibeSectionLabel(label: title, padding: EdgeInsets.zero),
        const SizedBox(height: 6),
        for (final run in runs.take(8))
          InkWell(
            key: Key('run_history_${run.id}'),
            onTap: () => RunHistoryDialog.show(context, run),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 5),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    run.status == 'succeeded'
                        ? LucideIcons.circleCheck
                        : run.status == 'cancelled'
                        ? LucideIcons.ban
                        : LucideIcons.circleX,
                    size: 14,
                    color: run.status == 'succeeded'
                        ? tokens.success
                        : run.status == 'cancelled'
                        ? tokens.textMuted
                        : tokens.danger,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          run.summaryText,
                          style: const TextStyle(fontSize: 12),
                        ),
                        Text(
                          '${relativeTime(run.startedAt, DateTime.now())} · '
                          '${run.strategy.label}'
                          '${run.triggeredByName == null ? '' : ' · via ${run.triggeredByName}'}',
                          style: TextStyle(
                            fontSize: 11,
                            color: tokens.textMuted,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        const SizedBox(height: 4),
        ShellVibeButton.quiet(
          key: const Key('run_history_clear'),
          label: 'Clear run history',
          icon: LucideIcons.trash2,
          onPressed: () => _confirmClear(context, ref),
        ),
      ],
    );
  }

  Future<void> _confirmClear(BuildContext context, WidgetRef ref) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => ShadDialog.alert(
        title: const Text('Clear run history'),
        description: Text(
          'Delete every stored run of $subject? The $subject itself is not '
          'affected.',
        ),
        actions: adaptiveDialogActions(dialogContext, [
          ShellVibeButton.secondary(
            label: 'Cancel',
            onPressed: () => Navigator.of(dialogContext).pop(false),
          ),
          ShellVibeButton.danger(
            key: const Key('run_history_clear_confirm'),
            label: 'Clear',
            onPressed: () => Navigator.of(dialogContext).pop(true),
          ),
        ]),
        actionsAxis: adaptiveDialogActionsAxis(dialogContext),
      ),
    );
    if (confirmed != true || !context.mounted) return;
    await onClear();
    ref.read(runHistoryRevisionProvider.notifier).bump();
  }
}
