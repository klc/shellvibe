import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../../../../app/theme/shellvibe_tokens.dart';
import '../../../../app/widgets/shellvibe_ui.dart';
import '../../../../core/api/api_exception.dart';
import '../../../billing/domain/entitlement.dart';
import '../../../billing/presentation/notifiers/entitlement_notifier.dart';
import '../../domain/account_session.dart';
import '../notifiers/account_notifier.dart';

/// Account surface in Settings: sign in, plan, devices, sign out.
///
/// Signing in is optional everywhere in this widget. The copy says what an
/// account is *for* rather than asking for one, because everything the app
/// does today keeps working without it.
final class AccountSettingsSection extends ConsumerStatefulWidget {
  const AccountSettingsSection({super.key});

  @override
  ConsumerState<AccountSettingsSection> createState() =>
      _AccountSettingsSectionState();
}

class _AccountSettingsSectionState
    extends ConsumerState<AccountSettingsSection> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _nameController = TextEditingController();

  /// True while the form is in "create account" mode rather than "sign in".
  bool _isRegistering = false;

  bool _busy = false;

  /// Field errors from a `422`, keyed by the server's field names.
  Map<String, List<String>> _fieldErrors = const {};

  /// A single message for failures that are not field-shaped.
  String? _formError;

  /// Whether the email field has been seeded from the stored last-used email.
  bool _emailPrefilled = false;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    _nameController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final account = ref.watch(accountProvider);
    final tokens = ShellVibeTokens.resolve(context);

    return account.when(
      loading: () => const _SectionCard(
        child: Padding(
          padding: EdgeInsets.all(12),
          child: Center(child: CircularProgressIndicator.adaptive()),
        ),
      ),
      error: (error, _) => _SectionCard(
        child: _ErrorText('The account state could not be read: $error'),
      ),
      data: (state) {
        _prefillEmail(state.lastEmail);

        return state.isSignedIn
            ? _buildSignedIn(context, tokens, state.session!)
            : _buildSignedOut(context, tokens, state.status);
      },
    );
  }

  // --- Signed out ---------------------------------------------------------

  Widget _buildSignedOut(
    BuildContext context,
    ShellVibeTokens tokens,
    AccountStatus status,
  ) {
    return _SectionCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (status == AccountStatus.sessionExpired)
            _Notice(
              icon: LucideIcons.triangleAlert,
              color: tokens.warning,
              // Saying *why* matters: an empty form with no explanation reads
              // as the app having forgotten the account.
              text:
                  'This device was signed out by the server. Sign in again to '
                  'reach cloud backup.',
            )
          else
            Text(
              'An account is only needed for cloud backup. The terminal, SSH, '
              'the vault and Local Device Link work without one.',
              style: TextStyle(fontSize: 13, color: tokens.textMuted),
            ),
          const SizedBox(height: 12),
          if (_isRegistering) ...[
            _Field(
              label: 'Name',
              controller: _nameController,
              errors: _fieldErrors['name'],
              placeholder: 'How the account is addressed',
            ),
            const SizedBox(height: 8),
          ],
          _Field(
            label: 'Email',
            controller: _emailController,
            errors: _fieldErrors['email'],
            placeholder: 'you@example.com',
            keyboardType: TextInputType.emailAddress,
          ),
          const SizedBox(height: 8),
          _Field(
            label: 'Password',
            controller: _passwordController,
            errors: _fieldErrors['password'],
            placeholder: _isRegistering ? 'At least 8 characters' : 'Password',
            obscure: true,
          ),
          if (_formError != null) ...[
            const SizedBox(height: 8),
            _ErrorText(_formError!),
          ],
          const SizedBox(height: 12),
          ShellVibeButton(
            buttonKey: const Key('account_submit_button'),
            label: _isRegistering ? 'Create Account' : 'Sign In',
            icon: _isRegistering ? LucideIcons.userPlus : LucideIcons.logIn,
            expand: true,
            busy: _busy,
            onPressed: _busy ? null : _submit,
          ),
          const SizedBox(height: 8),
          ShellVibeButton.quiet(
            buttonKey: const Key('account_toggle_mode_button'),
            label: _isRegistering
                ? 'I already have an account'
                : 'Create an account instead',
            expand: true,
            onPressed: _busy
                ? null
                : () => setState(() {
                    _isRegistering = !_isRegistering;
                    _fieldErrors = const {};
                    _formError = null;
                  }),
          ),
        ],
      ),
    );
  }

  // --- Signed in ----------------------------------------------------------

  Widget _buildSignedIn(
    BuildContext context,
    ShellVibeTokens tokens,
    AccountSession session,
  ) {
    final entitlement = ref.watch(entitlementProvider);

    return _SectionCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(LucideIcons.circleUser, size: 20),
            title: Text(session.email.isEmpty ? session.name : session.email),
            subtitle: Text(
              'This device: ${session.deviceId}',
              style: TextStyle(fontSize: 11, color: tokens.textSubtle),
            ),
          ),
          const Divider(height: 20),
          entitlement.when(
            loading: () => const _Notice(
              icon: LucideIcons.loader,
              text: 'Checking your subscription…',
            ),
            error: (e, _) => _PlanRow(
              entitlement: Entitlement.free,
              lockedByUnavailability: true,
            ),
            data: (billing) => _PlanRow(
              entitlement: billing.entitlement,
              lockedByUnavailability: billing.isLockedByUnavailability,
            ),
          ),
          const Divider(height: 20),
          ShellVibeButton.secondary(
            buttonKey: const Key('account_devices_button'),
            label: 'Devices on this account',
            icon: LucideIcons.monitorSmartphone,
            expand: true,
            onPressed: () => _showDevices(context),
          ),
          const SizedBox(height: 8),
          ShellVibeButton.quiet(
            buttonKey: const Key('account_sign_out_button'),
            label: 'Sign Out',
            icon: LucideIcons.logOut,
            expand: true,
            busy: _busy,
            onPressed: _busy ? null : () => _signOut(everywhere: false),
          ),
          const SizedBox(height: 8),
          ShellVibeButton.danger(
            buttonKey: const Key('account_sign_out_all_button'),
            label: 'Sign Out Everywhere',
            icon: LucideIcons.shieldOff,
            expand: true,
            busy: _busy,
            onPressed: _busy ? null : () => _signOut(everywhere: true),
          ),
        ],
      ),
    );
  }

  // --- Actions ------------------------------------------------------------

  void _prefillEmail(String? email) {
    if (_emailPrefilled || email == null || email.isEmpty) return;
    _emailPrefilled = true;
    _emailController.text = email;
  }

  Future<void> _submit() async {
    setState(() {
      _busy = true;
      _fieldErrors = const {};
      _formError = null;
    });

    try {
      final notifier = ref.read(accountProvider.notifier);
      if (_isRegistering) {
        await notifier.register(
          name: _nameController.text.trim(),
          email: _emailController.text.trim(),
          password: _passwordController.text,
        );
      } else {
        await notifier.signIn(
          email: _emailController.text.trim(),
          password: _passwordController.text,
        );
      }

      _passwordController.clear();
    } on ApiException catch (e) {
      setState(() {
        _fieldErrors = e.validationErrors;
        _formError = _messageFor(e);
      });
    } on ApiTransportException catch (e) {
      setState(() => _formError = e.timedOut
          ? 'The server did not answer in time.'
          : 'The server could not be reached.');
    } on Object catch (e) {
      setState(() => _formError = '$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Turns a failure into one sentence the user can act on.
  ///
  /// Branches on `code` only. The server's `message` is a debug summary and the
  /// contract explicitly does not keep it stable.
  String? _messageFor(ApiException e) {
    if (e.isValidationFailure) {
      // The fields carry their own errors; a duplicate summary above them
      // would just be noise.
      return e.validationErrors.isEmpty ? 'Check the form and try again.' : null;
    }

    if (e.isUnauthenticated) return 'That email and password do not match.';

    if (e.isThrottled) {
      final seconds = e.retryAfterSeconds;

      return seconds == null
          ? 'Too many attempts. Wait a moment and try again.'
          : 'Too many attempts. Try again in $seconds seconds.';
    }

    return 'Sign-in failed (${e.code}).'
        '${e.requestId == null ? '' : ' Reference: ${e.requestId}.'}';
  }

  Future<void> _signOut({required bool everywhere}) async {
    setState(() => _busy = true);
    try {
      await ref.read(accountProvider.notifier).signOut(everywhere: everywhere);
      await ref.read(entitlementProvider.notifier).clearCache();
      _passwordController.clear();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _showDevices(BuildContext context) async {
    final notifier = ref.read(accountProvider.notifier);

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (sheetContext) => _DeviceListSheet(
        load: notifier.devices,
        onRevoke: notifier.revokeDevice,
      ),
    );
  }
}

// --- Presentation-only pieces ---------------------------------------------

/// The plan line: tier, state, and what the limits actually are.
final class _PlanRow extends StatelessWidget {
  const _PlanRow({
    required this.entitlement,
    required this.lockedByUnavailability,
  });

  final Entitlement entitlement;
  final bool lockedByUnavailability;

  @override
  Widget build(BuildContext context) {
    final tokens = ShellVibeTokens.resolve(context);

    if (lockedByUnavailability) {
      return _Notice(
        icon: LucideIcons.cloudOff,
        color: tokens.warning,
        // Not the same sentence as "you need Pro": this one asks the user to
        // get back online, not to pay.
        text:
            'Your subscription could not be checked, so paid features are '
            'off for now. They come back when this device reaches the server.',
      );
    }

    final label = switch (entitlement.plan) {
      BillingPlan.free => 'Free',
      BillingPlan.pro => 'Pro',
      BillingPlan.team => 'Team',
    };

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(LucideIcons.badgeCheck, size: 16, color: tokens.brand),
            const SizedBox(width: 8),
            Text(
              '$label plan',
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
            ),
            if (entitlement.isInGracePeriod) ...[
              const SizedBox(width: 8),
              Text(
                '· payment overdue',
                style: TextStyle(fontSize: 12, color: tokens.warning),
              ),
            ],
          ],
        ),
        const SizedBox(height: 6),
        Text(
          entitlement.hasCloudBackup
              ? 'Cloud backup is included: up to '
                  '${_megabytes(entitlement.limits.maxBackupSizeBytes)} per '
                  'backup and ${entitlement.limits.maxBackupRevisions} '
                  'revisions kept.'
              : 'Cloud backup is not included in this plan.',
          style: TextStyle(fontSize: 12, color: tokens.textMuted),
        ),
        if (entitlement.expiresAt != null) ...[
          const SizedBox(height: 4),
          Text(
            'Renews or ends ${_date(entitlement.expiresAt!)}.',
            style: TextStyle(fontSize: 11, color: tokens.textSubtle),
          ),
        ],
      ],
    );
  }

  static String _megabytes(int bytes) =>
      '${(bytes / (1024 * 1024)).toStringAsFixed(bytes % (1024 * 1024) == 0 ? 0 : 1)} MB';

  static String _date(DateTime value) {
    final local = value.toLocal();

    return '${local.year}-${local.month.toString().padLeft(2, '0')}-'
        '${local.day.toString().padLeft(2, '0')}';
  }
}

