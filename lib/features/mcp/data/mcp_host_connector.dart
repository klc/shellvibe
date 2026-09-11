import 'dart:io';

import 'package:dartssh2/dartssh2.dart';

import '../../../core/network/ssh_session_manager.dart';
import '../../../shared/database/daos/known_hosts_dao.dart';
import '../../hosts/data/repositories/hosts_repository.dart';
import '../../hosts/domain/models/host_model.dart';
import '../../vault/data/repositories/vault_repository.dart';
import '../../vault/domain/models/identity_model.dart';
import '../domain/models/mcp_models.dart';
import '../domain/models/mcp_enums.dart';

/// A live SSH connection built by [McpHostConnector.connect]: the target
/// host's session manager plus the ordered jump hops it tunnels through.
class McpConnection {
  /// The manager holding the client for the requested host itself.
  final SSHSessionManager target;

  /// Jump-hop managers in connection order (outermost hop first, the hop
  /// nearest [target] last) — the same order [McpHostConnector.connect]
  /// dials them in.
  final List<SSHSessionManager> jumpManagers;

  const McpConnection({required this.target, required this.jumpManagers});

  /// Tears the connection down: [target] first, then the jump hops in
  /// reverse (innermost first). Closing [target] before unwinding the tunnel
  /// it rides on avoids tearing a hop out from under a still-open channel.
  Future<void> close() async {
    await target.close();
    for (final jumpManager in jumpManagers.reversed) {
      await jumpManager.close();
    }
  }
}

/// Resolves a [HostModel] into a live [McpConnection] for the MCP layer.
///
/// This class **duplicates** `TerminalTabsNotifier._connectSshTab`,
/// `._buildConnectConfig` and `._resolveJumpChain`
/// (`lib/features/terminal/presentation/notifiers/terminal_tabs_notifier.dart`)
/// field-for-field, and that duplication is a decision, not an oversight.
/// Extracting one shared `SshConnector` was considered and rejected: the
/// terminal's connect path is entangled with its reconnect, Mosh-fallback and
/// split-pane logic, and a shared abstraction able to serve both call sites
/// without risking those paths was judged not worth the payoff (see
/// `docs/mcp_plan.md`, "Bağlantı yolu — kararlaştırılmış tekrar"). The price
/// of accepting the duplication is
/// `test/unit/features/mcp/connector_parity_test.dart`, which builds the same
/// `HostModel`/`IdentityModel` pair through both paths and asserts the
/// resulting [SSHConnectConfig]s are field-for-field equal (`onHostKeyPrompt`
/// excepted, see below); it fails the moment the two drift apart.
class McpHostConnector {
  final HostsRepository hostsRepository;
  final VaultRepository vaultRepository;
  final KnownHostsDao knownHostsDao;

  McpHostConnector({
    required this.hostsRepository,
    required this.vaultRepository,
    required this.knownHostsDao,
  });

  /// Connects to [host], resolving its ProxyJump chain and every hop's
  /// identity exactly as the terminal does, and returns the resulting
  /// [McpConnection].
  ///
  /// On failure, any jump hop already connected is closed (innermost first)
  /// before the error is rethrown, so a chain that fails partway through
  /// never leaks a socket.
  Future<McpConnection> connect(HostModel host) async {
    SSHClient? viaClient;
    final jumpManagers = <SSHSessionManager>[];
    try {
      if (host.jumpHostId != null) {
        final jumpChain = await _resolveJumpChain(host);
        for (final jumpHost in jumpChain) {
          final jumpIdentity = jumpHost.identityId == null
              ? null
              : await vaultRepository.getIdentityById(jumpHost.identityId!);
          final jumpManager = SSHSessionManager(knownHostsDao: knownHostsDao);
          jumpManagers.add(jumpManager);
          final jumpConfig = _buildConnectConfig(jumpHost, jumpIdentity);
          viaClient = await jumpManager.connect(
            jumpConfig,
            viaClient: viaClient,
          );
        }
      }

      final identity = host.identityId == null
          ? null
          : await _resolveIdentity(host);
      final targetManager = SSHSessionManager(knownHostsDao: knownHostsDao);
      final config = _buildConnectConfig(host, identity);
      await targetManager.connect(config, viaClient: viaClient);

      return McpConnection(target: targetManager, jumpManagers: jumpManagers);
    } on SSHHostKeyRejectedException catch (e) {
      for (final jumpManager in jumpManagers.reversed) {
        await jumpManager.close();
      }
      // Deliberately fail-closed (see [_buildConnectConfig] on why this path
      // never prompts), but say so in terms the agent can act on: the bare
      // refusal reads as a broken tool and invites a retry loop, when the
      // only thing that can resolve it is a human verifying the fingerprint.
      throw McpToolException(
        McpErrorCode.hostKeyUntrusted,
        'Host "${host.label}" was refused because its SSH host key is not '
        'trusted yet: MCP never accepts a fingerprint on the user\'s behalf. '
        'The user needs to connect to this host once from a ShellVibe '
        'terminal tab and accept the fingerprint there; it will then '
        'connect from here too. Retrying will not help until they do. ($e)',
        details: {'hostId': host.id},
      );
    } catch (_) {
      for (final jumpManager in jumpManagers.reversed) {
        await jumpManager.close();
      }
      rethrow;
    }
  }

