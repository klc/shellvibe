import 'dart:async';
import 'dart:io' show Platform, pid;

import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../core/mcp/mcp_endpoint_file.dart';
import '../../../core/mcp/mcp_http_transport.dart';
import '../../../core/mcp/mcp_protocol.dart';
import '../../../shared/providers/workspace_provider.dart';
import '../../vault/presentation/notifiers/vault_notifier.dart';
import 'mcp_request_dispatcher.dart';
import 'repositories/mcp_client_repository.dart';
import 'repositories/mcp_repository_providers.dart';

part 'mcp_server_controller.g.dart';

/// Builds the [McpHttpTransport] a [McpServerController] runs. A factory
/// (rather than the controller constructing a `McpHttpTransport` itself)
/// exists purely so tests can hand the controller a fake transport without
/// binding a real socket — the controller supplies the wiring
/// ([McpTransportRequestHandler]/[McpTransportAuthenticator]), the factory
/// decides what concrete object answers to that wiring.
typedef McpHttpTransportFactory =
    McpHttpTransport Function({
      required McpTransportRequestHandler onRequest,
      required McpTransportAuthenticator authenticate,
    });

/// Thrown when [McpServerController._guardedOnRequest] rejects a request
/// because the vault is locked or in its `isLocking` drain window.
///
/// This is intentionally *not* the tool-facing `VAULT_LOCKED` wire error
/// (`McpErrorCode.vaultLocked` in `mcp_enums.dart`, surfaced as a normal
/// JSON-RPC success whose `McpToolResult.isError` is set — see
/// `mcp_protocol.dart`'s docstring on why MCP errors work that way). That
/// shaping is a `tools/call`-specific concern for the request dispatcher
/// this controller does not own (Faz 2+); every credential lookup the
/// dispatcher makes already goes through the vault and fails there on its
/// own. This exception exists only to close the narrow race between the
/// vault flipping `isLocking` and this controller's [McpServerController.stop]
/// actually finishing — see the class docstring's "Vault gate" section. The
/// transport's blanket exception handler (`mcp_http_transport.dart`) turns
/// it into a generic `-32603` for that narrow window, which is an accepted
/// v0 trade-off, not an oversight.
class McpVaultUnavailableException implements Exception {
  const McpVaultUnavailableException();

  @override
  String toString() => 'MCP request rejected: the vault is locked or unlocking';
}

/// Starts and stops the MCP HTTP server and keeps `mcp-endpoint.json` in
/// sync with it — the desktop-side lifecycle counterpart to
/// `TerminalTabsNotifier._ensureDeviceLinkServer`/`stopDeviceLinkServer` for
/// Device Link (`features/terminal/presentation/notifiers/terminal_tabs_notifier.dart`).
///
/// **Vault gate.** MCP tools resolve SSH credentials, so nothing here may
/// run while the vault is locked. [VaultState.allowsDeviceLink]
/// (`vault_notifier.dart`) already encodes the exact condition this needs
/// (`status != locked && !isLocking`) for Device Link; rather than fork that
/// getter into an MCP-specific twin, or edit `vault_notifier.dart` to widen
/// it, this controller takes the condition as an opaque [isVaultAvailable]
/// callback. The `@riverpod` provider at the bottom of this file wires it to
/// that same `vaultProvider` condition, so both capabilities read the vault
/// identically without `vault_notifier.dart` knowing MCP exists. `isLocking`
/// specifically must flip this to `false` *before* the lock finishes
/// draining (`docs/mcp_context.md` §5: "MCP oturumları isLocking görür
/// görmez kapanmalı") — an open MCP session has no business outliving the
/// moment the user asked to lock, even by the few hundred milliseconds a
/// drain takes.
///
/// **Desktop-only.** [start] refuses on iOS/Android. This is not merely "we
/// haven't built the mobile UI for it yet" — a backgrounded iOS app has its
/// sockets torn down by the OS, so an `HttpServer` here would silently stop
/// accepting connections the moment the user switches apps, which is worse
/// than never having started one. MCP stays a desktop capability by
/// decision, not by omission.
class McpServerController {
  final McpHttpTransportFactory transportFactory;
  final McpClientRepository clients;

  /// Handles an authenticated JSON-RPC request. See
  /// `mcp_http_transport.dart`'s `McpTransportRequestHandler`. Owned by the
  /// caller (wired up in the `@riverpod` provider below) rather than by this
  /// controller, because request dispatch — `tools/list`, `tools/call`, ...
  /// — is Faz 2+ scope; this controller only needs to know how to wrap
  /// *whatever* handler exists with the vault gate below.
  final McpTransportRequestHandler onRequest;

  /// Mirrors `VaultState.allowsDeviceLink`. See the class docstring.
  final bool Function() isVaultAvailable;