/// Device list, loaded when opened rather than kept in memory.
final class _DeviceListSheet extends StatefulWidget {
  const _DeviceListSheet({required this.load, required this.onRevoke});

  final Future<List<AccountDevice>> Function() load;
  final Future<void> Function(String deviceId) onRevoke;

  @override
  State<_DeviceListSheet> createState() => _DeviceListSheetState();
}

class _DeviceListSheetState extends State<_DeviceListSheet> {
  late Future<List<AccountDevice>> _devices;

  @override
  void initState() {
    super.initState();
    _devices = widget.load();
  }

  @override
  Widget build(BuildContext context) {
    final tokens = ShellVibeTokens.resolve(context);

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: FutureBuilder<List<AccountDevice>>(
          future: _devices,
          builder: (context, snapshot) {
            if (snapshot.connectionState != ConnectionState.done) {
              return const Padding(
                padding: EdgeInsets.all(24),
                child: Center(child: CircularProgressIndicator.adaptive()),
              );
            }

            if (snapshot.hasError) {
              return _ErrorText('Devices could not be loaded: '
                  '${snapshot.error}');
            }

            final devices = snapshot.data ?? const <AccountDevice>[];
            if (devices.isEmpty) {
              return Text(
                'No devices are registered to this account.',
                style: TextStyle(color: tokens.textMuted),
              );
            }

            return Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Devices',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 8),
                for (final device in devices)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(_iconFor(device.platform), size: 18),
                    title: Text(device.name),
                    subtitle: Text(
                      device.isRevoked
                          ? '${device.platform} · revoked'
                          : device.platform,
                      style: TextStyle(fontSize: 11, color: tokens.textSubtle),
                    ),
                    trailing: device.isRevoked
                        ? null
                        : ShellVibeIconButton(
                            icon: LucideIcons.trash2,
                            tooltip: 'Revoke this device',
                            danger: true,
                            onPressed: () async {
                              await widget.onRevoke(device.id);
                              if (!context.mounted) return;
                              setState(() => _devices = widget.load());
                            },
                          ),
                  ),
              ],
            );
          },
        ),
      ),
    );
  }

  /// Maps a platform string to a glyph, tolerating values this build has never
  /// seen -- the contract allows new ones.
  static IconData _iconFor(String platform) => switch (platform) {
    'ios' || 'android' => LucideIcons.smartphone,
    'macos' => LucideIcons.laptop,
    'windows' || 'linux' => LucideIcons.monitor,
    'web' => LucideIcons.globe,
    _ => LucideIcons.circleHelp,
  };
}