  /// Walks `jumpHostId` outward from [target], returning the hops in
  /// connection order: the directly-reachable outermost host first, the jump
  /// nearest [target] last. Empty when [target] has no `ProxyJump`.
  ///
  /// Throws on a missing host, a cycle, or an unreasonably long chain rather
  /// than looping forever or connecting through a broken link silently —
  /// mirrors `TerminalTabsNotifier._resolveJumpChain` exactly.
  Future<List<HostModel>> _resolveJumpChain(HostModel target) async {
    const maxHops = 8;
    final chain = <HostModel>[];
    final visited = <String>{target.id};
    var nextId = target.jumpHostId;
    while (nextId != null) {
      if (!visited.add(nextId)) {
        throw StateError(
          'ProxyJump chain for "${target.label}" contains a cycle.',
        );
      }
      if (chain.length >= maxHops) {
        throw StateError(
          'ProxyJump chain for "${target.label}" exceeds $maxHops hops.',
        );
      }
      final jumpHost = await hostsRepository.getHostById(nextId);
      if (jumpHost == null) {
        throw StateError(
          'Jump host referenced by "${target.label}" no longer exists.',
        );
      }
      chain.add(jumpHost);
      nextId = jumpHost.jumpHostId;
    }
    return chain.reversed.toList();
  }

  /// Builds the connect config for one hop (a jump host or the final
  /// target): resolves the effective username from, in order, the host's own
  /// `username` field, a `user@host` prefix embedded in the hostname, the
  /// identity's username, and finally the local OS user — matching the
  /// fallback order `ssh` itself uses rather than silently trying `root`.
  /// Mirrors `TerminalTabsNotifier._buildConnectConfig` exactly, with one
  /// deliberate exception:
  ///
  /// [onHostKeyPrompt] is always left `null`. It is not that MCP is stricter
  /// than the terminal about a bad host key — the terminal already denies a
  /// mismatch unconditionally too. The only case a callback changes is an
  /// *unknown* host: `SSHSessionManager._verifyHostKey` denies that outright
  /// when no callback is supplied, which is exactly the null-safe default
  /// this connector wants. There is no UI surface on the MCP path for a host
  /// key prompt, and there should not be one: the agent has no way to
  /// independently verify a fingerprint, so it must never be put in a
  /// position to vouch for one, and the user is not present to answer a
  /// prompt synchronously the way they are in the terminal. Leaving the
  /// parameter null turns that absence into fail-closed TOFU for free — a
  /// host the user has already trusted from the terminal connects fine
  /// because its fingerprint is in `known_hosts`; a host nobody has ever
  /// verified is refused instead of silently trusted.
  /// Resolves the host's stored credential, translating a vault failure into
  /// something the agent can act on.
  ///
  /// A credential encrypted under a previous vault key (the vault was reset,
  /// or the row was restored from another install) throws deep inside the
  /// vault repository. Left alone it surfaces to the agent as a generic
  /// internal error, which reads as "the tool is broken" rather than "this
  /// one host needs its credential re-entered" — so the agent retries the
  /// same host forever instead of telling the user or moving on.
  Future<IdentityModel?> _resolveIdentity(HostModel host) async {
    try {
      return await vaultRepository.getIdentityById(host.identityId!);
    } on Object catch (e) {
      throw McpToolException(
        McpErrorCode.internal,
        'The stored credential for host "${host.label}" could not be '
        'decrypted, so this host cannot be connected to. The user needs to '
        're-enter it in ShellVibe under Vault. Other hosts are unaffected. '
        '($e)',
        details: {'hostId': host.id},
      );
    }
  }

  SSHConnectConfig _buildConnectConfig(
    HostModel host,
    IdentityModel? identity,
  ) {
    String cleanHostname = host.hostname.trim();
    String? parsedUser;
    if (cleanHostname.contains('@')) {
      final atIndex = cleanHostname.indexOf('@');
      parsedUser = cleanHostname.substring(0, atIndex).trim();
      cleanHostname = cleanHostname.substring(atIndex + 1).trim();
    }

    final hostUser = host.username?.trim();
    final identityUser = identity?.username.trim();
    final osUser =
        Platform.environment['USER'] ?? Platform.environment['USERNAME'];
    final effectiveUsername = (hostUser != null && hostUser.isNotEmpty)
        ? hostUser
        : ((parsedUser != null && parsedUser.isNotEmpty)
              ? parsedUser
              : ((identityUser != null && identityUser.isNotEmpty)
                    ? identityUser
                    : (osUser ?? '')));

    return SSHConnectConfig(
      hostname: cleanHostname,
      port: host.port,
      username: effectiveUsername,
      password: identity?.password,
      privateKeyPem: identity?.privateKey,
      passphrase: identity?.passphrase,
      // Deliberately null — see the docstring above.
      onHostKeyPrompt: null,
    );
  }
}
