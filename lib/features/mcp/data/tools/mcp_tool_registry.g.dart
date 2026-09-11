// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'mcp_tool_registry.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
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

String _$mcpToolRegistryHash() => r'e496110821d59ab6020c9bf07ba8c9bdc29c119e';
