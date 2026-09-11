// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'mcp_activity_notifier.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// Live view behind the AI Activity panel: connected clients, their open
/// sessions, what each one currently holds, what it is waiting on right now,
/// and a recent tail of what it already did.
///
/// This is deliberately a poll, not a cache. The four repositories underneath
/// it (`McpAuditRepository`, `McpGrantRepository`, `McpApprovalRepository`,
/// `McpClientRepository`) and the session pool have no shared change stream
/// of their own — every write happens deep in a tool handler with no
/// `BuildContext` anywhere near it — so the only way to stay honest about
/// "what is the agent doing right now" is to keep re-reading them. The panel
/// is the product's whole answer to "the agent is a black box in every other
/// tool"; a notifier that quietly went stale would undercut that promise more
/// than the extra queries cost.

@ProviderFor(McpActivityNotifier)
final mcpActivityProvider = McpActivityNotifierProvider._();

/// Live view behind the AI Activity panel: connected clients, their open
/// sessions, what each one currently holds, what it is waiting on right now,
/// and a recent tail of what it already did.
///
/// This is deliberately a poll, not a cache. The four repositories underneath
/// it (`McpAuditRepository`, `McpGrantRepository`, `McpApprovalRepository`,
/// `McpClientRepository`) and the session pool have no shared change stream
/// of their own — every write happens deep in a tool handler with no
/// `BuildContext` anywhere near it — so the only way to stay honest about
/// "what is the agent doing right now" is to keep re-reading them. The panel
/// is the product's whole answer to "the agent is a black box in every other
/// tool"; a notifier that quietly went stale would undercut that promise more
/// than the extra queries cost.
final class McpActivityNotifierProvider
    extends $AsyncNotifierProvider<McpActivityNotifier, McpActivityState> {
  /// Live view behind the AI Activity panel: connected clients, their open
  /// sessions, what each one currently holds, what it is waiting on right now,
  /// and a recent tail of what it already did.
  ///
  /// This is deliberately a poll, not a cache. The four repositories underneath
  /// it (`McpAuditRepository`, `McpGrantRepository`, `McpApprovalRepository`,
  /// `McpClientRepository`) and the session pool have no shared change stream
  /// of their own — every write happens deep in a tool handler with no
  /// `BuildContext` anywhere near it — so the only way to stay honest about
  /// "what is the agent doing right now" is to keep re-reading them. The panel
  /// is the product's whole answer to "the agent is a black box in every other
  /// tool"; a notifier that quietly went stale would undercut that promise more
  /// than the extra queries cost.
  McpActivityNotifierProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'mcpActivityProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$mcpActivityNotifierHash();

  @$internal
  @override
  McpActivityNotifier create() => McpActivityNotifier();
}

String _$mcpActivityNotifierHash() =>
    r'8f158b1e541a99fdf2e76b5d556181a9f1b024c2';

/// Live view behind the AI Activity panel: connected clients, their open
/// sessions, what each one currently holds, what it is waiting on right now,
/// and a recent tail of what it already did.
///
/// This is deliberately a poll, not a cache. The four repositories underneath
/// it (`McpAuditRepository`, `McpGrantRepository`, `McpApprovalRepository`,
/// `McpClientRepository`) and the session pool have no shared change stream
/// of their own — every write happens deep in a tool handler with no
/// `BuildContext` anywhere near it — so the only way to stay honest about
/// "what is the agent doing right now" is to keep re-reading them. The panel
/// is the product's whole answer to "the agent is a black box in every other
/// tool"; a notifier that quietly went stale would undercut that promise more
/// than the extra queries cost.

abstract class _$McpActivityNotifier extends $AsyncNotifier<McpActivityState> {
  FutureOr<McpActivityState> build();
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref =
        this.ref as $Ref<AsyncValue<McpActivityState>, McpActivityState>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<AsyncValue<McpActivityState>, McpActivityState>,
              AsyncValue<McpActivityState>,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, build);
  }
}
