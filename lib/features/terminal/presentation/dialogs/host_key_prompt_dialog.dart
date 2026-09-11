import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../../../../app/theme/shellvibe_tokens.dart';
import '../../../../app/widgets/adaptive_modal.dart';
import '../../../../app/widgets/shellvibe_ui.dart';
import '../../../../core/network/ssh_session_manager.dart';

/// Blocking prompt shown during the SSH handshake when a host key is unknown
/// (Trust On First Use) or no longer matches the stored fingerprint.
///
/// Returning `true` trusts an unknown key and stores it in `known_hosts`;
/// changed keys cannot be accepted by this normal connection flow.
class HostKeyPromptDialog extends StatelessWidget {
  final String hostname;
  final int port;
  final String keyType;
  final String fingerprint;
  final HostKeyVerificationStatus status;

  const HostKeyPromptDialog({
    super.key,
    required this.hostname,
    required this.port,
    required this.keyType,
    required this.fingerprint,
    required this.status,
  });

  static Future<bool?> show(
    BuildContext context, {
    required String hostname,
    required int port,
    required String keyType,
    required String fingerprint,
    required HostKeyVerificationStatus status,
  }) {
    return showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => HostKeyPromptDialog(
        hostname: hostname,
        port: port,
        keyType: keyType,
        fingerprint: fingerprint,
        status: status,
      ),
    );
  }

  bool get _isMismatch => status == HostKeyVerificationStatus.mismatch;

  @override
  Widget build(BuildContext context) {
    final tokens = ShellVibeTokens.resolve(context);
    final accent = _isMismatch ? tokens.danger : tokens.brand;
    // Size and tracking stay on the ramp; only the colour is a token decision.
    final bodyStyle = Theme.of(context).textTheme.bodySmall;

    return ShadDialog.alert(
      title: Row(
        children: [
          Icon(_isMismatch ? Icons.gpp_bad : Icons.help_outline, color: accent),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              _isMismatch ? 'WARNING: Host Key Changed' : 'Unknown Host Key',
            ),
          ),
        ],
      ),
      description: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            _isMismatch
                ? 'The key presented by $hostname:$port does not match the key '
                      'stored on this device. This can mean the server was '
                      'reinstalled — or that someone is intercepting the '
                      'connection (man-in-the-middle attack).'
                : 'The authenticity of $hostname:$port cannot be established. '
                      'Verify the fingerprint below through a trusted channel '
                      '(e.g. `ssh-keygen -lf /etc/ssh/ssh_host_${keyType}_key.pub` '
                      'on the server) before trusting it.',
            style: bodyStyle?.copyWith(
              color: _isMismatch ? tokens.danger : tokens.textSecondary,
            ),
          ),
          const SizedBox(height: 16),
          Text(
            'Key type: $keyType',
            style: bodyStyle?.copyWith(color: tokens.textSecondary),
          ),
          const SizedBox(height: 4),
          Row(
            children: [
              Expanded(
                child: SelectableText(
                  fingerprint,
                  style: shellvibeMono(context, size: 12),
                ),
              ),
              ShellVibeIconButton(
                icon: Icons.copy,
                tooltip: 'Copy fingerprint',
                onPressed: () =>
                    Clipboard.setData(ClipboardData(text: fingerprint)),
              ),
            ],
          ),
          // A mismatch is a dead end inside the handshake, so point at the one
          // place the stored key can be rotated instead.
          if (_isMismatch) ...[
            const SizedBox(height: 16),
            Text(
              'If you know why the key changed — the server was reinstalled or '
              'its key was rotated — forget the stored key under '
              'Settings → Security → Known Host Keys, then connect again and '
              'verify the new fingerprint.',
              style: bodyStyle?.copyWith(color: tokens.textSecondary),
            ),
          ],
        ],
      ),
      actions: adaptiveDialogActions(context, [
        ShellVibeButton.secondary(
          key: const Key('host_key_reject_button'),
          label: 'Cancel Connection',
          onPressed: () => Navigator.of(context).pop(false),
        ),
        if (!_isMismatch)
          ShellVibeButton(
            key: const Key('host_key_accept_button'),
            label: 'Trust & Continue',
            onPressed: () => Navigator.of(context).pop(true),
          ),
      ]),
      actionsAxis: adaptiveDialogActionsAxis(context),
    );
  }
}
