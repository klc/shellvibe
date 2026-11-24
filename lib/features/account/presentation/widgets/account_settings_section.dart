import 'dart:async';

import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../../app/theme/shellvibe_tokens.dart';
import '../../../../app/widgets/adaptive_modal.dart';
import '../../../../app/widgets/shellvibe_ui.dart';
import '../../../../core/api/api_exception.dart';
import '../../../billing/domain/entitlement.dart';
import '../../../device_link/presentation/platform_icon.dart';
import '../../../billing/presentation/notifiers/entitlement_notifier.dart';
import '../../data/account_api.dart';
import '../../domain/account_session.dart';
import '../notifiers/account_notifier.dart';

/// The web panel's danger zone, which deletes an account the same way the app
/// does.
///
/// The app deletes in place through the API. This URL is the fallback offered
/// when that call gets no answer from the API, and the one Play's Data safety
/// form takes.
const String kAccountDeletionUrl = 'https://shellvibe.dev/panel/danger';

/// Account surface in Settings: sign in, plan, devices, sign out, deletion.
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
  bool _busy = false;

  /// The browser sign-in being waited on. Cleared to cancel it.
  BrowserSignIn? _pending;

  String? _formError;

  @override
  Widget build(BuildContext context) {
    final account = ref.watch(accountProvider);
    final tokens = ShellVibeTokens.resolve(context);

    return account.when(
      loading: () => const ShadCard(
        child: Padding(
          padding: EdgeInsets.all(12),
          child: Center(child: CircularProgressIndicator.adaptive()),
        ),
      ),
      error: (error, _) => ShadCard(
        child: _ErrorText('The account state could not be read: $error'),
      ),
      data: (state) {
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
    return ShadCard(
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
          if (_pending case final pending?) ...[
            Text(
              'Finish signing in in your browser. The page there should show '
              'this code:',
              style: TextStyle(fontSize: 13, color: tokens.textSecondary),
            ),
            const SizedBox(height: 8),
            SelectableText(
              pending.userCode,
              key: const Key('account_sign_in_code'),
              style: const TextStyle(
                fontSize: 22,
                fontFamily: 'monospace',
                letterSpacing: 4,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                ShellVibeButton.secondary(
                  buttonKey: const Key('account_sign_in_reopen_button'),
                  label: 'Open Browser Again',
                  icon: LucideIcons.externalLink,
                  onPressed: () => _openSignInPage(pending.verificationUrl),
                ),
                ShellVibeButton.quiet(
                  buttonKey: const Key('account_sign_in_cancel_button'),
                  label: 'Cancel',
                  onPressed: () => setState(() => _pending = null),
                ),
              ],
            ),
          ] else ...[
            if (_formError != null) ...[
              _ErrorText(_formError!),
              const SizedBox(height: 8),
            ],
            ShellVibeButton(
              buttonKey: const Key('account_sign_in_button'),
              label: 'Sign In',
              icon: LucideIcons.logIn,
              busy: _busy,
              onPressed: _busy ? null : _signIn,
            ),
            const SizedBox(height: 8),
            Text(
              'Opens shellvibe.dev in your browser. Sign in or create an '
              'account there with email, Google or GitHub.',
              style: TextStyle(fontSize: 12, color: tokens.textSubtle),
            ),
          ],
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

    return ShadCard(
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
              text: 'Checking your plan…',
            ),
            error: (e, _) => const _PlanRow(
              entitlement: Entitlement.free,
              limitsAreEstimates: true,
            ),
            data: (billing) => _PlanRow(
              entitlement: billing.entitlement,
              limitsAreEstimates: billing.isFromFallback,
            ),
          ),
          const Divider(height: 20),
          // Side by side rather than stacked: these size to their labels, and
          // a left-aligned column of them reads as ragged edges rather than a
          // set of actions.
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              ShellVibeButton.secondary(
                buttonKey: const Key('account_devices_button'),
                label: 'Manage Devices',
                icon: LucideIcons.monitorSmartphone,
                onPressed: () => _showDevices(context),
              ),
              ShellVibeButton.quiet(
                buttonKey: const Key('account_sign_out_button'),
                label: 'Sign Out',
                icon: LucideIcons.logOut,
                busy: _busy,
                onPressed: _busy ? null : () => _signOut(everywhere: false),
              ),
              ShellVibeButton.danger(
                buttonKey: const Key('account_sign_out_all_button'),
                label: 'Sign Out Everywhere',
                icon: LucideIcons.shieldOff,
                busy: _busy,
                onPressed: _busy ? null : () => _signOut(everywhere: true),
              ),
            ],
          ),
          const Divider(height: 20),
          Text(
            'Deleting the account removes it from the server with its '
            'devices, cloud backup and sync history. Hosts and keys on this '
            'device stay.',
            style: TextStyle(fontSize: 12, color: tokens.textMuted),
          ),
          const SizedBox(height: 8),
          ShellVibeButton.quiet(
            buttonKey: const Key('account_delete_button'),
            label: 'Delete Account…',
            icon: LucideIcons.userX,
            onPressed: _busy ? null : () => _deleteAccount(session.email),
          ),
        ],
      ),
    );
  }

  // --- Actions ------------------------------------------------------------

  /// Opens a browser sign-in and polls until it is approved, denied, expired
  /// or cancelled (by clearing [_pending], or by leaving this screen).
  Future<void> _signIn() async {
    final notifier = ref.read(accountProvider.notifier);
    setState(() {
      _busy = true;
      _formError = null;
    });

    BrowserSignIn? request;
    try {
      request = await notifier.startBrowserSignIn();
      if (!mounted) return;
      setState(() {
        _pending = request;
        _busy = false;
      });
      unawaited(_openSignInPage(request.verificationUrl));

      // The server ends the request after ten minutes, but only a server it
      // can reach can say so.
      final deadline = DateTime.now().add(const Duration(minutes: 10));
      while (true) {
        await Future<void>.delayed(request.interval);
        if (!mounted || !identical(_pending, request)) return;
        if (DateTime.now().isAfter(deadline)) {
          setState(
            () => _formError = 'The sign-in link expired. Sign in again.',
          );
          return;
        }
        try {
          if (await notifier.pollBrowserSignIn(request)) break;
        } on ApiTransportException {
          // The person is in the browser; a dropped poll is worth another try.
        } on ApiException catch (e) {
          if (!e.isThrottled) rethrow;
          await Future<void>.delayed(
            Duration(seconds: e.retryAfterSeconds ?? 10),
          );
        }
      }
    } on ApiException catch (e) {
      if (mounted && (request == null || identical(_pending, request))) {
        setState(() => _formError = _messageFor(e));
      }
    } on ApiTransportException catch (e) {
      if (mounted) {
        setState(
          () => _formError = e.timedOut
              ? 'The server did not answer in time.'
              : 'The server could not be reached.',
        );
      }
    } on Object catch (e) {
      debugPrint('Sign-in failed: $e');
      if (mounted) {
        setState(() => _formError = 'Something went wrong. Please try again.');
      }
    } finally {
      if (mounted && (request == null || identical(_pending, request))) {
        setState(() {
          _busy = false;
          _pending = null;
        });
      }
    }
  }

  Future<void> _openSignInPage(String url) async {
    final uri = Uri.tryParse(url);
    var opened = false;
    try {
      opened =
          uri != null &&
          await launchUrl(uri, mode: LaunchMode.externalApplication);
    } on Object catch (e) {
      debugPrint('Opening the sign-in page failed: $e');
    }
    if (opened || !mounted) return;
    ShadToaster.maybeOf(context)?.show(
      ShadToast(
        description: Text('No browser could be opened. Visit $url to sign in.'),
      ),
    );
  }

  /// Turns a failure into one sentence the user can act on.
  ///
  /// Branches on `code` only. The server's `message` is a debug summary and the
  /// contract explicitly does not keep it stable.
  String _messageFor(ApiException e) {
    if (e.code == ApiErrorCode.signInDenied) {
      return 'The sign-in was denied in the browser.';
    }

    if (e.code == ApiErrorCode.signInExpired) {
      return 'The sign-in link expired. Sign in again.';
    }

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
    } on ApiFailure catch (e) {
      // Only signing out everywhere throws: the other devices' tokens are
      // still good, and this one is still signed in to try again.
      debugPrint('Sign-out everywhere failed: $e');
      if (!mounted) return;
      ShadToaster.maybeOf(context)?.show(
        ShadToast.destructive(
          description: Text(
            e is ApiTransportException
                ? 'The server could not be reached, so your other devices are '
                      'still signed in. This device is too; try again.'
                : 'The server did not sign out your other devices. This '
                      'device is still signed in; try again.',
          ),
        ),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _deleteAccount(String email) async {
    final notifier = ref.read(accountProvider.notifier);

    final deleted = await showDialog<bool>(
      context: context,
      builder: (_) => _DeleteAccountDialog(
        email: email,
        delete: (password) => notifier.deleteAccount(password: password),
        openWebPanel: _openAccountDeletion,
      ),
    );
    if (deleted != true || !mounted) return;

    await ref.read(entitlementProvider.notifier).clearCache();
    if (!mounted) return;
    ShadToaster.maybeOf(context)?.show(
      const ShadToast(
        description: Text(
          'The account was deleted. Hosts and keys on this device are '
          'unchanged.',
        ),
      ),
    );
  }

  Future<void> _openAccountDeletion() async {
    final opened = await launchUrl(
      Uri.parse(kAccountDeletionUrl),
      mode: LaunchMode.externalApplication,
    );
    if (opened || !mounted) return;
    ShadToaster.of(context).show(
      const ShadToast(
        description: Text(
          'No browser could be opened. Visit $kAccountDeletionUrl to delete '
          'the account.',
        ),
      ),
    );
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

/// The plan line: which tier, and what this account's quotas are.
///
/// Not a paywall. Every feature is free, so the only thing here a user can
/// act on is a number -- how large a backup may be, how many revisions are
/// kept -- and the tier is named because the server still reports one.
final class _PlanRow extends StatelessWidget {
  const _PlanRow({required this.entitlement, required this.limitsAreEstimates});

  final Entitlement entitlement;

  /// True when the server could not be reached, so the numbers below are this
  /// build's defaults rather than the account's actual quotas.
  final bool limitsAreEstimates;

  @override
  Widget build(BuildContext context) {
    final tokens = ShellVibeTokens.resolve(context);

    final label = switch (entitlement.plan) {
      BillingPlan.free => 'Free',
      BillingPlan.pro => 'Free',
      BillingPlan.team => 'Team',
    };

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(LucideIcons.badgeCheck, size: 16, color: tokens.success),
            const SizedBox(width: 8),
            Text(
              '$label plan',
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
            ),
          ],
        ),
        const SizedBox(height: 6),
        Text(
          'Cloud backup, sync and remote Device Link are included: up to '
          '${_megabytes(entitlement.limits.maxBackupSizeBytes)} per backup '
          'and ${entitlement.limits.maxBackupRevisions} revisions kept.',
          style: TextStyle(fontSize: 12, color: tokens.textMuted),
        ),
        if (limitsAreEstimates) ...[
          const SizedBox(height: 4),
          Text(
            'Your plan could not be checked just now, so these are the '
            'standard limits rather than this account\'s.',
            style: TextStyle(fontSize: 11, color: tokens.textSubtle),
          ),
        ],
      ],
    );
  }

  static String _megabytes(int bytes) =>
      '${(bytes / (1024 * 1024)).toStringAsFixed(bytes % (1024 * 1024) == 0 ? 0 : 1)} MB';
}

