import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../../app/theme/shellvibe_tokens.dart';
import '../../../../app/widgets/adaptive_modal.dart';
import '../../../../app/widgets/shellvibe_ui.dart';
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
    return showAdaptivePanel<DeviceLinkSessionInfo>(
      context: context,
      isScrollControlled: true,
      builder: (context) => DeviceLinkSessionPickerSheet(
        sessions: sessions,
        selectedSessionId: selectedSessionId,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tokens = ShellVibeTokens.resolve(context);
    return SafeArea(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxHeight: 520),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.baseline,
                textBaseline: TextBaseline.alphabetic,
                children: [
                  Text('Sessions', style: theme.textTheme.titleMedium),
                  const SizedBox(width: 10),
                  Text(
                    sessions.length == 1 ? '1 open' : '${sessions.length} open',
                    style: shellvibeMono(context, size: 11),
                  ),
                ],
              ),
              const SizedBox(height: 14),
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
                    separatorBuilder: (_, _) => const SizedBox(height: 8),
                    itemBuilder: (context, index) {
                      final session = sessions[index];
                      final selected = session.id == selectedSessionId;
                      final isLocal = session.type == 'local';
                      // A 62px row with a live dot, mono detail line and no
                      // avatar: on a phone the session's name and whether it
                      // is alive are the only two things worth the width.
                      return InkWell(
                        key: Key('device_link_session_${session.id}'),
                        onTap: () => Navigator.of(context).pop(session),
                        borderRadius: BorderRadius.circular(11),
                        child: Container(
                          height: 62,
                          padding: const EdgeInsets.symmetric(horizontal: 14),
                          decoration: BoxDecoration(
                            color: selected
                                ? tokens.brand.withValues(alpha: 0.12)
                                : Colors.transparent,
                            borderRadius: BorderRadius.circular(11),
                            border: Border.all(
                              color: selected
                                  ? tokens.brand.withValues(alpha: 0.24)
                                  : tokens.border,
                            ),
                          ),
                          child: Row(
                            children: [
                              ShellVibeStatusDot(
                                state: selected
                                    ? ShellVibeDotState.online
                                    : ShellVibeDotState.idle,
                                size: 8,
                              ),
                              const SizedBox(width: 13),
                              Expanded(
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      session.title,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        fontSize: 15,
                                        fontWeight: FontWeight.w600,
                                        letterSpacing: -0.2,
                                        color: selected
                                            ? tokens.textPrimary
                                            : tokens.textSecondary,
                                      ),
                                    ),
                                    const SizedBox(height: 3),
                                    Text(
                                      '${isLocal ? 'local' : session.type} · '
                                      '${session.id}',
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: shellvibeMono(
                                        context,
                                        size: 11,
                                        color: tokens.textSubtle,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              if (selected) ...[
                                const SizedBox(width: 10),
                                Icon(
                                  LucideIcons.check,
                                  size: 16,
                                  color: tokens.brand,
                                ),
                              ],
                            ],
                          ),
                        ),
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
