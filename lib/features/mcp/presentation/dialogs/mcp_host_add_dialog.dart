import 'dart:async';

import 'package:material_ui/material_ui.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../../../../app/theme/shellvibe_tokens.dart';
import '../../../../app/widgets/adaptive_modal.dart';
import '../../../../app/widgets/shellvibe_ui.dart';
import '../../domain/models/mcp_models.dart';
import 'mcp_command_approval_dialog.dart';

/// Approval prompt for an agent's `add_host`: the address it proposed, and
/// the user's own choice of credentials for it.
///
/// Like the other approval dialogs, every way out other than "Add host"
/// (Deny, the barrier, Escape, a back gesture, the countdown) is a refusal.
class McpHostAddDialog extends StatefulWidget {
  final HostAddRequest request;
  final DateTime expiresAt;

  const McpHostAddDialog({
    super.key,
    required this.request,
    required this.expiresAt,
  });

  static Future<HostAddDecision?> show(
    BuildContext context, {
    required HostAddRequest request,
    required DateTime expiresAt,
  }) {
    return showDialog<HostAddDecision>(
      context: context,
      barrierDismissible: false,
      builder: (_) => McpHostAddDialog(request: request, expiresAt: expiresAt),
    );
  }

  @override
  State<McpHostAddDialog> createState() => _McpHostAddDialogState();
}

class _McpHostAddDialogState extends State<McpHostAddDialog> {
  late Timer _ticker;
  late final Timer _armTimer;
  late Duration _remaining;
  bool _resolved = false;
  bool _armed = false;
  String? _identityId;

  @override
  void initState() {
    super.initState();
    // Nothing pre-selected: which credential the agent's address gets is the
    // user's own pick, not a default the agent could steer.
    _armTimer = Timer(mcpApprovalArmDelay, () {
      if (mounted) setState(() => _armed = true);
    });
    _remaining = widget.expiresAt.difference(DateTime.now().toUtc());
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) => _tick());
  }

  @override
  void dispose() {
    _ticker.cancel();
    _armTimer.cancel();
    super.dispose();
  }

  void _tick() {
    final remaining = widget.expiresAt.difference(DateTime.now().toUtc());
    if (remaining.isNegative || remaining == Duration.zero) {
      _ticker.cancel();
      _resolve(HostAddDecision.denied);
      return;
    }
    if (mounted) setState(() => _remaining = remaining);
  }

  void _resolve(HostAddDecision decision) {
    if (_resolved || !mounted) return;
    _resolved = true;
    Navigator.of(context).pop(decision);
  }

  String _identityLabel(String? id) {
    final identity = widget.request.identities
        .where((i) => i.id == id)
        .firstOrNull;
    if (identity == null) return 'None (add credentials later)';
    return identity.username.isEmpty
        ? identity.title
        : '${identity.title} (${identity.username})';
  }

  @override
  Widget build(BuildContext context) {
    final tokens = ShellVibeTokens.resolve(context);
    final request = widget.request;
    final bodyStyle = Theme.of(context).textTheme.bodySmall;
    final mono = shellvibeMono(context, size: 13, color: tokens.textPrimary);
    final address =
        '${request.username == null ? '' : '${request.username}@'}'
        '${request.hostname}${request.port == 22 ? '' : ':${request.port}'}';
    final clamped = _remaining.isNegative ? Duration.zero : _remaining;

    Widget field(String name, Widget value) => Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            name,
            style: bodyStyle?.copyWith(
              color: tokens.textSecondary,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 4),
          value,
        ],
      ),
    );

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        _resolve(HostAddDecision.denied);
      },
      child: ShadDialog(
        key: const Key('mcp_host_add_dialog'),
        constraints: const BoxConstraints(maxWidth: 520),
        title: const Text('Add this host?'),
        description: Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Text(
            '${request.clientName} wants to save a new server. It will not '
            'get access to it until it asks and you allow it. Connect to it '
            'once from a terminal tab to trust its host key.',
            style: bodyStyle?.copyWith(color: tokens.textSecondary),
          ),
        ),
        actions: adaptiveDialogActions(context, [
          ShellVibeButton.secondary(
            key: const Key('mcp_host_add_deny_button'),
            label: 'Deny',
            onPressed: () => _resolve(HostAddDecision.denied),
          ),
          ShellVibeButton(
            key: const Key('mcp_host_add_approve_button'),
            label: 'Add host',
            onPressed: _armed
                ? () => _resolve(
                    HostAddDecision(approved: true, identityId: _identityId),
                  )
                : null,
          ),
        ]),
        actionsAxis: adaptiveDialogActionsAxis(context),
        child: Material(
          type: MaterialType.transparency,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              field(
                'Label',
                Text(
                  visibleControlChars(request.label),
                  key: const Key('mcp_host_add_label'),
                  style: mono,
                ),
              ),
              field(
                'Address',
                SelectableText(
                  address,
                  key: const Key('mcp_host_add_address'),
                  style: mono,
                ),
              ),
              field(
                'Credentials',
                ShadSelect<String?>(
                  key: const Key('mcp_host_add_identity'),
                  initialValue: _identityId,
                  minWidth: 300,
                  onChanged: (id) => setState(() => _identityId = id),
                  selectedOptionBuilder: (context, id) =>
                      Text(_identityLabel(id)),
                  options: [
                    ShadOption<String?>(
                      value: null,
                      child: Text(_identityLabel(null)),
                    ),
                    for (final identity in request.identities)
                      ShadOption<String?>(
                        value: identity.id,
                        child: Text(_identityLabel(identity.id)),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              Align(
                alignment: Alignment.centerRight,
                child: Text(
                  'Expires in ${clamped.inMinutes}m '
                  '${(clamped.inSeconds % 60).toString().padLeft(2, '0')}s',
                  style: shellvibeMono(
                    context,
                    size: 11,
                    color: tokens.textSubtle,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
