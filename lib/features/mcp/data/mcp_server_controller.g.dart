// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'mcp_server_controller.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// Owns the app's single [McpServerController] instance. `keepAlive` for the
/// same reason `mcpSessionPoolProvider` is (`mcp_providers.dart`): an
/// autoDispose controller would tear down a running server — and every
/// session an agent has open through it — the instant nothing happened to be
/// watching this provider, e.g. the user navigating away from the AI Access
/// settings screen. The server's lifetime must track the app's, not a
/// widget's.

@ProviderFor(mcpServerController)
final mcpServerControllerProvider = McpServerControllerProvider._();

/// Owns the app's single [McpServerController] instance. `keepAlive` for the
/// same reason `mcpSessionPoolProvider` is (`mcp_providers.dart`): an
/// autoDispose controller would tear down a running server — and every
/// session an agent has open through it — the instant nothing happened to be
/// watching this provider, e.g. the user navigating away from the AI Access
/// settings screen. The server's lifetime must track the app's, not a
/// widget's.

final class McpServerControllerProvider
    extends
        $FunctionalProvider<
          McpServerController,
          McpServerController,
          McpServerController
        >
    with $Provider<McpServerController> {
  /// Owns the app's single [McpServerController] instance. `keepAlive` for the
  /// same reason `mcpSessionPoolProvider` is (`mcp_providers.dart`): an
  /// autoDispose controller would tear down a running server — and every
  /// session an agent has open through it — the instant nothing happened to be
  /// watching this provider, e.g. the user navigating away from the AI Access
  /// settings screen. The server's lifetime must track the app's, not a
  /// widget's.
  McpServerControllerProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'mcpServerControllerProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$mcpServerControllerHash();

  @$internal
  @override
  $ProviderElement<McpServerController> $createElement(
    $ProviderPointer pointer,
  ) => $ProviderElement(pointer);

  @override
  McpServerController create(Ref ref) {
    return mcpServerController(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(McpServerController value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<McpServerController>(value),
    );
  }
}

String _$mcpServerControllerHash() =>
    r'c26c289f8716b096a7b50b1a88cf68dbe466af3a';