  /// The workspace whose MCP client this controller writes into
  /// `mcp-endpoint.json`. See `docs/mcp_plan.md`'s "Workspace bağlama": the
  /// client a bridge authenticates as is fixed to whichever workspace this
  /// returns *at start time* — switching the active workspace in the UI
  /// later does not move an already-running bridge's visibility.
  final String Function() activeWorkspaceId;

  /// Reserved name for the client row this controller itself creates and
  /// manages. Never matches a name a future Settings screen lets the user
  /// choose for their own registered agents, so [_resolveActiveClient] only
  /// ever touches rows it created.
  /// Reserved name for the client row this controller mints for its own
  /// bridge on every [start].
  ///
  /// Public because the Settings UI must be able to tell this row apart from
  /// the ones a user registered: it is infrastructure, not a client anyone
  /// chose. Revoking it individually would kill the bridge while leaving
  /// `mcp-endpoint.json` in place, so the token in that file authenticates
  /// against a dead row and every agent request fails with a bare
  /// "token is invalid" — with nothing on screen explaining why.
  static const String systemClientName = 'ShellVibe (this device)';

  McpHttpTransport? _transport;
  Future<void>? _startFuture;

  McpServerController({
    required this.transportFactory,
    required this.clients,
    required this.onRequest,
    required this.isVaultAvailable,
    required this.activeWorkspaceId,
  });

  bool get isRunning => _transport?.isRunning ?? false;

  /// The bound port, or `null` while stopped.
  int? get port => _transport?.port;

  /// Starts the transport and writes `mcp-endpoint.json`.
  ///
  /// Concurrent calls collapse onto the same in-flight attempt (mirroring
  /// `_ensureDeviceLinkServer`'s `_deviceLinkServerStartup` pattern in
  /// `terminal_tabs_notifier.dart`) so two near-simultaneous callers — e.g.
  /// the app boot sequence and a user flipping the Settings toggle in the
  /// same instant — can never race each other into binding two ports.
  Future<void> start() {
    final inFlight = _startFuture;
    if (inFlight != null) return inFlight;

    final future = _start().whenComplete(() {
      _startFuture = null;
    });
    _startFuture = future;
    return future;
  }

  Future<void> _start() async {
    if (isRunning) return;

    if (Platform.isIOS || Platform.isAndroid) {
      throw StateError(
        'The MCP server is a desktop-only capability and must not start on '
        'iOS/Android (see McpServerController class docstring).',
      );
    }

    if (!isVaultAvailable()) {
      throw StateError(
        'Cannot start the MCP server while the vault is locked or unlocking.',
      );
    }

    final transport = transportFactory(
      onRequest: _guardedOnRequest,
      authenticate: _authenticate,
    );

    final boundPort = await transport.start();
    _transport = transport;

    try {
      final (:clientId, :rawToken) = await _resolveActiveClient();
      await McpEndpointFile.write(port: boundPort, token: rawToken, pid: pid);
      // clientId is not persisted anywhere beyond the row `createClient`
      // already wrote — it exists here only so a future caller can log which
      // client this boot minted without a second DB round trip.
      assert(clientId.isNotEmpty);
    } on Object {
      // Never leave a bound, discoverable-in-principle HTTP server running
      // with no way for a bridge to learn its port/token — that is a server
      // silently listening for nobody, not a safe degraded state.
      _transport = null;
      await transport.stop();
      rethrow;
    }
  }

  /// Stops the transport and removes `mcp-endpoint.json`.
  ///
  /// The file is deleted **before** the transport stops, not after — see
  /// `mcp-endpoint.json`'s own docstring for why the ordering matters: a
  /// bridge that reads the file mid-shutdown must see "gone" (which it can
  /// report to its agent as a clear "app not running") rather than "present,
  /// but the port refuses connections", which reads as a transient network
  /// blip worth retrying.
  Future<void> stop() async {
    // Wait out any start() already in flight so a stop() issued right after
    // a start() (e.g. the vault locking mid-boot) cannot finish before the
    // server it is meant to stop has even started.
    final inFlightStart = _startFuture;
    if (inFlightStart != null) {
      await inFlightStart.catchError((_) {});
    }

    final transport = _transport;
    _transport = null;
    await McpEndpointFile.delete();
    if (transport != null) await transport.stop();
  }

  Future<String?> _authenticate(String bearerToken) async {
    final client = await clients.authenticate(bearerToken);
    if (client != null) return client.id;

    // The presented token is dead. If it is the one this server itself handed
    // to the bridge, the row behind it was deleted or revoked out from under
    // us — the user wiping clients, or the panic button — and every agent
    // request from here on would fail with a bare "token is invalid" that
    // names nothing the user could act on. Mint a replacement and rewrite
    // `mcp-endpoint.json` so the bridge recovers on its next call.
    //
    // This is deliberately keyed to the endpoint file's own token: any OTHER
    // unknown token is a genuine authentication failure and must stay one.
    // Re-minting on an arbitrary bad token would turn the bearer check into
    // a formality.
    final endpoint = await McpEndpointFile.read();
    if (endpoint == null || endpoint.token != bearerToken) return null;

    final boundPort = _transport?.port;
    if (boundPort == null) return null;

    try {
      final (:clientId, :rawToken) = await _resolveActiveClient();
      await McpEndpointFile.write(port: boundPort, token: rawToken, pid: pid);
      // The caller's request still fails: it presented the old token, and
      // honouring it would mean accepting a credential that was revoked.
      // The bridge re-reads the file on its next launch and succeeds then.
      assert(clientId.isNotEmpty);
    } on Object {
      // A failed re-mint must not turn into a successful authentication.
      return null;
    }
    return null;
  }

