import 'dart:io';

import '../../../../core/network/ssh_session_manager.dart';
import '../../../vault/domain/models/identity_model.dart';
import '../../data/repositories/hosts_repository.dart';
import '../models/host_model.dart';

/// Turns a stored [HostModel] into the things an SSH connect actually needs:
/// the ordered ProxyJump chain to dial through, and the [SSHConnectConfig]
/// for one hop.
///
/// Both used to live inside the terminal's tab notifier, which made them
/// unreachable from anything that wants an SSH client without a terminal —
/// notably a port forward started from the Tunnels screen. Neither depends on
/// a tab, a terminal or a widget, so they live here instead and the terminal
/// is now one of two callers.
class SshConnectPlanner {
  final HostsRepository hostsRepository;

  const SshConnectPlanner(this.hostsRepository);

  /// The jump hosts to connect through before [target], nearest-first — i.e.
  /// in the order they must be dialed, each one tunneling the next.
  ///
  /// Returns empty for a host with no `jumpHostId`. Throws on a cycle, an
  /// over-long chain, or a jump host that has since been deleted, rather than
  /// silently connecting direct to a host the user asked to reach through a
  /// bastion.
  Future<List<HostModel>> resolveJumpChain(HostModel target) async {
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
  SSHConnectConfig buildConnectConfig(
    HostModel host,
    IdentityModel? identity, {
    HostKeyPromptCallback? onHostKeyPrompt,
  }) {
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
      onHostKeyPrompt: onHostKeyPrompt,
    );
  }
}
