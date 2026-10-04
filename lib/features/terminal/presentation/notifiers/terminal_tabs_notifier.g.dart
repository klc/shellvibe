// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'terminal_tabs_notifier.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

@ProviderFor(TerminalTabsNotifier)
final terminalTabsProvider = TerminalTabsNotifierProvider._();

final class TerminalTabsNotifierProvider
    extends $NotifierProvider<TerminalTabsNotifier, TerminalTabsState> {
  TerminalTabsNotifierProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'terminalTabsProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$terminalTabsNotifierHash();

  @$internal
  @override
  TerminalTabsNotifier create() => TerminalTabsNotifier();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(TerminalTabsState value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<TerminalTabsState>(value),
    );
  }
}

String _$terminalTabsNotifierHash() =>
    r'937ae3657e9b6b8aaf85e1dd568517f98a7853b7';

abstract class _$TerminalTabsNotifier extends $Notifier<TerminalTabsState> {
  TerminalTabsState build();
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref = this.ref as $Ref<TerminalTabsState, TerminalTabsState>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<TerminalTabsState, TerminalTabsState>,
              TerminalTabsState,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, build);
  }
}

/// A one-line notice from the terminal layer for the screen that is showing
/// it: there is no `BuildContext` down in the notifier to toast from.
///
/// The id changes on every post, so the same message twice in a row is still
/// two events to a listener.

@ProviderFor(TerminalNotice)
final terminalNoticeProvider = TerminalNoticeProvider._();

/// A one-line notice from the terminal layer for the screen that is showing
/// it: there is no `BuildContext` down in the notifier to toast from.
///
/// The id changes on every post, so the same message twice in a row is still
/// two events to a listener.
final class TerminalNoticeProvider
    extends $NotifierProvider<TerminalNotice, ({int id, String message})?> {
  /// A one-line notice from the terminal layer for the screen that is showing
  /// it: there is no `BuildContext` down in the notifier to toast from.
  ///
  /// The id changes on every post, so the same message twice in a row is still
  /// two events to a listener.
  TerminalNoticeProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'terminalNoticeProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$terminalNoticeHash();

  @$internal
  @override
  TerminalNotice create() => TerminalNotice();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(({int id, String message})? value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<({int id, String message})?>(value),
    );
  }
}

String _$terminalNoticeHash() => r'ab2478b704249b17d5751444c91b1af73a93f6e9';

/// A one-line notice from the terminal layer for the screen that is showing
/// it: there is no `BuildContext` down in the notifier to toast from.
///
/// The id changes on every post, so the same message twice in a row is still
/// two events to a listener.

abstract class _$TerminalNotice extends $Notifier<({int id, String message})?> {
  ({int id, String message})? build();
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref =
        this.ref
            as $Ref<({int id, String message})?, ({int id, String message})?>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<
                ({int id, String message})?,
                ({int id, String message})?
              >,
              ({int id, String message})?,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, build);
  }
}
