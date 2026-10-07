// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'mcp_request_dispatcher.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// Provider for [McpRequestDispatcher].
///
/// `keepAlive` because the server holds it for its whole lifetime; an
/// auto-disposing dispatcher would mint a new connection scope the first time
/// no widget happened to be watching it.

@ProviderFor(mcpRequestDispatcher)
final mcpRequestDispatcherProvider = McpRequestDispatcherProvider._();

/// Provider for [McpRequestDispatcher].
///
/// `keepAlive` because the server holds it for its whole lifetime; an
/// auto-disposing dispatcher would mint a new connection scope the first time
/// no widget happened to be watching it.

final class McpRequestDispatcherProvider
    extends
        $FunctionalProvider<
          McpRequestDispatcher,
          McpRequestDispatcher,
          McpRequestDispatcher
        >
    with $Provider<McpRequestDispatcher> {
  /// Provider for [McpRequestDispatcher].
  ///
  /// `keepAlive` because the server holds it for its whole lifetime; an
  /// auto-disposing dispatcher would mint a new connection scope the first time
  /// no widget happened to be watching it.
  McpRequestDispatcherProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'mcpRequestDispatcherProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$mcpRequestDispatcherHash();

  @$internal
  @override
  $ProviderElement<McpRequestDispatcher> $createElement(
    $ProviderPointer pointer,
  ) => $ProviderElement(pointer);

  @override
  McpRequestDispatcher create(Ref ref) {
    return mcpRequestDispatcher(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(McpRequestDispatcher value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<McpRequestDispatcher>(value),
    );
  }
}

String _$mcpRequestDispatcherHash() =>
    r'31b0a0d8bf5556b1bfc53945af4e2592938ab484';
