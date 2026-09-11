import 'dart:async';

import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../../../../app/widgets/adaptive_modal.dart';
import '../../../../app/widgets/shellvibe_ui.dart';

/// Wraps a multi-line submission in the terminal bracketed-paste protocol.
///
/// The wrapper is deliberately exposed as a pure function so the exact byte
/// contract can be tested without a live WebSocket or camera plugin.
String deviceLinkBracketedPaste(String text) => '\x1b[200~$text\x1b[201~';

String _deviceLinkComposePayload(String text, bool bracketedPaste) =>
    bracketedPaste ? deviceLinkBracketedPaste(text) : text;

/// Compose surface for long text, shell snippets and dictation input.
final class DeviceLinkComposeSheet extends StatefulWidget {
  final FutureOr<void> Function(String bracketedText) onSubmit;
  final String initialText;
  final bool bracketedPaste;

  const DeviceLinkComposeSheet({
    super.key,
    required this.onSubmit,
    this.initialText = '',
    this.bracketedPaste = true,
  });

  static Future<bool?> show(
    BuildContext context, {
    required FutureOr<void> Function(String bracketedText) onSubmit,
    String initialText = '',
    bool bracketedPaste = true,
  }) {
    return showAdaptivePanel<bool>(
      context: context,
      isScrollControlled: true,
      builder: (context) => Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: DeviceLinkComposeSheet(
          onSubmit: onSubmit,
          initialText: initialText,
          bracketedPaste: bracketedPaste,
        ),
      ),
    );
  }

  @override
  State<DeviceLinkComposeSheet> createState() => _DeviceLinkComposeSheetState();
}

class _DeviceLinkComposeSheetState extends State<DeviceLinkComposeSheet> {
  late final TextEditingController _controller;
  late final FocusNode _focusNode;
  bool _submitting = false;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialText);
    _focusNode = FocusNode();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _focusNode.requestFocus();
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_submitting || _controller.text.isEmpty) return;
    setState(() => _submitting = true);
    try {
      await widget.onSubmit(
        _deviceLinkComposePayload(_controller.text, widget.bracketedPaste),
      );
      if (!mounted) return;
      _controller.clear();
      Navigator.of(context).pop(true);
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Send text to terminal', style: theme.textTheme.titleLarge),
            const SizedBox(height: 6),
            Text(
              'Multi-line text is sent as one bracketed paste.',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              key: const Key('device_link_compose_field'),
              controller: _controller,
              focusNode: _focusNode,
              minLines: 5,
              maxLines: 12,
              keyboardType: TextInputType.multiline,
              textInputAction: TextInputAction.newline,
              decoration: const InputDecoration(
                hintText: 'Paste or dictate a command…',
                border: OutlineInputBorder(),
                alignLabelWithHint: true,
              ),
            ),
            const SizedBox(height: 12),
            Align(
              alignment: Alignment.centerRight,
              child: ShellVibeButton(
                key: const Key('device_link_compose_submit'),
                label: 'Send',
                icon: LucideIcons.send,
                onPressed: _submit,
                busy: _submitting,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
