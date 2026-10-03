import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../data/repositories/run_history_repository.dart';
import '../../data/run_providers.dart';
import 'runbook_run_notifier.dart';
import 'runbooks_notifier.dart';

part 'run_history_providers.g.dart';

/// A runbook's stored runs, newest first. Reloads when a run is recorded or
/// the history is cleared.
@riverpod
Future<List<RunHistorySummary>> runbookHistory(Ref ref, String runbookId) {
  ref.watch(runHistoryRevisionProvider);
  return ref.watch(runHistoryRepositoryProvider).forRunbook(runbookId);
}

/// One stored run in full, or null once it has been pruned.
@riverpod
Future<StoredRun?> storedRun(Ref ref, String runId) {
  return ref.watch(runHistoryRepositoryProvider).load(runId);
}

/// The most recent run of every runbook in the list, for the last-run badge.
@riverpod
Future<Map<String, RunHistorySummary>> latestRunbookRuns(Ref ref) async {
  ref.watch(runHistoryRevisionProvider);
  final runbooks = await ref.watch(runbooksProvider.future);
  return ref.watch(runHistoryRepositoryProvider).latestByRunbook([
    for (final r in runbooks) r.id,
  ]);
}
