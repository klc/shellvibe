// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'runbook_run_notifier.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// Holds the run the Automation library is showing, so progress and Stop
/// outlive the widget that started it.
///
/// Auto-dispose, but kept alive while a run is in flight: leaving the screen
/// must not silently cancel a deploy, and a settled run has nothing left to
/// protect. Disposing mid-run (the app container going away) cancels it, which
/// closes every SSH session it opened.

@ProviderFor(RunbookRunNotifier)
final runbookRunProvider = RunbookRunNotifierProvider._();

/// Holds the run the Automation library is showing, so progress and Stop
/// outlive the widget that started it.
///
/// Auto-dispose, but kept alive while a run is in flight: leaving the screen
/// must not silently cancel a deploy, and a settled run has nothing left to
/// protect. Disposing mid-run (the app container going away) cancels it, which
/// closes every SSH session it opened.
final class RunbookRunNotifierProvider
    extends $NotifierProvider<RunbookRunNotifier, ActiveRun?> {
  /// Holds the run the Automation library is showing, so progress and Stop
  /// outlive the widget that started it.
  ///
  /// Auto-dispose, but kept alive while a run is in flight: leaving the screen
  /// must not silently cancel a deploy, and a settled run has nothing left to
  /// protect. Disposing mid-run (the app container going away) cancels it, which
  /// closes every SSH session it opened.
  RunbookRunNotifierProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'runbookRunProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$runbookRunNotifierHash();

  @$internal
  @override
  RunbookRunNotifier create() => RunbookRunNotifier();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(ActiveRun? value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<ActiveRun?>(value),
    );
  }
}

String _$runbookRunNotifierHash() =>
    r'5360ed29fcf1be3b3e873c3a055cc91572d9b05f';

/// Holds the run the Automation library is showing, so progress and Stop
/// outlive the widget that started it.
///
/// Auto-dispose, but kept alive while a run is in flight: leaving the screen
/// must not silently cancel a deploy, and a settled run has nothing left to
/// protect. Disposing mid-run (the app container going away) cancels it, which
/// closes every SSH session it opened.

abstract class _$RunbookRunNotifier extends $Notifier<ActiveRun?> {
  ActiveRun? build();
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref = this.ref as $Ref<ActiveRun?, ActiveRun?>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<ActiveRun?, ActiveRun?>,
              ActiveRun?,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, build);
  }
}
