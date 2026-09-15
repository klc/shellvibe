import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../../../../core/network/ssh_session_manager.dart';
import '../../../terminal/presentation/dialogs/host_key_prompt_dialog.dart';
import '../../../terminal/presentation/notifiers/terminal_tabs_notifier.dart';
import '../../../vault/domain/models/identity_model.dart';
import '../../../vault/presentation/notifiers/identities_notifier.dart';
import '../../presentation/dialogs/connect_credentials_dialog.dart';
import '../models/host_model.dart';

/// Opens a terminal session for a host, with the prompts that go with it.
///
/// Connecting is not one call: stored credentials have to be decrypted, a host
/// with no identity has to be asked for one, and an unknown host key has to be
/// shown to the user before the handshake continues. Every place that offers
/// "connect to this host" needs all three, so they live here rather than being
/// written out again next to each button.
///
/// Holds a [BuildContext] and is therefore built per use and thrown away, like
/// the dialogs it opens.
class HostLauncher {
  final BuildContext context;
  final WidgetRef ref;

  const HostLauncher({required this.context, required this.ref});

  /// Opens a session for [host] and returns its tab id, or null when the
  /// credentials could not be read or the user called the connection off.
  Future<String?> openSession(HostModel host) async {
    final resolved = await resolveIdentity(host);
    if (!resolved.ok) return null;

    await ref
        .read(terminalTabsProvider.notifier)
        .openTabForHost(
          host,
          identity: resolved.identity,
          onHostKeyPrompt: promptHostKey,
        );

    return ref.read(terminalTabsProvider).activeTabId;
  }

  /// [openSession] plus the move to the terminal, which is what a plain
  /// "connect" means everywhere it is offered.
  Future<void> connect(HostModel host) async {
    await openSession(host);
    if (context.mounted) {
      GoRouter.maybeOf(context)?.go('/terminal');
    }
  }

  /// Decrypts a host's stored credentials, or asks for them.
  ///
  /// `ok: false` aborts instead of connecting without the credentials the host
  /// was saved with.
  Future<({bool ok, IdentityModel? identity})> resolveIdentity(
    HostModel host,
  ) async {
    // "(None — Prompt on Connect)" has to actually prompt. Handing the
    // handshake no credentials at all just walks into "all authentication
    // methods failed", with nowhere for the password to have been typed.
    if (host.identityId == null) {
      final entered = await ConnectCredentialsDialog.show(
        context,
        hostLabel: host.label,
        hostname: host.hostname,
        port: host.port,
        username: host.username ?? '',
      );
      // Cancelled: the user called the connection off, so it is not an error.
      if (entered == null) return (ok: false, identity: null);
      return (
        ok: true,
        // Never persisted, and never given an id that could collide with a
        // stored identity: it lives for this connection attempt alone.
        identity: IdentityModel(
          id: 'prompt:${host.id}',
          workspaceId: host.workspaceId,
          title: 'Prompted credentials',
          username: entered.username,
          authType: 'password',
          password: entered.password,
          createdAt: DateTime.now(),
        ),
      );
    }
    try {
      final identity = await ref
          .read(identitiesProvider.notifier)
          .getDecryptedIdentity(host.identityId!);
      return (ok: true, identity: identity);
    } catch (e) {
      if (context.mounted) {
        ShadToaster.of(context).show(
          ShadToast.destructive(
            description: Text('Cannot read stored credentials: $e'),
          ),
        );
      }
      return (ok: false, identity: null);
    }
  }

  Future<bool> promptHostKey(
    String hostname,
    int port,
    String keyType,
    String fingerprint,
    HostKeyVerificationStatus status,
  ) async {
    if (!context.mounted) return false;
    final approved = await HostKeyPromptDialog.show(
      context,
      hostname: hostname,
      port: port,
      keyType: keyType,
      fingerprint: fingerprint,
      status: status,
    );
    return approved ?? false;
  }
}
