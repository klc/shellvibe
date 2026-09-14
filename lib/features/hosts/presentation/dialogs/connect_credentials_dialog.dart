import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../../../../app/theme/shellvibe_tokens.dart';
import '../../../../app/widgets/adaptive_modal.dart';
import '../../../../app/widgets/shellvibe_ui.dart';

/// What the caller got back from [ConnectCredentialsDialog].
class ConnectCredentials {
  final String username;
  final String password;

  const ConnectCredentials({required this.username, required this.password});
}

/// Asks for the credentials of a host bound to no stored identity.
///
/// A host whose identity is "(None — Prompt on Connect)" has to be asked for
/// them somewhere, and this is that prompt. Nothing typed here is persisted:
/// the credentials live only as long as the connection attempt that asked.
class ConnectCredentialsDialog extends StatefulWidget {
  final String hostLabel;
  final String hostname;
  final int port;

  /// The host's own username, when it has one. Empty means the prompt has to
  /// collect that too.
  final String username;

  const ConnectCredentialsDialog({
    super.key,
    required this.hostLabel,
    required this.hostname,
    required this.port,
    required this.username,
  });

  static Future<ConnectCredentials?> show(
    BuildContext context, {
    required String hostLabel,
    required String hostname,
    required int port,
    required String username,
  }) {
    return showDialog<ConnectCredentials>(
      context: context,
      builder: (ctx) => ConnectCredentialsDialog(
        hostLabel: hostLabel,
        hostname: hostname,
        port: port,
        username: username,
      ),
    );
  }

  @override
  State<ConnectCredentialsDialog> createState() =>
      _ConnectCredentialsDialogState();
}

class _ConnectCredentialsDialogState extends State<ConnectCredentialsDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _usernameController;
  final _passwordController = TextEditingController();
  bool _obscurePassword = true;

  @override
  void initState() {
    super.initState();
    _usernameController = TextEditingController(text: widget.username);
  }

  @override
  void dispose() {
    _usernameController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  void _submit() {
    if (!_formKey.currentState!.validate()) return;
    Navigator.of(context).pop(
      ConnectCredentials(
        username: _usernameController.text.trim(),
        password: _passwordController.text,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final tokens = ShellVibeTokens.resolve(context);

    return ShadDialog(
      title: const Text('Authenticate'),
      description: Text(
        '${widget.hostLabel} (${widget.hostname}:${widget.port}) has no '
        'identity in the Vault. These credentials are used for this '
        'connection only and are not saved.',
        style: Theme.of(
          context,
        ).textTheme.bodySmall?.copyWith(color: tokens.textSecondary),
      ),
      actions: adaptiveDialogActions(context, [
        ShellVibeButton.secondary(
          key: const Key('connect_credentials_cancel_button'),
          label: 'Cancel',
          onPressed: () => Navigator.of(context).pop(),
        ),
        ShellVibeButton(
          buttonKey: const Key('connect_credentials_submit_button'),
          label: 'Connect',
          onPressed: _submit,
        ),
      ]),
      actionsAxis: adaptiveDialogActionsAxis(context),
      child: SizedBox(
        width: double.infinity,
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 8),
              ShadInputFormField(
                key: const Key('connect_username_input'),
                controller: _usernameController,
                label: const Text('Username'),
                placeholder: const Text('e.g. root, ubuntu'),
                leading: const Icon(LucideIcons.user, size: 16),
                validator: (v) =>
                    v.trim().isEmpty ? 'Username is required' : null,
              ),
              const SizedBox(height: 12),
              ShadInputFormField(
                key: const Key('connect_password_input'),
                controller: _passwordController,
                obscureText: _obscurePassword,
                label: const Text('Password'),
                leading: const Icon(LucideIcons.lock, size: 16),
                onSubmitted: (_) => _submit(),
                validator: (v) => v.isEmpty ? 'Password is required' : null,
                trailing: ShellVibeIconButton(
                  icon: _obscurePassword ? LucideIcons.eye : LucideIcons.eyeOff,
                  tooltip: _obscurePassword ? 'Show password' : 'Hide password',
                  onPressed: () =>
                      setState(() => _obscurePassword = !_obscurePassword),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
