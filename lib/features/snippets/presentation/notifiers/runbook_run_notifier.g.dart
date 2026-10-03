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
    r'286501659ad9bfe307dcab67f312aedb0689fc47';

/// Holds the run the Automation library is showing, so progress and Stop
/// outlive the widget that started it.
///
/// Kept alive, unlike the session-scoped providers: leaving the screen must
/// not silently cancel a deploy, and a settled run (a dialog may still be
/// about to read it) would otherwise vanish the moment nothing watched it.
/// What it retains once settled is plain data — every SSH session is closed in
/// the run service's `finally`, and disposing mid-run (the app container going
/// away) cancels the run, which closes the ones still open.

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
