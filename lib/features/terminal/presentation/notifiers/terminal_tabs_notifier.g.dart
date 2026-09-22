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
    r'bb567992d58d12333b870e9958f2c36049bb9e95';

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
