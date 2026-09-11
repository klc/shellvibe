import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../../../../app/theme/shellvibe_tokens.dart';
import '../../../../app/widgets/adaptive_modal.dart';
import '../../../../app/widgets/shellvibe_ui.dart';
import '../../../../core/constants/app_constants.dart';
import '../../../../shared/database/app_database.dart';
import '../../../../shared/providers/database_providers.dart';

/// Every host key trusted on this device, ordered the way the list reads:
/// hostname first, then port for the multi-daemon case.
final knownHostsListProvider = FutureProvider<List<KnownHost>>((ref) async {
  final hosts = await ref.watch(knownHostsDaoProvider).getAllKnownHosts();
  final sorted = [...hosts]
    ..sort((a, b) {
      final byName = a.hostname.toLowerCase().compareTo(
        b.hostname.toLowerCase(),
      );
      return byName != 0 ? byName : a.port.compareTo(b.port);
    });
  return sorted;
});

/// Key-rotation surface for `known_hosts`.
///
/// The connect flow deliberately refuses a changed key (see
/// `SSHSessionManager._verifyHostKey`), so a reinstalled server can only be
/// reached again by forgetting its old key here — a deliberate act outside the
/// handshake, which is what makes it safe. Forgetting a key drops the host back
/// to Trust On First Use on the next connection.
final class KnownHostsSettingsSection extends ConsumerWidget {
  const KnownHostsSettingsSection({super.key});

  Future<void> _forgetHost(
    BuildContext context,
    WidgetRef ref,
    KnownHost host,
  ) async {
    final tokens = ShellVibeTokens.resolve(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => ShadDialog.alert(
        title: const Text('Forget Host Key'),
        description: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              '${AppConstants.appName} will stop trusting the stored key '
              'for '
              '${host.hostname}:${host.port}. The next connection asks you to '
              'verify the key it is offered, exactly like a first connection.',
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: tokens.textSecondary),
            ),
            const SizedBox(height: 12),
            Text(
              'Only do this when you know why the key changed — a server '
              'reinstall or a deliberate key rotation. An unexplained change '
              'can mean the connection is being intercepted.',
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: tokens.danger),
            ),
            const SizedBox(height: 12),
            SelectableText(
              host.fingerprintSha256,
              style: shellvibeMono(context, size: 12),
            ),
          ],
        ),
        actions: adaptiveDialogActions(context, [
          ShellVibeButton.secondary(
            key: const Key('forget_known_host_cancel_button'),
            label: 'Cancel',
            onPressed: () => Navigator.of(dialogContext).pop(false),
          ),
          ShellVibeButton.danger(
            key: const Key('forget_known_host_confirm_button'),
            label: 'Forget Key',
            onPressed: () => Navigator.of(dialogContext).pop(true),
          ),
        ]),
        actionsAxis: adaptiveDialogActionsAxis(context),
      ),
    );
    if (confirmed != true) return;

    await ref.read(knownHostsDaoProvider).deleteKnownHost(host.id);
    ref.invalidate(knownHostsListProvider);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = ShellVibeTokens.resolve(context);
    final hosts = ref.watch(knownHostsListProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'A key is stored the first time you trust a server. If that server is '
          'reinstalled its key changes, and ${AppConstants.appName} refuses '
          'the connection until '
          'you forget the old key here.',
          style: Theme.of(
            context,
          ).textTheme.bodyMedium?.copyWith(color: tokens.textMuted),
        ),
        const SizedBox(height: 12),
        ShadCard(
          child: hosts.when(
            loading: () => const Padding(
              padding: EdgeInsets.all(16),
              child: Center(child: CircularProgressIndicator()),
            ),
            error: (error, _) => ListTile(
              key: const Key('known_hosts_error'),
              leading: Icon(LucideIcons.circleAlert, color: tokens.danger),
              title: Text('Could not load known hosts: $error'),
            ),
            data: (list) => _buildList(context, ref, list, tokens),
          ),
        ),
      ],
    );
  }

  Widget _buildList(
    BuildContext context,
    WidgetRef ref,
    List<KnownHost> hosts,
    ShellVibeTokens tokens,
  ) {
    if (hosts.isEmpty) {
      return const ListTile(
        key: Key('known_hosts_empty'),
        leading: Icon(LucideIcons.shieldQuestionMark),
        title: Text('No host keys have been trusted on this device yet.'),
      );
    }

    return Column(
      children: [
        for (final host in hosts) ...[
          if (host != hosts.first) const Divider(),
          ListTile(
            key: Key('known_host_${host.id}'),
            leading: const Icon(LucideIcons.shieldCheck),
            title: Text('${host.hostname}:${host.port}'),
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${host.keyType} · trusted ${_formatDate(host.firstSeenAt)}',
                  style: Theme.of(
                    context,
                  ).textTheme.bodySmall?.copyWith(color: tokens.textMuted),
                ),
                const SizedBox(height: 2),
                SelectableText(
                  host.fingerprintSha256,
                  style: shellvibeMono(context, size: 11),
                ),
              ],
            ),
            isThreeLine: true,
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                ShellVibeIconButton(
                  key: Key('copy_known_host_${host.id}'),
                  icon: LucideIcons.copy,
                  tooltip: 'Copy fingerprint',
                  onPressed: () => Clipboard.setData(
                    ClipboardData(text: host.fingerprintSha256),
                  ),
                ),
                ShellVibeIconButton(
                  key: Key('forget_known_host_${host.id}'),
                  icon: LucideIcons.trash2,
                  tooltip: 'Forget host key',
                  onPressed: () => _forgetHost(context, ref, host),
                  danger: true,
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }

  String _formatDate(DateTime date) {
    final local = date.toLocal();
    return '${local.year}-${local.month.toString().padLeft(2, '0')}-'
        '${local.day.toString().padLeft(2, '0')}';
  }
}