/// Asks for the password and deletes the account in place, so a wrong
/// password or a refusal is answered here rather than by reopening it.
///
/// Pops `true` once the server has erased the account.
final class _DeleteAccountDialog extends StatefulWidget {
  const _DeleteAccountDialog({
    required this.email,
    required this.delete,
    required this.openWebPanel,
  });

  final String email;
  final Future<void> Function(String password) delete;
  final VoidCallback openWebPanel;

  @override
  State<_DeleteAccountDialog> createState() => _DeleteAccountDialogState();
}

class _DeleteAccountDialogState extends State<_DeleteAccountDialog> {
  final _password = TextEditingController();

  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _password.dispose();
    super.dispose();
  }

  bool get _canSubmit => !_busy && _password.text.isNotEmpty;

  Future<void> _submit() async {
    if (!_canSubmit) return;
    setState(() {
      _busy = true;
      _error = null;
    });

    String? error;
    try {
      await widget.delete(_password.text);
      if (mounted) Navigator.of(context).pop(true);
      return;
    } on ApiException catch (e) {
      error = _messageFor(e);
    } on ApiTransportException catch (e) {
      error = e.timedOut
          ? 'The server did not answer in time.'
          : 'The server could not be reached.';
    } on Object catch (e) {
      error = '$e';
    }

    if (!mounted) return;
    setState(() {
      _busy = false;
      _error = error;
    });
  }

  /// Branches on `code` only, like the sign-in form.
  static String _messageFor(ApiException e) {
    if (e.code == ApiErrorCode.invalidCredentials) {
      return 'That password does not match this account.';
    }

    if (e.code == ApiErrorCode.accountOwnsSharedTeam) {
      return 'You own a team other people still belong to, and deleting the '
          'account would take their shared workspaces with it. Hand the team '
          'over or remove its members first.';
    }

    if (e.isUnauthenticated) {
      return 'This device is no longer signed in. Sign in again, then delete '
          'the account.';
    }

    if (e.isThrottled) {
      final seconds = e.retryAfterSeconds;

      return seconds == null
          ? 'Too many attempts. Wait a moment and try again.'
          : 'Too many attempts. Try again in $seconds seconds.';
    }

    if (e.isValidationFailure) {
      return e.validationErrors['password']?.first ?? 'Enter your password.';
    }

    return 'The account could not be deleted (${e.code}).'
        '${e.requestId == null ? '' : ' Reference: ${e.requestId}.'}';
  }

  @override
  Widget build(BuildContext context) {
    final tokens = ShellVibeTokens.resolve(context);
    final bodyStyle = TextStyle(fontSize: 13, color: tokens.textSecondary);
    final account = widget.email.isEmpty ? 'the account' : widget.email;

    // Held open while the request is out, so the result lands where the user
    // can read it rather than after a tap outside has dismissed it.
    return PopScope(
      canPop: !_busy,
      child: ShadDialog.alert(
        key: const Key('account_delete_dialog'),
        title: const Text('Delete Account?'),
        description: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'This permanently deletes $account '
              'from the ShellVibe server, with every device signed in to it, its '
              'cloud backups and its sync history. It cannot be undone.',
              style: bodyStyle,
            ),
            const SizedBox(height: 8),
            Text(
              'Hosts, keys and settings on this device are not touched.',
              style: bodyStyle,
            ),
            const SizedBox(height: 12),
            ShadInput(
              key: const Key('account_delete_password'),
              controller: _password,
              obscureText: true,
              autofocus: true,
              enabled: !_busy,
              placeholder: const Text('Password'),
              onChanged: (_) => setState(() {}),
              onSubmitted: (_) => _submit(),
            ),
            if (_error != null) ...[
              const SizedBox(height: 8),
              _ErrorText(_error!),
            ],
            // The same deletion by another road: for an account opened with
            // Google or GitHub, which has no password to type here but
            // confirms with its provider there, and for when the API is down.
            const SizedBox(height: 12),
            Text(
              'Signed up with Google or GitHub? The account has no password; '
              'delete it in the web panel instead.',
              style: TextStyle(fontSize: 12, color: tokens.textMuted),
            ),
            const SizedBox(height: 4),
            ShellVibeButton.quiet(
              buttonKey: const Key('account_delete_web_panel'),
              label: 'Delete in the Web Panel',
              icon: LucideIcons.externalLink,
              onPressed: () {
                Navigator.of(context).pop(false);
                widget.openWebPanel();
              },
            ),
          ],
        ),
        actions: adaptiveDialogActions(context, [
          ShellVibeButton.secondary(
            buttonKey: const Key('account_delete_cancel'),
            label: 'Cancel',
            onPressed: _busy ? null : () => Navigator.of(context).pop(false),
          ),
          ShellVibeButton.danger(
            buttonKey: const Key('account_delete_confirm'),
            label: 'Delete Account',
            busy: _busy,
            onPressed: _canSubmit ? _submit : null,
          ),
        ]),
        actionsAxis: adaptiveDialogActionsAxis(context),
      ),
    );
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
              return _ErrorText(
                'Devices could not be loaded: '
                '${snapshot.error}',
              );
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
                    leading: Icon(platformIcon(device.platform), size: 18),
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
    style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.error),
  );
}
