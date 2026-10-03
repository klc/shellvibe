// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'run_history_providers.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// A runbook's stored runs, newest first. Reloads when a run is recorded or
/// the history is cleared.

@ProviderFor(runbookHistory)
final runbookHistoryProvider = RunbookHistoryFamily._();

/// A runbook's stored runs, newest first. Reloads when a run is recorded or
/// the history is cleared.

final class RunbookHistoryProvider
    extends
        $FunctionalProvider<
          AsyncValue<List<RunHistorySummary>>,
          List<RunHistorySummary>,
          FutureOr<List<RunHistorySummary>>
        >
    with
        $FutureModifier<List<RunHistorySummary>>,
        $FutureProvider<List<RunHistorySummary>> {
  /// A runbook's stored runs, newest first. Reloads when a run is recorded or
  /// the history is cleared.
  RunbookHistoryProvider._({
    required RunbookHistoryFamily super.from,
    required String super.argument,
  }) : super(
         retry: null,
         name: r'runbookHistoryProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$runbookHistoryHash();

  @override
  String toString() {
    return r'runbookHistoryProvider'
        ''
        '($argument)';
  }

  @$internal
  @override
  $FutureProviderElement<List<RunHistorySummary>> $createElement(
    $ProviderPointer pointer,
  ) => $FutureProviderElement(pointer);

  @override
  FutureOr<List<RunHistorySummary>> create(Ref ref) {
    final argument = this.argument as String;
    return runbookHistory(ref, argument);
  }

  @override
  bool operator ==(Object other) {
    return other is RunbookHistoryProvider && other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$runbookHistoryHash() => r'875b08fbe7a7f673c1a64dcb598ba5edbc1b1973';

/// A runbook's stored runs, newest first. Reloads when a run is recorded or
/// the history is cleared.

final class RunbookHistoryFamily extends $Family
    with $FunctionalFamilyOverride<FutureOr<List<RunHistorySummary>>, String> {
  RunbookHistoryFamily._()
    : super(
        retry: null,
        name: r'runbookHistoryProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  /// A runbook's stored runs, newest first. Reloads when a run is recorded or
  /// the history is cleared.

  RunbookHistoryProvider call(String runbookId) =>
      RunbookHistoryProvider._(argument: runbookId, from: this);

  @override
  String toString() => r'runbookHistoryProvider';
}

/// One stored run in full, or null once it has been pruned.

@ProviderFor(storedRun)
final storedRunProvider = StoredRunFamily._();

/// One stored run in full, or null once it has been pruned.

final class StoredRunProvider
    extends
        $FunctionalProvider<
          AsyncValue<StoredRun?>,
          StoredRun?,
          FutureOr<StoredRun?>
        >
    with $FutureModifier<StoredRun?>, $FutureProvider<StoredRun?> {
  /// One stored run in full, or null once it has been pruned.
  StoredRunProvider._({
    required StoredRunFamily super.from,
    required String super.argument,
  }) : super(
         retry: null,
         name: r'storedRunProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$storedRunHash();

  @override
  String toString() {
    return r'storedRunProvider'
        ''
        '($argument)';
  }

  @$internal
  @override
  $FutureProviderElement<StoredRun?> $createElement($ProviderPointer pointer) =>
      $FutureProviderElement(pointer);

  @override
  FutureOr<StoredRun?> create(Ref ref) {
    final argument = this.argument as String;
    return storedRun(ref, argument);
  }

  @override
  bool operator ==(Object other) {
    return other is StoredRunProvider && other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$storedRunHash() => r'28b0a9ee1baa5a98cd52c17300e2bdfb0aec18c5';

/// One stored run in full, or null once it has been pruned.

final class StoredRunFamily extends $Family
    with $FunctionalFamilyOverride<FutureOr<StoredRun?>, String> {
  StoredRunFamily._()
    : super(
        retry: null,
        name: r'storedRunProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  /// One stored run in full, or null once it has been pruned.

  StoredRunProvider call(String runId) =>
      StoredRunProvider._(argument: runId, from: this);

  @override
  String toString() => r'storedRunProvider';
}

/// The most recent run of every runbook in the list, for the last-run badge.

@ProviderFor(latestRunbookRuns)
final latestRunbookRunsProvider = LatestRunbookRunsProvider._();

/// The most recent run of every runbook in the list, for the last-run badge.

final class LatestRunbookRunsProvider
    extends
        $FunctionalProvider<
          AsyncValue<Map<String, RunHistorySummary>>,
          Map<String, RunHistorySummary>,
          FutureOr<Map<String, RunHistorySummary>>
        >
    with
        $FutureModifier<Map<String, RunHistorySummary>>,
        $FutureProvider<Map<String, RunHistorySummary>> {
  /// The most recent run of every runbook in the list, for the last-run badge.
  LatestRunbookRunsProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'latestRunbookRunsProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$latestRunbookRunsHash();

  @$internal
  @override
  $FutureProviderElement<Map<String, RunHistorySummary>> $createElement(
    $ProviderPointer pointer,
  ) => $FutureProviderElement(pointer);

  @override
  FutureOr<Map<String, RunHistorySummary>> create(Ref ref) {
    return latestRunbookRuns(ref);
  }
}

String _$latestRunbookRunsHash() => r'135e9596929a09f0c133538f58eaf13fc56c7faf';
