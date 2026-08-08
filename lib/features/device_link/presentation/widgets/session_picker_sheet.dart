import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../../core/network/device_link/device_link_protocol.dart';

/// Presents the sessions advertised by the desktop's `hello_ack` response.
///
/// The sheet returns the selected session and never retains the list after it
/// is dismissed. That keeps this first-time pairing surface independent from
/// the persistent pairing records planned for Phase 5.
final class DeviceLinkSessionPickerSheet extends StatelessWidget {
  final List<DeviceLinkSessionInfo> sessions;
  final String? selectedSessionId;

  const DeviceLinkSessionPickerSheet({
    super.key,
    required this.sessions,
    this.selectedSessionId,
  });

  static Future<DeviceLinkSessionInfo?> show(
    BuildContext context, {
    required List<DeviceLinkSessionInfo> sessions,
    String? selectedSessionId,
  }) {
    return showModalBottomSheet<DeviceLinkSessionInfo>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) => DeviceLinkSessionPickerSheet(
        sessions: sessions,
        selectedSessionId: selectedSessionId,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SafeArea(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxHeight: 520),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Choose a terminal session',
                style: theme.textTheme.titleLarge,
              ),
              const SizedBox(height: 6),
              Text(
                'Select the desktop session to open on this device.',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 12),
              if (sessions.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 28),
                  child: Column(
                    children: [
                      Icon(Icons.terminal_outlined, size: 32),
                      SizedBox(height: 10),
                      Text('No live terminal sessions found.'),
                    ],
                  ),
                )
              else
                Flexible(
                  child: ListView.separated(
                    shrinkWrap: true,
                    itemCount: sessions.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 6),
                    itemBuilder: (context, index) {
                      final session = sessions[index];
                      final selected = session.id == selectedSessionId;
                      final isLocal = session.type == 'local';
                      return ListTile(
                        key: Key('device_link_session_${session.id}'),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                          side: BorderSide(
                            color: selected
                                ? theme.colorScheme.primary
                                : theme.colorScheme.outlineVariant,
                          ),
                        ),
                        leading: CircleAvatar(
                          backgroundColor: theme.colorScheme.primaryContainer,
                          child: Icon(
                            isLocal
                                ? Icons.computer_outlined
                                : Icons.terminal_outlined,
                            color: theme.colorScheme.onPrimaryContainer,
                          ),
                        ),
                        title: Text(
                          session.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        subtitle: Text('${session.type} · ${session.id}'),
                        trailing: selected
                            ? Icon(
                                LucideIcons.check,
                                color: theme.colorScheme.primary,
                              )
                            : const Icon(Icons.chevron_right),
                        onTap: () => Navigator.of(context).pop(session),
                      );
                    },
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
