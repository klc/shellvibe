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
/// Kept alive, unlike the session-scoped providers: leaving the screen must
/// not silently cancel a deploy, and a settled run (a dialog may still be
/// about to read it) would otherwise vanish the moment nothing watched it.
/// What it retains once settled is plain data — every SSH session is closed in
/// the run service's `finally`, and disposing mid-run (the app container going
/// away) cancels the run, which closes the ones still open.
///
/// A run is written to local history once, when it settles (cancelled runs
/// included). A run cut off by the app quitting is therefore not recorded.

@ProviderFor(RunbookRunNotifier)
final runbookRunProvider = RunbookRunNotifierProvider._();

/// Holds the run the Automation library is showing, so progress and Stop
/// outlive the widget that started it.
///
/// Kept alive, unlike the session-scoped providers: leaving the screen must
/// not silently cancel a deploy, and a settled run (a dialog may still be
/// about to read it) would otherwise vanish the moment nothing watched it.
/// What it retains once settled is plain data — every SSH session is closed in
/// the run service's `finally`, and disposing mid-run (the app container going
/// away) cancels the run, which closes the ones still open.
///
/// A run is written to local history once, when it settles (cancelled runs
/// included). A run cut off by the app quitting is therefore not recorded.
final class RunbookRunNotifierProvider
    extends $NotifierProvider<RunbookRunNotifier, ActiveRun?> {
  /// Holds the run the Automation library is showing, so progress and Stop
  /// outlive the widget that started it.
  ///
  /// Kept alive, unlike the session-scoped providers: leaving the screen must
  /// not silently cancel a deploy, and a settled run (a dialog may still be
  /// about to read it) would otherwise vanish the moment nothing watched it.
  /// What it retains once settled is plain data — every SSH session is closed in
  /// the run service's `finally`, and disposing mid-run (the app container going
  /// away) cancels the run, which closes the ones still open.
  ///
  /// A run is written to local history once, when it settles (cancelled runs
  /// included). A run cut off by the app quitting is therefore not recorded.
  RunbookRunNotifierProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'runbookRunProvider',
        isAutoDispose: false,
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
    r'90a1f909c50c682ee4f0dd4233c32f7ac1cb65c3';

/// Holds the run the Automation library is showing, so progress and Stop
/// outlive the widget that started it.
///
/// Kept alive, unlike the session-scoped providers: leaving the screen must
/// not silently cancel a deploy, and a settled run (a dialog may still be
/// about to read it) would otherwise vanish the moment nothing watched it.
/// What it retains once settled is plain data — every SSH session is closed in
/// the run service's `finally`, and disposing mid-run (the app container going
/// away) cancels the run, which closes the ones still open.
///
/// A run is written to local history once, when it settles (cancelled runs
/// included). A run cut off by the app quitting is therefore not recorded.

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

/// Bumped each time a run is written to history, so history lists and
/// last-run badges reload.

@ProviderFor(RunHistoryRevision)
final runHistoryRevisionProvider = RunHistoryRevisionProvider._();

/// Bumped each time a run is written to history, so history lists and
/// last-run badges reload.
final class RunHistoryRevisionProvider
    extends $NotifierProvider<RunHistoryRevision, int> {
  /// Bumped each time a run is written to history, so history lists and
  /// last-run badges reload.
  RunHistoryRevisionProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'runHistoryRevisionProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$runHistoryRevisionHash();

  @$internal
  @override
  RunHistoryRevision create() => RunHistoryRevision();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(int value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<int>(value),
    );
  }
}

String _$runHistoryRevisionHash() =>
    r'f0d6d4cd26c831e614e1e8df45bf05a85ad912dc';

/// Bumped each time a run is written to history, so history lists and
/// last-run badges reload.

abstract class _$RunHistoryRevision extends $Notifier<int> {
  int build();
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref = this.ref as $Ref<int, int>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<int, int>,
              int,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, build);
  }
}