final class _SectionCard extends StatelessWidget {
  const _SectionCard({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => ShadCard(child: child);
}

final class _Field extends StatelessWidget {
  const _Field({
    required this.label,
    required this.controller,
    this.errors,
    this.placeholder,
    this.obscure = false,
    this.keyboardType,
  });

  final String label;
  final TextEditingController controller;
  final List<String>? errors;
  final String? placeholder;
  final bool obscure;
  final TextInputType? keyboardType;

  @override
  Widget build(BuildContext context) {
    final tokens = ShellVibeTokens.resolve(context);
    final fieldErrors = errors ?? const [];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(fontSize: 12, color: tokens.textSecondary),
        ),
        const SizedBox(height: 4),
        ShadInput(
          key: Key('account_field_${label.toLowerCase()}'),
          controller: controller,
          obscureText: obscure,
          keyboardType: keyboardType,
          placeholder: placeholder == null ? null : Text(placeholder!),
        ),
        for (final error in fieldErrors)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: _ErrorText(error),
          ),
      ],
    );
  }
}

final class _Notice extends StatelessWidget {
  const _Notice({required this.icon, required this.text, this.color});

  final IconData icon;
  final String text;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final tokens = ShellVibeTokens.resolve(context);
    final tint = color ?? tokens.textMuted;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 16, color: tint),
        const SizedBox(width: 8),
        Expanded(
          child: Text(text, style: TextStyle(fontSize: 13, color: tint)),
        ),
      ],
    );
  }
}

final class _ErrorText extends StatelessWidget {
  const _ErrorText(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Text(
    text,
    style: TextStyle(
      fontSize: 12,
      color: Theme.of(context).colorScheme.error,
    ),
  );
}
