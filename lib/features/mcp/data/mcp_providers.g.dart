// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'mcp_providers.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// Provider for [McpHostConnector]. Plain-Dart, no `Ref`/`BuildContext` inside
/// the class itself — see its docstring — so this is only the Riverpod
/// wiring around it.

@ProviderFor(mcpHostConnector)
final mcpHostConnectorProvider = McpHostConnectorProvider._();

/// Provider for [McpHostConnector]. Plain-Dart, no `Ref`/`BuildContext` inside
/// the class itself — see its docstring — so this is only the Riverpod
/// wiring around it.

final class McpHostConnectorProvider
    extends
        $FunctionalProvider<
          McpHostConnector,
          McpHostConnector,
          McpHostConnector
        >
    with $Provider<McpHostConnector> {
  /// Provider for [McpHostConnector]. Plain-Dart, no `Ref`/`BuildContext` inside
  /// the class itself — see its docstring — so this is only the Riverpod
  /// wiring around it.
  McpHostConnectorProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'mcpHostConnectorProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$mcpHostConnectorHash();

  @$internal
  @override
  $ProviderElement<McpHostConnector> $createElement($ProviderPointer pointer) =>
      $ProviderElement(pointer);

  @override
  McpHostConnector create(Ref ref) {
    return mcpHostConnector(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(McpHostConnector value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<McpHostConnector>(value),
    );
  }
}

String _$mcpHostConnectorHash() => r'ee1dc6b2e6cc33a55799c8524e2f07cb36ab69d4';

/// Provider for [McpSessionPool].
///
/// Must be `keepAlive`: an autoDispose pool would tear down every open agent
/// session the instant nothing was watching it, e.g. the moment the user
/// navigates away from the AI Access settings screen — killing sessions the
/// agent is actively using for a reason that has nothing to do with them.

@ProviderFor(mcpSessionPool)
final mcpSessionPoolProvider = McpSessionPoolProvider._();

/// Provider for [McpSessionPool].
///
/// Must be `keepAlive`: an autoDispose pool would tear down every open agent
/// session the instant nothing was watching it, e.g. the moment the user
/// navigates away from the AI Access settings screen — killing sessions the
/// agent is actively using for a reason that has nothing to do with them.

final class McpSessionPoolProvider
    extends $FunctionalProvider<McpSessionPool, McpSessionPool, McpSessionPool>
    with $Provider<McpSessionPool> {
  /// Provider for [McpSessionPool].
  ///
  /// Must be `keepAlive`: an autoDispose pool would tear down every open agent
  /// session the instant nothing was watching it, e.g. the moment the user
  /// navigates away from the AI Access settings screen — killing sessions the
  /// agent is actively using for a reason that has nothing to do with them.
  McpSessionPoolProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'mcpSessionPoolProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$mcpSessionPoolHash();

  @$internal
  @override
  $ProviderElement<McpSessionPool> $createElement($ProviderPointer pointer) =>
      $ProviderElement(pointer);

  @override
  McpSessionPool create(Ref ref) {
    return mcpSessionPool(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(McpSessionPool value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<McpSessionPool>(value),
    );
  }
}

String _$mcpSessionPoolHash() => r'5ed28b8a69d6091b24db8f631f06494bd87acacd';
