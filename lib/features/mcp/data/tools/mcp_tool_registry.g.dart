// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'mcp_tool_registry.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

@ProviderFor(mcpToolSwitches)
final mcpToolSwitchesProvider = McpToolSwitchesProvider._();

final class McpToolSwitchesProvider
    extends
        $FunctionalProvider<McpToolSwitches, McpToolSwitches, McpToolSwitches>
    with $Provider<McpToolSwitches> {
  McpToolSwitchesProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'mcpToolSwitchesProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$mcpToolSwitchesHash();

  @$internal
  @override
  $ProviderElement<McpToolSwitches> $createElement($ProviderPointer pointer) =>
      $ProviderElement(pointer);

  @override
  McpToolSwitches create(Ref ref) {
    return mcpToolSwitches(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(McpToolSwitches value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<McpToolSwitches>(value),
    );
  }
}

String _$mcpToolSwitchesHash() => r'54b6a364662d615fa2964d4ba9e4d354d95b732b';

/// Provider for [McpToolRegistry].
///
/// `keepAlive`, matching every other provider in this feature that backs a
/// live MCP connection (see `mcp_providers.dart`): an autoDispose registry
/// would be torn down and rebuilt on whatever unrelated widget-tree churn
/// happens to drop its last watcher, which has nothing to do with whether an
/// agent is still connected.

@ProviderFor(mcpToolRegistry)
final mcpToolRegistryProvider = McpToolRegistryProvider._();

/// Provider for [McpToolRegistry].
///
/// `keepAlive`, matching every other provider in this feature that backs a
/// live MCP connection (see `mcp_providers.dart`): an autoDispose registry
/// would be torn down and rebuilt on whatever unrelated widget-tree churn
/// happens to drop its last watcher, which has nothing to do with whether an
/// agent is still connected.

final class McpToolRegistryProvider
    extends
        $FunctionalProvider<McpToolRegistry, McpToolRegistry, McpToolRegistry>
    with $Provider<McpToolRegistry> {
  /// Provider for [McpToolRegistry].
  ///
  /// `keepAlive`, matching every other provider in this feature that backs a
  /// live MCP connection (see `mcp_providers.dart`): an autoDispose registry
  /// would be torn down and rebuilt on whatever unrelated widget-tree churn
  /// happens to drop its last watcher, which has nothing to do with whether an
  /// agent is still connected.
  McpToolRegistryProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'mcpToolRegistryProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$mcpToolRegistryHash();

  @$internal
  @override
  $ProviderElement<McpToolRegistry> $createElement($ProviderPointer pointer) =>
      $ProviderElement(pointer);

  @override
  McpToolRegistry create(Ref ref) {
    return mcpToolRegistry(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(McpToolRegistry value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<McpToolRegistry>(value),
    );
  }
}

String _$mcpToolRegistryHash() => r'ed320a803167329dea6847a417f249d714d3b12a';
