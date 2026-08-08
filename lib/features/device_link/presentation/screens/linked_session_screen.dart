import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../terminal/presentation/screens/terminal_screen.dart';
import '../controllers/linked_session_controller.dart';
import '../widgets/compose_sheet.dart';

/// Terminal surface opened on the phone after a Device Link attach.
final class DeviceLinkLinkedSessionScreen extends ConsumerStatefulWidget {
  final DeviceLinkLinkedSessionController controller;
  final VoidCallback? onClosed;
  final bool? showExtraKeys;

  const DeviceLinkLinkedSessionScreen({
    super.key,
    required this.controller,
    this.onClosed,
    this.showExtraKeys,
  });

  @override
  ConsumerState<DeviceLinkLinkedSessionScreen> createState() =>
      _DeviceLinkLinkedSessionScreenState();
}

class _DeviceLinkLinkedSessionScreenState
    extends ConsumerState<DeviceLinkLinkedSessionScreen> {
  DeviceLinkLinkedSessionController get _controller => widget.controller;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        unawaited(_controller.connect());
      }
    });
  }

  @override
  void dispose() {
    unawaited(_controller.close());
    super.dispose();
  }

  Future<void> _compose() async {
    if (!_controller.canSendInput) return;
    await DeviceLinkComposeSheet.show(
      context,
      onSubmit: _controller.sendText,
      bracketedPaste: _controller.supportsBracketedPaste,
    );
  }

  Future<void> _detach() async {
    await _controller.detach();
    if (!mounted) return;
    if (widget.onClosed != null) {
      widget.onClosed!();
    } else {
      Navigator.of(context).maybePop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final showExtraKeys =
        widget.showExtraKeys ??
        (defaultTargetPlatform == TargetPlatform.android ||
            defaultTargetPlatform == TargetPlatform.iOS);

    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        final readOnly = _controller.isReadOnly;
        return Scaffold(
          appBar: AppBar(
            title: Text(
              _controller.session.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            actions: [
              if (_controller.canSendInput)
                IconButton(
                  key: const Key('device_link_compose_button'),
                  tooltip: 'Send text',
                  onPressed: _compose,
                  icon: const Icon(Icons.edit_note),
                ),
              IconButton(
                key: const Key('device_link_detach_button'),
                tooltip: 'Disconnect',
                onPressed: _detach,
                icon: const Icon(Icons.link_off),
              ),
            ],
          ),
          body: Column(
            children: [
              _buildStatusBar(context, readOnly),
              Expanded(
                child: TerminalScreen(
                  session: _controller.terminalSession,
                  showExtraKeys: showExtraKeys,
                  readOnly: readOnly,
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildStatusBar(BuildContext context, bool readOnly) {
    final theme = Theme.of(context);
    final (label, color, icon) = switch (_controller.status) {
      DeviceLinkLinkedSessionStatus.connecting => (
        'Connecting…',
        theme.colorScheme.primary,
        Icons.sync,
      ),
      DeviceLinkLinkedSessionStatus.attached => (
        'Linked · desktop session is active',
        Colors.green,
        Icons.link,
      ),
      DeviceLinkLinkedSessionStatus.reclaimed => (
        'Desktop control reclaimed · read-only',
        theme.colorScheme.tertiary,
        Icons.desktop_windows,
      ),
      DeviceLinkLinkedSessionStatus.detached => (
        'Disconnected',
        theme.colorScheme.onSurfaceVariant,
        Icons.link_off,
      ),
      DeviceLinkLinkedSessionStatus.disconnected => (
        'Connection lost · read-only',
        theme.colorScheme.error,
        Icons.cloud_off,
      ),
      DeviceLinkLinkedSessionStatus.error => (
        _controller.errorMessage ?? 'Device Link error',
        theme.colorScheme.error,
        Icons.error_outline,
      ),
    };
    return Material(
      color: color.withValues(alpha: 0.12),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        child: Row(
          children: [
            Icon(icon, size: 16, color: color),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                label,
                key: const Key('device_link_status'),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: color, fontSize: 12),
              ),
            ),
            if (readOnly)
              Text(
                'READ ONLY',
                style: TextStyle(
                  color: color,
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.7,
                ),
              ),
          ],
        ),
      ),
    );
  }
}
