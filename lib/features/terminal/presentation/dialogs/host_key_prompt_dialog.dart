import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

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

  bool get _isMismatch => status == HostKeyVerificationStatus.mismatch;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final accent = _isMismatch
        ? theme.colorScheme.error
        : theme.colorScheme.primary;

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
            style: theme.textTheme.bodySmall?.copyWith(
              color: _isMismatch ? theme.colorScheme.error : null,
            ),
          ),
          const SizedBox(height: 16),
          Text('Key type: $keyType', style: theme.textTheme.bodySmall),
          const SizedBox(height: 4),
          Row(
            children: [
              Expanded(
                child: SelectableText(
                  fingerprint,
                  style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
                ),
              ),
              IconButton(
                icon: const Icon(Icons.copy, size: 16),
                tooltip: 'Copy fingerprint',
                onPressed: () =>
                    Clipboard.setData(ClipboardData(text: fingerprint)),
              ),
            ],
          ),
        ],
      ),
      actions: [
        ShadButton.outline(
          key: const Key('host_key_reject_button'),
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('Cancel Connection'),
        ),
        if (!_isMismatch)
          ShadButton(
            key: const Key('host_key_accept_button'),
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Trust & Continue'),
          ),
      ],
    );
  }
}