  /// Wraps [onRequest] with the vault gate documented on the class. See
  /// [McpVaultUnavailableException] for why this throws rather than trying
  /// to shape a tool-specific `VAULT_LOCKED` response itself.
  Future<Object?> _guardedOnRequest(
    String clientId,
    JsonRpcRequest request,
  ) async {
    if (!isVaultAvailable()) {
      throw const McpVaultUnavailableException();
    }
    return onRequest(clientId, request);
  }

  /// Ensures the workspace's MCP client row exists and returns its id and a
  /// **fresh** raw bearer token for it.
  ///
  /// `McpClientRepository.createClient` (see its docstring) is the only
  /// moment a raw token exists outside an agent's own config — the database
  /// keeps [McpToken.hash] of it, never the token itself, so a row this
  /// method didn't just create is not one it can hand a usable token back
  /// for. Rather than treat that as a dead end, this always mints a fresh
  /// client (revoking whatever stale row this controller left behind under
  /// [systemClientName] last time) on every [start]. That is safe, not
  /// wasteful, because nothing external is meant to depend on the token
  /// surviving a restart: `mcp-endpoint.json` "is regenerated fresh every
  /// time the app starts the MCP server" (see that file's own docstring),
  /// and the `shellvibe-mcp` bridge reads it live on every launch rather
  /// than caching a token in an agent's static config. A smaller validity
  /// window on every boot is a feature here, not a limitation. Rows this
  /// controller does not own — a name a future Settings screen lets the
  /// user pick for their own registered agents — are never touched.
  Future<({String clientId, String rawToken})> _resolveActiveClient() async {
    final workspaceId = activeWorkspaceId();
    final existing = await clients.listClients(workspaceId);
    // Delete rather than revoke. A revoked row is kept around so a *user's*
    // token fails cleanly and stays visible in Settings as something they
    // once issued; neither applies to this one. It is minted fresh on every
    // start, so revoking instead of deleting would grow an unbounded list of
    // dead infrastructure rows — one per app launch — that the user never
    // created and cannot act on. The audit log is unaffected: it copies
    // client labels at write time and holds no foreign key into this table.
    final stale = existing.where((client) => client.name == systemClientName);
    for (final client in stale) {
      await clients.deleteClient(client.id);
    }

    final (clientId, rawToken) = await clients.createClient(
      workspaceId: workspaceId,
      name: systemClientName,
    );
    return (clientId: clientId, rawToken: rawToken);
  }
}

/// Owns the app's single [McpServerController] instance. `keepAlive` for the
/// same reason `mcpSessionPoolProvider` is (`mcp_providers.dart`): an
/// autoDispose controller would tear down a running server — and every
/// session an agent has open through it — the instant nothing happened to be
/// watching this provider, e.g. the user navigating away from the AI Access
/// settings screen. The server's lifetime must track the app's, not a
/// widget's.
@Riverpod(keepAlive: true)
McpServerController mcpServerController(Ref ref) {
  final repository = ref.watch(mcpClientRepositoryProvider);

  final controller = McpServerController(
    transportFactory: ({required onRequest, required authenticate}) =>
        McpHttpTransport(onRequest: onRequest, authenticate: authenticate),
    clients: repository,
    onRequest: ref.watch(mcpRequestDispatcherProvider).handle,
    isVaultAvailable: () => _vaultAllowsMcp(ref.read(vaultProvider)),
    activeWorkspaceId: () => ref.read(activeWorkspaceIdProvider),
  );

  // Mirrors `TerminalTabsNotifier`'s `ref.listen(vaultProvider, ...)` for
  // Device Link: a lock transition stops the server outright rather than
  // relying solely on the per-request `_guardedOnRequest` check, so no
  // socket is left listening — even harmlessly — while the vault is locked.
  ref.listen(vaultProvider, (previous, next) {
    if (_vaultAllowsMcp(next)) return;
    unawaited(controller.stop());
  });

  ref.onDispose(() {
    unawaited(controller.stop());
  });

  return controller;
}

bool _vaultAllowsMcp(AsyncValue<VaultState> vault) {
  return vault.hasValue &&
      !vault.isLoading &&
      !vault.hasError &&
      vault.value!.allowsDeviceLink;
}
