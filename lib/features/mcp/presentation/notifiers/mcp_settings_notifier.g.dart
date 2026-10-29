// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'mcp_settings_notifier.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// Owns the current workspace's AI-access settings: the master switch, the
/// live server view, and the tunable numeric knobs.
///
/// Flipping the master switch is the one place this notifier reaches outside
/// its own storage: on -> [McpServerController.start], off ->
/// [McpServerController.stop]. The "Limits" setters persist their value and
/// push it onto the live session pool, which is where each one is read.

@ProviderFor(McpSettingsNotifier)
final mcpSettingsProvider = McpSettingsNotifierProvider._();

/// Owns the current workspace's AI-access settings: the master switch, the
/// live server view, and the tunable numeric knobs.
///
/// Flipping the master switch is the one place this notifier reaches outside
/// its own storage: on -> [McpServerController.start], off ->
/// [McpServerController.stop]. The "Limits" setters persist their value and
/// push it onto the live session pool, which is where each one is read.
final class McpSettingsNotifierProvider
    extends $AsyncNotifierProvider<McpSettingsNotifier, McpSettingsState> {
  /// Owns the current workspace's AI-access settings: the master switch, the
  /// live server view, and the tunable numeric knobs.
  ///
  /// Flipping the master switch is the one place this notifier reaches outside
  /// its own storage: on -> [McpServerController.start], off ->
  /// [McpServerController.stop]. The "Limits" setters persist their value and
  /// push it onto the live session pool, which is where each one is read.
  McpSettingsNotifierProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'mcpSettingsProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$mcpSettingsNotifierHash();

  @$internal
  @override
  McpSettingsNotifier create() => McpSettingsNotifier();
}

String _$mcpSettingsNotifierHash() =>
    r'b7cca2432e122cf650c0b9ade31084ee35498cb0';

/// Owns the current workspace's AI-access settings: the master switch, the
/// live server view, and the tunable numeric knobs.
///
/// Flipping the master switch is the one place this notifier reaches outside
/// its own storage: on -> [McpServerController.start], off ->
/// [McpServerController.stop]. The "Limits" setters persist their value and
/// push it onto the live session pool, which is where each one is read.

abstract class _$McpSettingsNotifier extends $AsyncNotifier<McpSettingsState> {
  FutureOr<McpSettingsState> build();
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref =
        this.ref as $Ref<AsyncValue<McpSettingsState>, McpSettingsState>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<AsyncValue<McpSettingsState>, McpSettingsState>,
              AsyncValue<McpSettingsState>,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, build);
  }
}
